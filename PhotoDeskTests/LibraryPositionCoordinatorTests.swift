// MARK: - 职责说明：位置记忆 v5 协调器单测（docs/25 §5.4–5.5 / M15 P0-2，≥12 条）——
// 门禁：恢复前 save 全被拒、settled 后立即生效、saveNow 同步 flush；恢复算法：
// 无锚点 settled、bounds=0 保持 restoring、asset 精确像素落地、verify 失败只调 offset 重试一次、
// 两次失败 settled（verify-failed）、fallback section/ratio、cancelRestore、queryKey 一次性。

import XCTest
import UIKit
@testable import PhotoDesk
import PhotoDeskCore

@MainActor
final class LibraryPositionCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var fileDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "PositionCoordinator-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fileDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pos-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if !suiteName.isEmpty {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try? FileManager.default.removeItem(at: fileDir)
        super.tearDown()
    }

    private func makeStore() -> LibraryPositionStore {
        LibraryPositionStore(fileStore: PositionFileStore(directory: fileDir), defaults: defaults)
    }

    private func snapshot(_ anchor: String,
                          visualY: Double = 40,
                          queryKey: String = "scope.all") -> LibraryPositionSnapshot {
        LibraryPositionSnapshot(queryKey: queryKey,
                                anchorAssetID: anchor,
                                anchorVisualY: visualY,
                                anchorSectionID: "2026-11",
                                anchorItemIndex: 3,
                                contentOffsetY: 900,
                                contentHeight: 5_000,
                                viewportHeight: 844)
    }

    private func saveAnchor(_ store: LibraryPositionStore,
                            anchor: String = "target",
                            visualY: Double = 40,
                            queryKey: String = "scope.all") {
        store.save(LibraryPositionV6(queryKey: "",
                                     anchorAssetID: anchor,
                                     anchorGlobalIndex: nil,
                                     anchorSectionID: "2026-11",
                                     anchorSectionItemIndex: 3,
                                     anchorVisualY: visualY,
                                     anchorContentOffsetY: 831.2,
                                     gridColumns: 3,
                                     contentInsetTop: 0,
                                     contentHeight: 5_000,
                                     viewportHeight: 844,
                                     savedAt: Date()),
                   queryKey: queryKey)
    }

    /// 可控 context：记录 scrollTo / applyOffset 调用；actual 可编程（首次偏 10pt 后收敛）。
    private final class ContextRecorder {
        var scrollCalls: [String] = []
        var appliedOffsets: [Double] = []
        var failFirstVerify = false
        var anchorMinYValue: Double? = 1_000
        var sectionMinYValue: Double? = 2_400

        func context(bounds: CGSize = CGSize(width: 390, height: 844),
                     isIndexComplete: Bool = true,
                     anchorInData: Bool = true) -> LibraryPositionRestoreContext {
            LibraryPositionRestoreContext(
                bounds: bounds,
                isIndexComplete: isIndexComplete,
                contentHeight: 5_000,
                viewportHeight: 844,
                adjustedTop: 0,
                bottomInset: 0,
                anchorInData: { _ in anchorInData },
                anchorMinY: { [unowned self] _ in anchorInData ? anchorMinYValue : nil },
                // section 头 minY 与锚点是否在数据无关：索引完成即可用（section fallback 路径依赖）
                sectionMinY: { [unowned self] _, _ in sectionMinYValue },
                scrollToAnchorTop: { [unowned self] id in
                    scrollCalls.append(id)
                    return true
                },
                applyOffset: { [unowned self] y in
                    appliedOffsets.append(y)
                },
                actualOffsetY: { [unowned self] in
                    // 首次校验故意偏 10pt（模拟 UIKit 拒绝），之后返回最后写入值
                    if failFirstVerify {
                        failFirstVerify = false
                        return (appliedOffsets.last ?? 0) + 10
                    }
                    return appliedOffsets.last ?? 0
                },
                layoutNow: { }
            )
        }
    }

    /// 异步恢复链（applyOffset → async verify）在测试 runloop 里收敛。
    private func runUntil(_ coordinator: LibraryPositionCoordinator,
                          phase: PositionRestorePhaseV6,
                          timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, coordinator.phase != phase {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - 保存门禁

    func testStaleSaveTimerDoesNotOverwriteNewAnchor() {
        let store = makeStore()
        let coordinator = LibraryPositionCoordinator(store: store)
        // 无锚点启动 → settled（可保存门禁 I1）
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.scheduleSave(reason: "old", snapshot: snapshot("old-anchor"), debounce: 0.2)
        coordinator.saveNow(reason: "new", snapshot: snapshot("new-anchor"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "new-anchor")

        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "new-anchor",
                       "旧 revision 的防抖保存必须被丢弃，不得覆盖新锚点")
    }

    func testRestoreInFlightBlocksAllWrites() {
        let store = makeStore()
        saveAnchor(store, anchor: "saved-anchor")
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        XCTAssertTrue(coordinator.isRestoreInFlight, "begin 后必须处于恢复中")

        coordinator.saveNow(reason: "intermediate", snapshot: snapshot("new-position"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "saved-anchor",
                       "I1：恢复完成前任何保存都必须被拒绝")
    }

    func testSaveAllowedAfterSettle() {
        let store = makeStore()
        saveAnchor(store)
        let recorder = ContextRecorder()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context())
        runUntil(coordinator, phase: .settled)
        XCTAssertEqual(coordinator.phase, .settled)

        coordinator.saveNow(reason: "after-restore", snapshot: snapshot("post-restore"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "post-restore",
                       "I2：settled 后保存必须立即生效")
    }

    func testSaveNowFlushesSynchronously() {
        let store = makeStore()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")   // 无锚点 → settled（I1 门禁）
        coordinator.saveNow(reason: "flush", snapshot: snapshot("flush-anchor"))
        // saveNow 内部 flush：无需 runloop 即可读到
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "flush-anchor",
                       "I3：saveNow 必须等落盘完成再返回")
    }

    // MARK: - 恢复：无锚点 / 一次性 / queryKey

    func testNoAnchorSettlesImmediately() {
        let store = makeStore()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        XCTAssertEqual(coordinator.phase, .settled, "无锚点 → settled(top)，不遮罩")
        XCTAssertFalse(coordinator.isRestoreInFlight)
        coordinator.saveNow(reason: "no-anchor", snapshot: snapshot("first-scroll"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "first-scroll",
                       "无锚点 settled 后保存立即生效")
    }

    func testBeginOnlyOncePerQueryKey() {
        let store = makeStore()
        saveAnchor(store)
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.cancelRestore(reason: "test")
        XCTAssertEqual(coordinator.phase, .settled)
        // 同一 queryKey 二次 begin 必须是 no-op（I2：一次启动只恢复一次）
        coordinator.beginRestore(queryKey: "scope.all")
        XCTAssertEqual(coordinator.phase, .settled, "同 queryKey 二次 begin 不得重新进入恢复")
    }

    func testQueryKeySwitchStartsNewRestore() {
        let store = makeStore()
        saveAnchor(store, queryKey: "scope.all")
        saveAnchor(store, queryKey: "scope.favorites")
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.cancelRestore(reason: "test")
        coordinator.beginRestore(queryKey: "scope.favorites")
        XCTAssertEqual(coordinator.phase, .loading, "queryKey 变化 → 新一轮恢复（v6 先 loading 等窗口）")
    }

    // MARK: - 恢复：bounds / asset / verify

    func testZeroBoundsKeepsRestoring() {
        let store = makeStore()
        saveAnchor(store)
        let recorder = ContextRecorder()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context(bounds: .zero))
        XCTAssertEqual(coordinator.phase, .waitingForWindow, "bounds=0 必须保持等待，不得失败/回顶")
        XCTAssertTrue(recorder.appliedOffsets.isEmpty, "bounds=0 不得写 offset")
    }

    func testAssetRestoreAppliesPixelOffset() {
        let store = makeStore()
        saveAnchor(store)
        let recorder = ContextRecorder()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context())
        runUntil(coordinator, phase: .settled)
        XCTAssertEqual(coordinator.phase, .settled)
        XCTAssertEqual(coordinator.lastStrategy, .asset)
        XCTAssertEqual(recorder.appliedOffsets.last ?? -1, 960, accuracy: 0.5,
                       "target = minY 1000 - visualY 40")
        XCTAssertEqual(recorder.scrollCalls, ["target"],
                       "asset 路径恰好一次 scrollToItem(.top)")
    }

    func testVerifyFailureRetriesOffsetOnly() {
        let store = makeStore()
        saveAnchor(store)
        let recorder = ContextRecorder()
        recorder.failFirstVerify = true
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context())
        runUntil(coordinator, phase: .settled)
        XCTAssertEqual(coordinator.phase, .settled)
        XCTAssertEqual(coordinator.restoreAttempts, 1, "第一次 verify 失败 → 恰好一次重试")
        XCTAssertEqual(recorder.scrollCalls.count, 1,
                       "重试只调 offset，不得重新 scrollToItem")
        XCTAssertEqual(recorder.appliedOffsets.count, 2, "重试必须再写一次 offset")
        XCTAssertEqual(coordinator.lastStrategy, .asset)
    }

    func testSecondVerifyFailureSettlesWithoutBlocking() {
        let store = makeStore()
        saveAnchor(store)
        let recorder = ContextRecorder()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        // 每次校验都偏 10pt：第一次重试后第二次仍失败
        recorder.failFirstVerify = true
        // 让 failFirstVerify 重新置位：重试写 offset 后再次失败
        let originalApply = recorder.context()
        _ = originalApply
        // 简化：直接把 anchorMinY 设为随 offset 漂移的坏值，制造二次失败
        var verifyCount = 0
        let badContext = LibraryPositionRestoreContext(
            bounds: CGSize(width: 390, height: 844),
            isIndexComplete: true,
            contentHeight: 5_000,
            viewportHeight: 844,
            adjustedTop: 0,
            bottomInset: 0,
            anchorInData: { _ in true },
            anchorMinY: { _ in 1_000 },
            sectionMinY: { _, _ in nil },
            scrollToAnchorTop: { _ in true },
            applyOffset: { _ in },
            actualOffsetY: {
                verifyCount += 1
                return 5_000 + Double(verifyCount)   // 永远不等于 target
            },
            layoutNow: { }
        )
        coordinator.attemptRestore(context: badContext)
        runUntil(coordinator, phase: .settled)
        XCTAssertEqual(coordinator.phase, .settled, "两次 verify 失败 → settled（verify-failed），不阻塞 UI")
        XCTAssertEqual(coordinator.restoreAttempts, 2)
        coordinator.saveNow(reason: "after-fail", snapshot: snapshot("any"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "any",
                       "verify-failed settled 后允许保存")
    }

    // MARK: - fallback

    func testFallbackToSectionWhenAnchorMissingAndIndexComplete() {
        let store = makeStore()
        saveAnchor(store, anchor: "deleted-asset")
        let recorder = ContextRecorder()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context(anchorInData: false))
        runUntil(coordinator, phase: .settled)
        XCTAssertEqual(coordinator.phase, .settled)
        XCTAssertEqual(coordinator.lastStrategy, .section, "索引完成仍缺锚点 → section fallback")
        XCTAssertEqual(recorder.appliedOffsets.last ?? -1, 2_400, accuracy: 0.5,
                       "section fallback：直接落 section minY")
        XCTAssertTrue(recorder.scrollCalls.isEmpty, "fallback 不做 scrollToItem")
    }

    func testFallbackToRatioWhenSectionMissing() {
        let store = makeStore()
        saveAnchor(store, anchor: "deleted-asset")
        let recorder = ContextRecorder()
        recorder.sectionMinYValue = nil
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context(anchorInData: false))
        runUntil(coordinator, phase: .settled)
        XCTAssertEqual(coordinator.phase, .settled)
        XCTAssertEqual(coordinator.lastStrategy, .ratio)
        // ratio 0.2 × scrollable(5000-844=4156) = 831.2
        XCTAssertEqual(recorder.appliedOffsets.last ?? -1, 831.2, accuracy: 0.5)
    }

    func testAnchorMissingKeepsWaitingWhileIndexIncomplete() {
        let store = makeStore()
        saveAnchor(store, anchor: "not-yet-fetched")
        let recorder = ContextRecorder()
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        coordinator.attemptRestore(context: recorder.context(isIndexComplete: false, anchorInData: false))
        // v6：锚点缺失 + 索引未完成 → 停在 applying 门禁态（不写 offset、保存被拒），
        // 索引完成后 attemptRestore 再入即降级 fallback
        XCTAssertEqual(coordinator.phase, .applying, "I4：锚点未到 + 索引未完成 → 保持等待，不失败")
        XCTAssertTrue(recorder.appliedOffsets.isEmpty)
        coordinator.saveNow(reason: "waiting", snapshot: snapshot("should-be-rejected"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "not-yet-fetched",
                       "恢复等待期保存必须被拒（锚点保持 not-yet-fetched）")
    }

    // MARK: - cancel

    func testCancelRestoreAllowsSave() {
        let store = makeStore()
        saveAnchor(store)
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        XCTAssertTrue(coordinator.isRestoreInFlight)
        coordinator.cancelRestore(reason: "monthJump")
        XCTAssertEqual(coordinator.phase, .settled)
        coordinator.saveNow(reason: "monthJump", snapshot: snapshot("jump-anchor"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "jump-anchor",
                       "用户接管后保存必须生效")
    }
}

