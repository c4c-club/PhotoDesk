// MARK: - BatchCommitPlannerTests：5,000 分批 / 缺失 id / 幂等对账（docs/09 D16 §8）

import XCTest
@testable import PhotoDeskCore

final class BatchCommitPlannerTests: XCTestCase {
    func testBatchesUnderLimit() {
        let ids = (0..<4_999).map { "id-\($0)" }
        let batches = BatchCommitPlanner.batches(for: ids)
        XCTAssertEqual(batches.count, 1, "5,000 以内单批 = 1 次系统确认")
        XCTAssertEqual(batches[0].ids.count, 4_999)
        XCTAssertEqual(batches[0].index, 0)
        XCTAssertEqual(batches[0].totalBatches, 1)
    }

    func testBatchesSplitAtExactLimit() {
        let ids = (0..<5_000).map { "id-\($0)" }
        let batches = BatchCommitPlanner.batches(for: ids)
        XCTAssertEqual(batches.count, 1)
    }

    func testBatchesSplitAboveLimit() {
        let ids = (0..<11_000).map { "id-\($0)" }
        let batches = BatchCommitPlanner.batches(for: ids)
        XCTAssertEqual(batches.count, 3, "11,000 → 5000/5000/1000，共 3 次系统确认（不是 11,000 次）")
        XCTAssertEqual(batches.map { $0.ids.count }, [5_000, 5_000, 1_000])
        XCTAssertEqual(batches[0].totalBatches, 3)
        // 顺序保持
        XCTAssertEqual(batches[0].ids.first, "id-0")
        XCTAssertEqual(batches[2].ids.first, "id-10000")
    }

    func testCustomBatchSize() {
        let ids = ["a", "b", "c", "d", "e"]
        let batches = BatchCommitPlanner.batches(for: ids, batchSize: 2)
        XCTAssertEqual(batches.map { $0.ids }, [["a", "b"], ["c", "d"], ["e"]])
    }

    func testEmptyInput() {
        XCTAssertTrue(BatchCommitPlanner.batches(for: []).isEmpty)
    }

    func testPartitionSeparatesMissing() {
        let (committable, missing) = BatchCommitPlanner.partition(
            ids: ["a", "b", "c", "d"],
            available: ["a", "c", "d"])
        XCTAssertEqual(committable, ["a", "c", "d"], "可提交项保持顺序")
        XCTAssertEqual(missing, ["b"], "缺失 id = alreadyGone，跳过不删")
    }

    func testPartitionAllMissing() {
        let (committable, missing) = BatchCommitPlanner.partition(ids: ["x"], available: [])
        XCTAssertTrue(committable.isEmpty)
        XCTAssertEqual(missing, ["x"])
    }

    func testReconcileAfterInterruption() {
        // 崩溃在 performChanges 成功后、清空队列前：已不在库中的视为已提交
        let remaining = BatchCommitPlanner.reconcileAfterInterruption(
            pending: ["a", "b", "c"],
            stillInLibrary: ["b", "c", "d"])
        XCTAssertEqual(remaining, ["b", "c"], "a 已不在库中 → 清除；b/c 保留待提交")
    }

    func testReconcileKeepsAllWhenNothingCommitted() {
        let remaining = BatchCommitPlanner.reconcileAfterInterruption(
            pending: ["a", "b"],
            stillInLibrary: ["a", "b", "c"])
        XCTAssertEqual(remaining, ["a", "b"])
    }
}
