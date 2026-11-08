// MARK: - 职责说明：R03 位置记忆恢复单元测试（docs/16 M12 Phase 3）——
// 基线红：① 首批固定「最新 500」（深月份锚点不在首屏 → 两阶段可见跳转）；
// ② 恢复期间的中间位置会被 0.3s Timer / didEndDragging 回写覆盖锚点。
// 通过 pushSnapshotForTesting（DEBUG 钩子）驱动两阶段快照，绕开 PhotoKit 依赖。

import XCTest
import Photos
import UIKit
@testable import PhotoDesk
import PhotoDeskCore

/// 锚点窗口测试仓库：数组即「creationDate 降序的完整结果」（与 PHFetchResult 切片语义一致）
private final class FakeAnchorRepository: AssetRepositoryProtocol {
    let items: [PhotoItem]

    init(_ items: [PhotoItem]) { self.items = items }

    func prepare(scope: PhotoScope) async -> Int { items.count }

    func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int { items.count }

    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] {
        guard offset < items.count, limit > 0 else { return [] }
        let upper = min(offset + limit, items.count)
        return Array(items[offset..<upper])
    }

    func globalIndex(of assetID: String, scope: PhotoScope) async -> Int? {
        items.firstIndex(where: { $0.id == assetID })
    }

    func count(scope: PhotoScope) async -> Int { items.count }

    func fetch(ids: [String]) async -> [PhotoItem] { [] }

    var latestResult: PHFetchResult<PHAsset>? { nil }
    func latestResult(for scope: PhotoScope) -> PHFetchResult<PHAsset>? { nil }
    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope) {}

    func map(_ asset: PHAsset) -> PhotoItem { Self.placeholder }

    static let placeholder = PhotoItem(id: "placeholder",
                                       mediaType: .image,
                                       mediaSubtypes: [],
                                       creationDate: nil,
                                       modificationDate: nil,
                                       pixelWidth: 1, pixelHeight: 1, duration: 0,
                                       isFavorite: false, isHidden: false,
                                       location: nil, burstIdentifier: nil,
                                       isCloudOnly: false)
}

@MainActor
final class LibraryPositionRestoreTests: XCTestCase {
    private var settings: SettingsStore!
    private var writer: MockPhotoWriter!
    private var session: ReviewSessionController!
    private var persistence: PersistenceController!
    private var testDefaults: UserDefaults!
    private var testSuiteName: String = ""
    private var snapshots: [LibrarySnapshot] = []
    /// 布局门禁要求集合视图在真实窗口内——窗口由测试类持有（局部变量会被释放）
    private var hostWindow: UIWindow?

    override func setUp() async throws {
        // 测试隔离：清筛选持久化（同 LibraryViewModelTests 的 CI 实测根因规避）
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("library.filter.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        settings = SettingsStore()
        writer = MockPhotoWriter()
        persistence = PersistenceController(inMemory: true)
        testSuiteName = "M12RestoreTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        snapshots = []
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("M12Restore-\(UUID().uuidString)", isDirectory: true)
        session = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                          writer: writer, trashBin: nil, settings: settings)
    }

    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("library.filter.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if !testSuiteName.isEmpty {
            UserDefaults().removePersistentDomain(forName: testSuiteName)
        }
        hostWindow = nil
    }

    // MARK: - 夹具

    private func makeItem(_ index: Int, idPrefix: String = "id") -> PhotoItem {
        PhotoItem(id: "\(idPrefix)-\(index)",
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: Date(timeIntervalSince1970: 1_700_000_000 - TimeInterval(index * 86_400)),
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: false, isHidden: false,
                  location: nil, burstIdentifier: nil,
                  isCloudOnly: false)
    }

    private func makeViewModel(repository: AssetRepositoryProtocol,
                               store: LibraryPositionStore) -> LibraryViewModel {
        let vm = LibraryViewModel(service: PhotoLibraryService(initialAccess: .authorized),
                                  repository: repository,
                                  pipeline: FakeAnchorPipeline(),
                                  writer: writer,
                                  trashBin: TrashBin(persistence: persistence, settings: settings),
                                  undoCenter: UndoCenter(writer: writer,
                                                         trashBin: nil,
                                                         persistence: persistence),
                                  settings: settings,
                                  reviewSession: session,
                                  positionStore: store)
        vm.attachSnapshotHandler { [weak self] snapshot in
            self?.snapshots.append(snapshot)
        }
        return vm
    }

    private func makeViewController(viewModel: LibraryViewModel,
                                    store: LibraryPositionStore) -> LibraryViewController {
        let controller = LibraryViewController(viewModel: viewModel,
                                               pipeline: FakeAnchorPipeline(),
                                               settings: settings,
                                               positionStore: store)
        // M12：快照应用带布局门禁（集合视图须完成初次布局）——VC 视图挂真实 UIWindow
        //（单测宿主内 UIWindow 布局链可用，ViewerCellGeometryTests 同款）
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(controller.view)
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        hostWindow = window   // 强持有（验证轮 18 实测：局部 window 释放后布局门禁永久挂起）
        return controller
    }

    private func waitUntil(timeout: TimeInterval = 5,
                           _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func section(_ id: String, title: String, count: Int) -> MonthSection {
        MonthSection(id: id, title: title, count: count)
    }

    // MARK: - R03：锚点窗口首屏

    /// 深月份锚点必须落在首批窗口内（以锚点为中心前后各半批）——旧版固定「最新 500」→ 两阶段跳转
    func testAnchorWindowFirstBatchCentersAnchor() async {
        let items = (0..<2_000).map { makeItem($0) }
        let store = LibraryPositionStore(defaults: testDefaults)
        let viewModel = makeViewModel(repository: FakeAnchorRepository(items), store: store)
        let queryKey = viewModel.query.key
        store.save(LibraryPosition(assetID: "id-1200",
                                   sectionID: "2024-05",
                                   itemIndexInSection: 0,
                                   offsetRatio: 0,
                                   savedAt: Date()),
                   queryKey: queryKey)

        await viewModel.start()

        XCTAssertEqual(viewModel.viewState, .ready)
        XCTAssertEqual(viewModel.allItems.count, 500, "首批仍遵守每批 ≤ 500")
        XCTAssertTrue(viewModel.allItems.contains(where: { $0.id == "id-1200" }),
                      "R03：锚点必须落在首批窗口内（旧版只推最新 500 → 恢复挂 pending → 可见跳转）")
        XCTAssertEqual(viewModel.allItems.first?.id, "id-950",
                       "窗口应以锚点为中心：start = max(0, 1200 - 250)")
    }

    /// 锚点已删除（globalIndex nil）→ 回退「最新 500」，不崩溃
    func testDeletedAnchorFallsBackToLatestBatch() async {
        let items = (0..<800).map { makeItem($0) }
        let store = LibraryPositionStore(defaults: testDefaults)
        let viewModel = makeViewModel(repository: FakeAnchorRepository(items), store: store)
        let queryKey = viewModel.query.key
        store.save(LibraryPosition(assetID: "deleted-asset",
                                   sectionID: "2024-05",
                                   itemIndexInSection: 0,
                                   offsetRatio: 0,
                                   savedAt: Date()),
                   queryKey: queryKey)

        await viewModel.start()

        XCTAssertEqual(viewModel.allItems.count, 500)
        XCTAssertEqual(viewModel.allItems.first?.id, "id-0", "无锚点 → 最新 500")
        await viewModel.ensureIndexComplete()
        XCTAssertEqual(viewModel.allItems.count, 800, "后台补齐不受锚点影响")
    }

    // MARK: - R03：恢复期间零回写 + 遮罩

    /// 两阶段恢复：中间快照期间的 savePositionNow 绝不能覆盖锚点；定位完成才解除
    func testRestoreDoesNotOverwriteAnchorWithIntermediatePosition() async {
        let store = LibraryPositionStore(defaults: testDefaults)
        let viewModel = makeViewModel(repository: FakeAnchorRepository([]), store: store)
        let queryKey = viewModel.query.key
        store.save(LibraryPosition(assetID: "a-target",
                                   sectionID: "2026-11",
                                   itemIndexInSection: 5,
                                   offsetRatio: 0,
                                   contentHeight: 2_000,
                                   viewportHeight: 844,
                                   savedAt: Date()),
                   queryKey: queryKey)
        let controller = makeViewController(viewModel: viewModel, store: store)
        controller.loadViewIfNeeded()

        // 阶段 1：快照不含锚点 + 索引未完成（旧版此时挂 pending 且回写不受限）
        let stage1Items = (0..<20).map { makeItem($0, idPrefix: "b") }
        viewModel.pushSnapshotForTesting(sections: [section("2026-11", title: "2026年11月", count: 20)],
                                         itemsBySection: [stage1Items],
                                         queryKey: queryKey,
                                         indexComplete: false)
        let maskShown = await waitUntil { controller.test_restoreMask.alpha > 0 }
        XCTAssertTrue(maskShown, "R03：恢复期间必须显示遮罩（用户不可见中间位置）")

        // 模拟恢复期间的回写触发点（0.3s Timer / didEndDragging 都汇聚到 savePositionNow）
        controller.savePositionNow(reason: "intermediate")
        XCTAssertEqual(store.load(queryKey: queryKey)?.assetID, "a-target",
                       "R03：恢复期间的中间位置绝不能覆盖锚点（旧版会写 b-0）")

        // 阶段 2：快照含锚点 + 索引完成 → 立即定位、解除遮罩
        var stage2Items = (0..<20).map { makeItem($0, idPrefix: "b") }
        stage2Items[5] = makeItem(0, idPrefix: "x").withID("a-target")
        viewModel.pushSnapshotForTesting(sections: [section("2026-11", title: "2026年11月", count: 20)],
                                         itemsBySection: [stage2Items],
                                         queryKey: queryKey,
                                         indexComplete: true)
        let restored = await waitUntil { viewModel.debugRestoreNote.contains("by=asset") }
        XCTAssertTrue(restored, "锚点可见后必须立即按 assetID 定位：\(viewModel.debugRestoreNote)")
        let maskHidden = await waitUntil { controller.test_restoreMask.alpha == 0 }
        XCTAssertTrue(maskHidden, "定位完成后遮罩必须移除")
        XCTAssertEqual(store.load(queryKey: queryKey)?.assetID, "a-target",
                       "恢复后锚点不被覆盖")
    }

    /// 锚点 asset 已删除但 sectionID 可用 → 回退 sectionID + itemIndexInSection（不弹横幅/动画）
    func testDeletedAnchorFallsBackToNearestSection() async {
        let store = LibraryPositionStore(defaults: testDefaults)
        let viewModel = makeViewModel(repository: FakeAnchorRepository([]), store: store)
        let queryKey = viewModel.query.key
        store.save(LibraryPosition(assetID: "missing-asset",
                                   sectionID: "2024-05",
                                   itemIndexInSection: 3,
                                   offsetRatio: 0.5,
                                   savedAt: Date()),
                   queryKey: queryKey)
        let controller = makeViewController(viewModel: viewModel, store: store)
        controller.loadViewIfNeeded()

        let items = (0..<60).map { makeItem($0, idPrefix: "m") }
        viewModel.pushSnapshotForTesting(sections: [section("2024-05", title: "2024年5月", count: 60)],
                                         itemsBySection: [items],
                                         queryKey: queryKey,
                                         indexComplete: true)

        let restored = await waitUntil { viewModel.debugRestoreNote.contains("by=section") }
        XCTAssertTrue(restored,
                      "锚点缺失时应回退 sectionID + itemIndexInSection：\(viewModel.debugRestoreNote)")
        let maskHidden = await waitUntil { controller.test_restoreMask.alpha == 0 }
        XCTAssertTrue(maskHidden)
    }

    /// 各 scope 的位置键彼此独立（回归守卫：切类不清空别类位置）
    func testPerScopePositionKeysAreIndependent() {
        let keyAll = LibraryQuery.stableKey(scope: .all, filter: .default, sortAscending: false)
        let keyFav = LibraryQuery.stableKey(scope: .favorites, filter: .default, sortAscending: false)
        XCTAssertNotEqual(keyAll, keyFav, "scope 不同 → 查询键必须不同")
        let store = LibraryPositionStore(defaults: testDefaults)
        store.save(LibraryPosition(assetID: "pos-all",
                                   sectionID: "s",
                                   itemIndexInSection: 0,
                                   offsetRatio: 0,
                                   savedAt: Date()),
                   queryKey: keyAll)
        store.save(LibraryPosition(assetID: "pos-fav",
                                   sectionID: "s",
                                   itemIndexInSection: 0,
                                   offsetRatio: 0,
                                   savedAt: Date()),
                   queryKey: keyFav)
        XCTAssertEqual(store.load(queryKey: keyAll)?.assetID, "pos-all")
        XCTAssertEqual(store.load(queryKey: keyFav)?.assetID, "pos-fav")
    }
    // MARK: - M13 P2：v3 视觉锚点与精确恢复

    func testSaveUsesVisualAnchorNotFirstVisibleCell() {
        let store = LibraryPositionStore(defaults: testDefaults)
        let viewModel = makeViewModel(repository: FakeAnchorRepository([]), store: store)
        let controller = makeViewController(viewModel: viewModel, store: store)
        controller.loadViewIfNeeded()
        let items = (0..<40).map { makeItem($0, idPrefix: "m13") }
        viewModel.pushSnapshotForTesting(sections: [section("2024-05", title: "2024年5月", count: items.count)],
                                         itemsBySection: [items],
                                         queryKey: viewModel.query.key,
                                         indexComplete: true)
        controller.test_collectionView.contentOffset = CGPoint(x: 0, y: 240)
        controller.test_collectionView.layoutIfNeeded()
        controller.savePositionNow(reason: "v3-unit")
        let restored = store.load(queryKey: viewModel.query.key)
        XCTAssertNotNil(restored)
        XCTAssertFalse(restored?.anchorAssetID.isEmpty ?? true, "v3 必须写视觉锚点 assetID")
        XCTAssertNotEqual(restored?.anchorAssetID, items.first?.id,
                          "视口下移后锚点不应再是 sorted().first 的首 cell")
        XCTAssertNotEqual(restored?.anchorVisualY, 0)
    }

    func testRestoreUsesPixelOffsetNotCentered() {
        let (strategy, offsetY) = PositionAnchorPolicy.resolve(
            anchor: PositionAnchorV3(anchorAssetID: "a", anchorVisualY: 32,
                                     anchorContentOffsetY: 1200, assetID: "a", sectionID: "s",
                                     itemIndexInSection: 0, offsetRatio: 0.5, savedAt: Date(), schemaVersion: 3),
            assetCellMinY: 1232, sectionCellMinY: nil,
            contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0)
        XCTAssertEqual(strategy, .asset)
        XCTAssertEqual(offsetY, 1200, "targetOffsetY = newMinY - anchorVisualY，禁止居中")
    }

    func testNoWritebackDuringRestoreInFlight() {
        XCTAssertFalse(PositionAnchorPolicy.allowsWriteback(isRestoreInFlight: true))
        XCTAssertTrue(PositionAnchorPolicy.allowsWriteback(isRestoreInFlight: false))
    }

    func testHostReuseAcrossViewStateDoesNotResetOffset() {
        let first = AppContainer.shared.libraryHostController
        let second = AppContainer.shared.libraryHostController
        XCTAssertTrue(first === second, "host 必须跨 viewState 复用同一 UINavigationController")
        let offset = CGPoint(x: 0, y: 321)
        (first.viewControllers.first as? LibraryViewController)?.test_collectionView.setContentOffset(offset, animated: false)
        XCTAssertEqual((second.viewControllers.first as? LibraryViewController)?.test_collectionView.contentOffset.y,
                       offset.y)
    }

    func testV3DecodeV2Fallback() throws {
        let json = """
        {"assetID":"legacy","sectionID":"2024-05","itemIndexInSection":2,"offsetRatio":0.25,"savedAt":700000000,"schemaVersion":2}
        """
        let decoded = try JSONDecoder().decode(LibraryPosition.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.anchorAssetID, "legacy")
        XCTAssertEqual(decoded.anchorVisualY, 0)
        XCTAssertEqual(decoded.itemIndexInSection, 2)
    }

    func testRotationKeepsSameVisualAnchor() {
        let visualY = PositionAnchorPolicy.visualY(cellMinY: 1500, contentOffsetY: 1380)
        let newMinY = 1250.0
        XCTAssertEqual(PositionAnchorPolicy.targetOffsetY(cellMinY: newMinY, anchorVisualY: visualY),
                       1130, "旋转后用相同锚点视觉 y 重算像素 offset")
    }
}

private extension PhotoItem {
    func withID(_ newID: String) -> PhotoItem {
        PhotoItem(id: newID,
                  mediaType: mediaType,
                  mediaSubtypes: mediaSubtypes,
                  creationDate: creationDate,
                  modificationDate: modificationDate,
                  pixelWidth: pixelWidth,
                  pixelHeight: pixelHeight,
                  duration: duration,
                  isFavorite: isFavorite,
                  isHidden: isHidden,
                  location: location,
                  burstIdentifier: burstIdentifier,
                  isCloudOnly: isCloudOnly)
    }
}

/// 极简管道 fake（R03 测试不取图）
@MainActor
private final class FakeAnchorPipeline: ImagePipelineProtocol {
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
