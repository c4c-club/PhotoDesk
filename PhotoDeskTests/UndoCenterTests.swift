// MARK: - 职责说明：UndoCenter 单元测试（docs/05 M3 验收）——
// 反向写语义（Mock PhotoWriter 记录调用）、Clock 注入的窗口过期、ActionLog 持久化与重启恢复、
// 加相簿撤销（移出引用）。PhotoKit 全流程由真机/P-3 验证。

import XCTest
@testable import PhotoDesk

/// 记录型 Mock（AGENTS.md §3.2 protocol 化；协议为 @MainActor，Mock 必须同隔离）
@MainActor
private final class MockPhotoWriter: PhotoWriterProtocol {
    private(set) var favoriteCalls: [(ids: [String], value: Bool)] = []
    private(set) var hiddenCalls: [(ids: [String], value: Bool)] = []
    private(set) var removedFromAlbums: [(ids: [String], albumID: String)] = []

    func setFavorite(ids: [String], isFavorite: Bool) async throws {
        favoriteCalls.append((ids, isFavorite))
    }

    func setHidden(ids: [String], isHidden: Bool) async throws {
        hiddenCalls.append((ids, isHidden))
    }

    func moveToRecentlyDeleted(ids: [String]) async throws {}

    func createAlbum(title: String) async throws -> String { UUID().uuidString }

    func renameAlbum(localID: String, to title: String) async throws {}

    func deleteAlbum(localID: String) async throws {}

    func add(ids: [String], toAlbum albumID: String) async throws {}

    func remove(ids: [String], fromAlbum albumID: String) async throws {
        removedFromAlbums.append((ids, albumID))
    }
}

/// 可拨动的假时钟（docs/03 §8）
private final class FakeClock: Clock {
    var now: Date
    init(now: Date = Date()) { self.now = now }
}

@MainActor
final class UndoCenterTests: XCTestCase {
    private func makeCenter(writer: MockPhotoWriter,
                            clock: FakeClock,
                            persistence: PersistenceController? = nil) -> UndoCenter {
        UndoCenter(writer: writer,
                   trashBin: nil,
                   persistence: persistence ?? PersistenceController(inMemory: true),
                   clock: clock)
    }

    func testUndoFavoriteReversesWriterCall() async {
        let writer = MockPhotoWriter()
        let center = makeCenter(writer: writer, clock: FakeClock())
        center.push(kind: .favorite, assetIDs: ["a"], toastText: "已收藏", window: 5)

        let entry = await center.undo()

        XCTAssertEqual(entry?.kind, .favorite)
        XCTAssertEqual(writer.favoriteCalls.last?.ids, ["a"])
        XCTAssertEqual(writer.favoriteCalls.last?.value, false)   // 反向：取消收藏
        XCTAssertFalse(center.hasActiveEntry)
    }

    func testUndoHideReversesWriterCall() async {
        let writer = MockPhotoWriter()
        let center = makeCenter(writer: writer, clock: FakeClock())
        center.push(kind: .hide, assetIDs: ["b"], toastText: "已隐藏", window: 5)

        _ = await center.undo()

        XCTAssertEqual(writer.hiddenCalls.last?.ids, ["b"])
        XCTAssertEqual(writer.hiddenCalls.last?.value, false)     // 反向：取消隐藏
    }

    func testUndoAddToAlbumRemovesReference() async {
        let writer = MockPhotoWriter()
        let center = makeCenter(writer: writer, clock: FakeClock())
        center.push(kind: .addToAlbum, assetIDs: ["c"], albumID: "album-1",
                    toastText: "已加入相簿", window: 5)

        _ = await center.undo()

        XCTAssertEqual(writer.removedFromAlbums.last?.ids, ["c"])
        XCTAssertEqual(writer.removedFromAlbums.last?.albumID, "album-1")
    }

    func testExpiryViaInjectedClock() {
        let clock = FakeClock(now: Date())
        let writer = MockPhotoWriter()
        let persistence = PersistenceController(inMemory: true)
        let center = makeCenter(writer: writer, clock: clock, persistence: persistence)
        center.push(kind: .hide, assetIDs: ["x"], toastText: "已隐藏", window: 5)
        XCTAssertEqual(center.recoverableCount(), 1)

        clock.now = clock.now.addingTimeInterval(6)   // 拨过窗口
        XCTAssertEqual(center.recoverableCount(), 0)
        XCTAssertNil(center.restoreLatestIfNeeded())
    }

    func testRestartRecoveryFromActionLog() async {
        let writer = MockPhotoWriter()
        let persistence = PersistenceController(inMemory: true)
        let clock = FakeClock(now: Date())
        let first = makeCenter(writer: writer, clock: clock, persistence: persistence)
        first.push(kind: .favorite, assetIDs: ["r1"], toastText: "已收藏", window: 300)

        // 模拟重启：新 UndoCenter 挂同一存储
        let second = makeCenter(writer: writer, clock: clock, persistence: persistence)
        XCTAssertEqual(second.recoverableCount(), 1)

        let restored = second.restoreLatestIfNeeded()
        XCTAssertEqual(restored?.kind, .favorite)
        XCTAssertEqual(restored?.assetIDs, ["r1"])
        XCTAssertTrue(second.hasActiveEntry)

        // 撤销后不再可恢复
        _ = await second.undo()
        XCTAssertEqual(second.recoverableCount(), 0)
    }

    func testNewPushReplacesActiveEntry() {
        let writer = MockPhotoWriter()
        let center = makeCenter(writer: writer, clock: FakeClock())
        center.push(kind: .hide, assetIDs: ["a"], toastText: "已隐藏", window: 5)
        center.push(kind: .favorite, assetIDs: ["b"], toastText: "已收藏", window: 5)

        XCTAssertEqual(center.activeEntry?.kind, .favorite)   // 最新动作顶掉旧条目
    }
}
