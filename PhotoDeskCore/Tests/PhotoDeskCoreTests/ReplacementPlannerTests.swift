// MARK: - ReplacementPlannerTests：补位方向/首尾/空列表/连续删除/无手势（docs/09 D16 §8）

import XCTest
@testable import PhotoDeskCore

final class ReplacementPlannerTests: XCTestCase {
    // MARK: - 正常前进（保持 index）

    func testSwipeUpEntryFromBottom() {
        // 上滑（飞出 .top）→ 下一张从底部补位
        let plan = ReplacementPlanner.plan(currentIndex: 3, countAfterRemoval: 10,
                                           exitEdge: .top, hasNext: true, hasPrevious: true)
        XCTAssertEqual(plan.nextIndex, 3, "原 i+1 顶到 i，不跳张")
        XCTAssertEqual(plan.entryEdge, .bottom)
        XCTAssertFalse(plan.shouldClose)
    }

    func testSwipeDownEntryFromTop() {
        // 下滑（飞出 .bottom）→ 下一张从顶部补位
        let plan = ReplacementPlanner.plan(currentIndex: 3, countAfterRemoval: 10,
                                           exitEdge: .bottom, hasNext: true, hasPrevious: true)
        XCTAssertEqual(plan.nextIndex, 3)
        XCTAssertEqual(plan.entryEdge, .top)
    }

    func testToolbarDeleteDefaultsToBottom() {
        // 工具栏/无手势 → 默认从底部前进
        let plan = ReplacementPlanner.plan(currentIndex: 3, countAfterRemoval: 10,
                                           exitEdge: nil, hasNext: true, hasPrevious: true)
        XCTAssertEqual(plan.nextIndex, 3)
        XCTAssertEqual(plan.entryEdge, .bottom)
    }

    // MARK: - 末尾回退（回卷，与飞出方向相同）

    func testSwipeUpAtEndRollsBackWithTopEntry() {
        // 已是最后一张，上滑 → 回退上一张，从顶部补位（与飞出边相同）
        let plan = ReplacementPlanner.plan(currentIndex: 9, countAfterRemoval: 9,
                                           exitEdge: .top, hasNext: false, hasPrevious: true)
        XCTAssertEqual(plan.nextIndex, 8)
        XCTAssertEqual(plan.entryEdge, .top)
    }

    func testSwipeDownAtEndRollsBackWithBottomEntry() {
        let plan = ReplacementPlanner.plan(currentIndex: 9, countAfterRemoval: 9,
                                           exitEdge: .bottom, hasNext: false, hasPrevious: true)
        XCTAssertEqual(plan.nextIndex, 8)
        XCTAssertEqual(plan.entryEdge, .bottom)
    }

    func testToolbarAtEndRollsBackWithDefaultBottom() {
        let plan = ReplacementPlanner.plan(currentIndex: 9, countAfterRemoval: 9,
                                           exitEdge: nil, hasNext: false, hasPrevious: true)
        XCTAssertEqual(plan.nextIndex, 8)
        XCTAssertEqual(plan.entryEdge, .bottom)
    }

    // MARK: - 空列表

    func testEmptyListClosesViewer() {
        let plan = ReplacementPlanner.plan(currentIndex: 0, countAfterRemoval: 0,
                                           exitEdge: .bottom, hasNext: false, hasPrevious: false)
        XCTAssertNil(plan.nextIndex)
        XCTAssertNil(plan.entryEdge)
        XCTAssertTrue(plan.shouldClose)
    }

    // MARK: - 边界与连续删除

    func testRemoveFirstItem() {
        // 删除第 0 张且后面还有 → 保持 index 0（下一张顶上来）
        let plan = ReplacementPlanner.plan(currentIndex: 0, countAfterRemoval: 5,
                                           exitEdge: .bottom, hasNext: true, hasPrevious: false)
        XCTAssertEqual(plan.nextIndex, 0)
        XCTAssertEqual(plan.entryEdge, .top)
    }

    func testConsecutiveRemovalPlanIsStateless() {
        // 连续删除：每次都以「当前 index + 删除后长度」独立计算（纯函数无状态）
        var index = 4
        for _ in 0..<3 {
            let plan = ReplacementPlanner.plan(currentIndex: index, countAfterRemoval: 10,
                                               exitEdge: .top, hasNext: true, hasPrevious: true)
            XCTAssertEqual(plan.nextIndex, index)
            guard let next = plan.nextIndex else { return XCTFail("nextIndex 不能为 nil") }
            index = next
        }
        XCTAssertEqual(index, 4, "保持 index 策略下连续删除不前进")
    }

    func testDefensiveClampWhenNoNeighbors() {
        // 防御：count > 0 但无后无前（调用方状态不一致）→ clamp 到合法 index，不崩溃
        let plan = ReplacementPlanner.plan(currentIndex: 5, countAfterRemoval: 2,
                                           exitEdge: .top, hasNext: false, hasPrevious: false)
        XCTAssertEqual(plan.nextIndex, 1)
        XCTAssertFalse(plan.shouldClose)
    }
}
