// MARK: - 职责说明：R04 撤销条单元测试（docs/16 M12 Phase 4）——
// 基线红：① 环层叠在「撤销」文字上（undoButton.layer + toast layoutSubviews 画环）；
// ② 双时钟（DSToast 30fps 自算到期 vs UndoCenter 0.25s Timer）；③ effectView/按钮 equal 44
// 硬约束在 XXXL 动态字体下裁切；④ 多选 Toast 位置 -(84+12) 魔法数。

import XCTest
import UIKit
import Photos
import AVFoundation
import PhotoDeskCore
@testable import PhotoDesk

/// 可注入时钟（PhotoDeskCore.Clock）
private final class MockClock: PhotoDeskCore.Clock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 100_000)) {
        self.now = now
    }
}

@MainActor
final class DSToastUndoTests: XCTestCase {
    // MARK: - 夹具

    private func makeToast(width: CGFloat = 340) -> DSToast {
        let toast = DSToast(frame: CGRect(x: 0, y: 0, width: width, height: 48))
        toast.layoutIfNeeded()
        return toast
    }

    // MARK: - 环与文字不重叠（R04 ①）

    func testCountdownRingDoesNotOverlapUndoLabel() {
        let toast = makeToast()
        toast.show(icon: "eye.slash.fill",
                   text: "已加入待隐藏 · 撤销",
                   duration: 5,
                   allowUndo: true,
                   onUndo: nil,
                   onDismissFinished: nil)
        toast.layoutIfNeeded()
        let ring = toast.test_countdownRingView
        XCTAssertFalse(ring.isHidden, "allowUndo 时环必须可见")
        let ringFrame = toast.convert(ring.frame, to: toast)
        let buttonFrame = toast.convert(toast.test_undoButton.frame, to: toast)
        let messageFrame = toast.convert(toast.test_messageLabel.frame, to: toast)
        XCTAssertLessThanOrEqual(ringFrame.maxX, buttonFrame.minX + 0.5,
                                 "环必须在「撤销」按钮外侧（旧版 ringLayer 叠在按钮上）：ring=\(ringFrame) button=\(buttonFrame)")
        XCTAssertLessThanOrEqual(messageFrame.maxX, ringFrame.minX + 0.5,
                                 "环不得压住文案：message=\(messageFrame) ring=\(ringFrame)")
        XCTAssertGreaterThan(ringFrame.width, 0)
        // 环路径在自身 layoutSubviews 计算：自身 bounds 必须非零
        XCTAssertEqual(ring.bounds.width, DSSpacing.toastRingSize, accuracy: 0.5)
    }

    // MARK: - allowUndo=false 无环（回归守卫）

    func testAllowUndoFalseHasNoRing() {
        let toast = makeToast()
        toast.show(icon: "checkmark.circle.fill",
                   text: "已完成 3 项",
                   duration: 3,
                   allowUndo: false,
                   onUndo: nil,
                   onDismissFinished: nil)
        toast.layoutIfNeeded()
        XCTAssertTrue(toast.test_countdownRingView.isHidden, "allowUndo=false 时环必须隐藏且不注册驱动")
        XCTAssertTrue(toast.test_undoButton.isHidden)
    }

    // MARK: - 动态字体不裁切（R04 ③：结构断言——equal 44 硬约束必须消失）

    func testDynamicTypeXXXLToastNotClipped() {
        let toast = makeToast()
        let button = toast.test_undoButton
        let effectView = toast.test_effectView
        let buttonHeights = Self.constraints(on: [toast, effectView, button],
                                             firstItem: button,
                                             attribute: .height)
        XCTAssertTrue(buttonHeights.contains { $0.relation == .greaterThanOrEqual && $0.constant >= 44 },
                      "「撤销」按钮必须有 >= 44 最小命中区")
        XCTAssertFalse(buttonHeights.contains { $0.relation == .equal && $0.constant == 44 },
                       "不得再有 equal 44 硬约束（XXXL 放大字体下裁切根因）：\(buttonHeights)")
        let effectHeights = Self.constraints(on: [toast, effectView, button],
                                             firstItem: effectView,
                                             attribute: .height)
        XCTAssertFalse(effectHeights.contains { $0.relation == .equal && $0.constant == 44 },
                       "effectView 不得再有 equal 44 硬约束：\(effectHeights)")
        XCTAssertTrue(effectHeights.contains { $0.relation == .greaterThanOrEqual && $0.constant >= 44 },
                      "effectView 高度必须为 >= 44 下限约束")
    }

    private static func constraints(on owners: [UIView],
                                    firstItem: AnyObject,
                                    attribute: NSLayoutConstraint.Attribute) -> [NSLayoutConstraint] {
        var result: [NSLayoutConstraint] = []
        for owner in owners {
            for constraint in owner.constraints
            where constraint.firstItem === firstItem && constraint.firstAttribute == attribute {
                result.append(constraint)
            }
        }
        return result
    }

    // MARK: - 唯一时钟（R04 ②）

    /// UndoCenter 到期与驱动同刻：5s 窗口，4.95s 未到期、5.05s 必须到期
    func testCountdownAndUndoExpireTogether() {
        let clock = MockClock()
        let driver = UndoCountdownDriver(clock: clock)
        let undoCenter = UndoCenter(writer: MockPhotoWriter(),
                                    trashBin: nil,
                                    persistence: PersistenceController(inMemory: true),
                                    clock: clock,
                                    countdownDriver: driver)
        var expired = false
        undoCenter.onExpire = { _ in expired = true }
        _ = undoCenter.push(kind: .favorite,
                            assetIDs: ["asset-x"],
                            toastText: "已收藏",
                            window: 5)
        XCTAssertNotNil(undoCenter.activeEntry)

        clock.now = clock.now.addingTimeInterval(4.95)
        driver.fireIfExpiredForTesting()
        XCTAssertFalse(expired, "4.95s 不得提前到期")
        XCTAssertNotNil(undoCenter.activeEntry)

        clock.now = clock.now.addingTimeInterval(0.10)
        driver.fireIfExpiredForTesting()
        XCTAssertTrue(expired, "5.05s 必须到期（环归零 / 按钮失效 / 实际撤销截止三者同刻，误差 ≤ 0.1s）")
        XCTAssertNil(undoCenter.activeEntry)
    }

    /// 驱动语义：tick 单调、到期恰好触发一次、cancel 后不再触发
    func testDriverExpireFiresOnceAndStops() {
        let clock = MockClock()
        let driver = UndoCountdownDriver(clock: clock)
        var lastFraction = 1.0
        var expireCount = 0
        let id = driver.start(duration: 1,
                              onTick: { lastFraction = $0 },
                              onExpire: { expireCount += 1 })
        clock.now = clock.now.addingTimeInterval(0.5)
        driver.fireIfExpiredForTesting()
        XCTAssertEqual(lastFraction, 0.5, accuracy: 0.01, "半程环应剩 50%")
        XCTAssertEqual(expireCount, 0)

        clock.now = clock.now.addingTimeInterval(0.6)
        driver.fireIfExpiredForTesting()
        XCTAssertEqual(expireCount, 1, "到期必须恰好触发一次")
        XCTAssertEqual(lastFraction, 0, accuracy: 0.01, "到期时环归零")

        clock.now = clock.now.addingTimeInterval(2)
        driver.fireIfExpiredForTesting()
        driver.cancel(id: id)
        XCTAssertEqual(expireCount, 1, "cancel/过期后不得重复触发")
    }

    // MARK: - Toast 位置约束引用切换（R04 ④：去 -(84+12) 魔法数）

    func testToastPositionUsesSafeAreaAndSelectionBarConstraint() {
        let store = LibraryPositionStore(defaults: (UserDefaults(suiteName: "M12ToastPos-\(UUID())") ?? .standard))
        let viewModel = LibraryViewModel(service: PhotoLibraryService(initialAccess: .authorized),
                                         repository: FakeToastRepo(),
                                         pipeline: FakeToastPipeline(),
                                         writer: MockPhotoWriter(),
                                         trashBin: TrashBin(persistence: PersistenceController(inMemory: true),
                                                             settings: SettingsStore()),
                                         undoCenter: UndoCenter(writer: MockPhotoWriter(),
                                                                trashBin: nil,
                                                                persistence: PersistenceController(inMemory: true)),
                                         settings: settings,
                                         reviewSession: session,
                                         positionStore: store)
        let controller = LibraryViewController(viewModel: viewModel,
                                               pipeline: FakeToastPipeline(),
                                               settings: settings,
                                               positionStore: store)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        // 常规态：贴 safeArea 底部 - toastBottomOffset
        let toast = controller.test_batchToast
        let selectionBar = controller.test_selectionBar
        XCTAssertEqual(toast.frame.maxY,
                       controller.view.safeAreaLayoutGuide.layoutFrame.maxY - DSSpacing.toastBottomOffset,
                       accuracy: 1.0,
                       "常规态 Toast 应贴 safeArea 底部（-DSSpacing.toastBottomOffset）")

        // 多选态：贴 selectionBar 顶部 - toastBottomOffset（旧版 -(84+12) = -12 间距 → 断言红）
        controller.toggleSelectionMode()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.isSelecting)
        XCTAssertEqual(toast.frame.maxY,
                       selectionBar.frame.minY - DSSpacing.toastBottomOffset,
                       accuracy: 1.0,
                       "多选态 Toast 应贴多选工具栏顶部 -DSSpacing.toastBottomOffset（旧版魔法数 12 ≠ 16）")

        // 退出恢复
        controller.toggleSelectionMode()
        controller.view.layoutIfNeeded()
        XCTAssertFalse(controller.isSelecting)
        XCTAssertEqual(toast.frame.maxY,
                       controller.view.safeAreaLayoutGuide.layoutFrame.maxY - DSSpacing.toastBottomOffset,
                       accuracy: 1.0, "退出多选后恢复 safeArea 底部")
    }

    private var settings: SettingsStore!
    private var session: ReviewSessionController!

    override func setUp() async throws {
        settings = SettingsStore()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("M12Toast-\(UUID().uuidString)", isDirectory: true)
        session = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                          writer: MockPhotoWriter(), trashBin: nil, settings: settings)
    }
}

/// 极简仓库/管道 fake（Toast 位置测试不取图、不取库）
private final class FakeToastRepo: AssetRepositoryProtocol {
    func prepare(scope: PhotoScope) async -> Int { 0 }
    func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int { 0 }
    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] { [] }
    func globalIndex(of assetID: String, scope: PhotoScope) async -> Int? { nil }
    func count(scope: PhotoScope) async -> Int { 0 }
    func fetch(ids: [String]) async -> [PhotoItem] { [] }
    var latestResult: PHFetchResult<PHAsset>? { nil }
    func latestResult(for scope: PhotoScope) -> PHFetchResult<PHAsset>? { nil }
    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope) {}
    func map(_ asset: PHAsset) -> PhotoItem {
        PhotoItem(id: "placeholder", mediaType: .image, mediaSubtypes: [],
                  creationDate: nil, modificationDate: nil, pixelWidth: 1, pixelHeight: 1,
                  duration: 0, isFavorite: false, isHidden: false, location: nil,
                  burstIdentifier: nil, isCloudOnly: false)
    }
}

@MainActor
private final class FakeToastPipeline: ImagePipelineProtocol {
    func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage? { nil }
    func prefetch(ids: [String], size: CGSize) {}
    func cancel(id: String) {}
    func cancelAll() {}
    func fullImageWithState(for id: String, progress: @escaping (Double) -> Void,
                            allowNetwork: Bool) async -> FullImageResult {
        FullImageResult(image: nil, isInCloud: false)
    }
    func videoAsset(for id: String) async -> (asset: AVAsset, audioMix: AVAudioMix?)? { nil }
    var diskCacheBytes: Int64 { 0 }
    func clearCaches() {}
}
