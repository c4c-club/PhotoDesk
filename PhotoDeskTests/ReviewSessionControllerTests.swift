// MARK: - 职责说明：ReviewSessionController 单元测试（docs/09 D16 §8）——
// 20 次滑动 0 次 writer / 提交 1 次 / 取消保留 / 重启恢复（杀 App 队列还原）/ 隐藏批量提交。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
final class ReviewSessionControllerTests: XCTestCase {
    private var settings: SettingsStore!
    private var writer: MockPhotoWriter!
    private var storeDir: URL!

    override func setUp() async throws {
        settings = SettingsStore()
        writer = MockPhotoWriter()
        storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionCtrlTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeController() -> ReviewSessionController {
        ReviewSessionController(store: PendingActionStore(directoryOverride: storeDir),
                                writer: writer, trashBin: nil, settings: settings)
    }

    // MARK: - 滑动路径

    func testTwentySwipesZeroWriterCalls() {
        let session = makeController()
        for i in 0..<20 {
            XCTAssertTrue(session.enqueueDelete(id: "id-\(i)", originIndex: i))
        }
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0, "滑动全程 0 次 PhotoKit 写")
        XCTAssertEqual(session.pendingDeleteCount, 20)
        XCTAssertFalse(session.isCommitting)
    }

    func testCommitOnceForTwenty() async {
        let session = makeController()
        for i in 0..<20 { session.enqueueDelete(id: "id-\(i)", originIndex: i) }
        let result = await session.commitDeletes()
        XCTAssertEqual(result.committed, 20)
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 1, "恰好 1 次 performChanges（1 次系统确认）")
        XCTAssertTrue(session.isEmpty, "提交成功清空队列")
    }

    func testCancelKeepsQueue() async {
        let session = makeController()
        for i in 0..<5 { session.enqueueDelete(id: "id-\(i)", originIndex: i) }
        writer.shouldFailMoveToRecentlyDeleted = true
        let result = await session.commitDeletes()
        XCTAssertEqual(result.committed, 0)
        XCTAssertEqual(result.failed, true)
        XCTAssertEqual(session.pendingDeleteCount, 5, "系统确认取消：队列保留不丢数据")
    }

    // MARK: - 重启恢复（杀 App）

    func testRestartRestoresQueueWithoutAutoCommit() async throws {
        let session = makeController()
        for i in 0..<7 { session.enqueueDelete(id: "d-\(i)", originIndex: i) }
        for i in 0..<3 { session.enqueueHide(id: "h-\(i)", originIndex: i) }
        // 等 debounce 落盘
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0)

        // 「杀 App 重启」：新 controller + 同一 store 目录
        let revived = makeController()
        XCTAssertEqual(revived.pendingDeleteCount, 7, "重启恢复待删除队列")
        XCTAssertEqual(revived.pendingHideCount, 3, "重启恢复待隐藏队列")
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0, "恢复不自动提交、不自动弹系统框")
    }

    func testCorruptStoreStartsEmptyNotCrash() throws {
        // 先写一个合法文件再破坏它
        let session = makeController()
        session.enqueueDelete(id: "x", originIndex: 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        let fileURL = storeDir.appendingPathComponent("session-v1.json")
        try Data("not-json".utf8).write(to: fileURL)

        let revived = makeController()
        XCTAssertTrue(revived.isEmpty, "损坏文件 → 备份改名后从空队列开始，不 crash")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: storeDir.path)
        XCTAssertTrue(leftovers.contains { $0.contains("corrupt") }, "损坏文件已备份")
    }

    // MARK: - 隐藏批量

    func testHideCommitSingleBatch() async {
        let session = makeController()
        for i in 0..<20 { session.enqueueHide(id: "h-\(i)", originIndex: i) }
        let result = await session.commitHides()
        XCTAssertEqual(result.committed, 20)
        XCTAssertEqual(writer.setHiddenCallCount, 1, "一次批量 setHidden（通常无系统确认）")
        XCTAssertEqual(writer.setHiddenCalls.first?.isHidden, true)
        XCTAssertTrue(session.isEmpty)
    }

    func testFlushHidesOnEnterVault() async {
        let session = makeController()
        for i in 0..<4 { session.enqueueHide(id: "h-\(i)", originIndex: i) }
        await session.flushHidesIfNeeded(reason: "enterVault")
        XCTAssertEqual(writer.setHiddenCallCount, 1, "进入 Vault 前批量提交待隐藏")
        XCTAssertTrue(session.isEmpty)
    }

    // MARK: - 撤销 / 恢复

    func testUndoPendingAndRestore() {
        let session = makeController()
        session.enqueueDelete(id: "a", originIndex: 0)
        session.undoPending(id: "a", kind: .delete)
        XCTAssertTrue(session.isEmpty)
    }

    func testRestoreRemovesBothKinds() {
        let session = makeController()
        session.enqueueHide(id: "a", originIndex: 0)
        session.restore(id: "a")
        XCTAssertTrue(session.isEmpty, "review 页恢复：任意 kind 均移除")
    }

    func testDuplicateEnqueueIsIdempotent() {
        let session = makeController()
        session.enqueueDelete(id: "a", originIndex: 0)
        session.enqueueDelete(id: "a", originIndex: 1)
        XCTAssertEqual(session.pendingDeleteCount, 1, "重复入队去重")
        session.enqueueHide(id: "a", originIndex: 2)
        XCTAssertEqual(session.pendingHideCount, 1, "改标自动替换 kind")
        XCTAssertEqual(session.pendingDeleteCount, 0)
    }

    // MARK: - 幂等对账（崩溃于 performChanges 成功后、清空队列前）

    func testReconcileAfterCrash() async {
        let session = makeController()
        for id in ["a", "b", "c"] { session.enqueueDelete(id: id, originIndex: 0) }
        // 模拟：a 已删成功但队列未清（a 不在「仍在库中」集合里）
        let stillInLibrary: Set<String> = ["b", "c"]
        let remaining = BatchCommitPlanner.reconcileAfterInterruption(
            pending: session.session.pendingDeleteIDs,
            stillInLibrary: stillInLibrary)
        XCTAssertEqual(remaining, ["b", "c"], "已不在库中的 a 视为提交成功，b/c 保留")
    }
}
