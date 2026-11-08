// MARK: - SelectionPolicyTests：进入/切换/全选/反选/取消/筛选收敛/移除（docs/09 D11/D12）

import XCTest
@testable import PhotoDeskCore

final class SelectionPolicyTests: XCTestCase {
    private let scope: Set<String> = ["a", "b", "c", "d"]

    func testBeginWithInitial() {
        var state = SelectionState()
        state.begin(scope: scope, initial: "b")
        XCTAssertEqual(state.selected, ["b"])
        XCTAssertTrue(state.scope == scope)
        XCTAssertFalse(state.allSelected)
    }

    func testBeginIgnoresInitialOutsideScope() {
        var state = SelectionState()
        state.begin(scope: scope, initial: "zzz")
        XCTAssertTrue(state.isEmpty)
    }

    func testToggle() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.toggle("a")
        XCTAssertEqual(state.selectedSet, ["a"])
        state.toggle("a")
        XCTAssertTrue(state.isEmpty)
    }

    func testToggleIgnoresOutsideScope() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.toggle("zzz")
        XCTAssertTrue(state.isEmpty)
    }

    func testSelectOnlyAdds() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.select("a")
        state.select("a")   // 重复加选无副作用（框选只加不取消）
        XCTAssertEqual(state.selected, ["a"])
    }

    func testSelectAllAndAllSelected() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.selectAll()
        XCTAssertTrue(state.allSelected)
        XCTAssertEqual(state.selectedSet, scope)
    }

    func testDeselectAll() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.selectAll()
        state.deselectAll()
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.allSelected)
    }

    func testInvert() {
        var state = SelectionState()
        state.begin(scope: scope, initial: "a")
        state.toggle("b")             // selected = {a, b}
        state.invert()
        XCTAssertEqual(state.selectedSet, ["c", "d"])
    }

    func testIntersectScopeOnFilterChange() {
        var state = SelectionState()
        state.begin(scope: scope, initial: "a")
        state.toggle("b")
        // 筛选变化：新 scope 只剩 b/c/d → a 被收敛掉，b 保留
        state.intersectScope(with: ["b", "c", "d"])
        XCTAssertEqual(state.selected, ["b"])
        XCTAssertEqual(state.scope, ["b", "c", "d"])
    }

    func testIntersectScopeEmptySelectionStays() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.intersectScope(with: [])
        XCTAssertTrue(state.isEmpty)
        XCTAssertTrue(state.scope.isEmpty)
    }

    func testRemoveAllAfterCommit() {
        var state = SelectionState()
        state.begin(scope: scope, initial: "a")
        state.toggle("d")
        state.removeAll(["a"])
        XCTAssertEqual(state.selected, ["d"])
        XCTAssertEqual(state.scope, ["b", "c", "d"])
    }

    // MARK: - docs/13 S07/S10 扩展：scopeID / 批量加选 / 范围替换 / 范围选择

    func testBeginStoresScopeID() {
        var state = SelectionState()
        state.begin(scope: scope, scopeID: "month:2024-05")
        XCTAssertEqual(state.scopeID, "month:2024-05")
        XCTAssertTrue(state.isMonthScope)
    }

    func testDefaultScopeIDIsNil() {
        var state = SelectionState()
        state.begin(scope: scope)
        XCTAssertNil(state.scopeID)
        XCTAssertFalse(state.isMonthScope)
    }

    func testRebeginResetsScopeID() {
        var state = SelectionState()
        state.begin(scope: scope, scopeID: "month:2024-05")
        state.begin(scope: scope)
        XCTAssertNil(state.scopeID)
    }

    func testBatchSelectPreservesOrderAndSkipsOutsideScope() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.select(["d", "zzz", "a", "a", "b"])
        XCTAssertEqual(state.selected, ["d", "a", "b"])
    }

    func testReplaceSelectionFiltersAndDedupes() {
        var state = SelectionState()
        state.begin(scope: scope)
        state.replaceSelection(["c", "zzz", "a", "c"])
        XCTAssertEqual(state.selected, ["c", "a"])
    }

    func testReplaceSelectionWithEmptyListClears() {
        var state = SelectionState()
        state.begin(scope: scope, initial: "a")
        state.replaceSelection([])
        XCTAssertTrue(state.isEmpty)
    }

    func testSelectRangeForward() {
        var state = SelectionState()
        let ordered = ["a", "b", "c", "d", "e"]
        state.begin(scope: Set(ordered))
        state.selectRange(in: ordered, from: "b", to: "d")
        XCTAssertEqual(state.selected, ["b", "c", "d"])
    }

    func testSelectRangeReverseKeepsListOrder() {
        var state = SelectionState()
        let ordered = ["a", "b", "c", "d", "e"]
        state.begin(scope: Set(ordered))
        state.selectRange(in: ordered, from: "d", to: "b")
        XCTAssertEqual(state.selected, ["b", "c", "d"])
    }

    func testSelectRangeIgnoresOutOfScopeIds() {
        var state = SelectionState()
        let ordered = ["a", "b", "c", "d", "e"]
        state.begin(scope: ["b", "c", "d"])   // scope 不含 a/e
        state.selectRange(in: ordered, from: "a", to: "e")
        XCTAssertEqual(state.selected, ["b", "c", "d"])
    }

    func testSelectRangeMissingAnchorIsNoOp() {
        var state = SelectionState()
        let ordered = ["a", "b", "c"]
        state.begin(scope: Set(ordered), initial: "a")
        state.selectRange(in: ordered, from: "zzz", to: "c")
        XCTAssertEqual(state.selected, ["a"])
    }

    func testSelectRangeMergesWithExistingSelection() {
        var state = SelectionState()
        let ordered = ["a", "b", "c", "d", "e"]
        state.begin(scope: Set(ordered), initial: "e")
        state.selectRange(in: ordered, from: "b", to: "d")
        XCTAssertEqual(state.selected, ["e", "b", "c", "d"])
    }

    func testRemoveOnlyOneID() {
        var state = SelectionState()
        state.begin(scope: Set(["a", "b", "c"]), initial: "a")
        state.select("b")
        state.select("c")
        XCTAssertEqual(state.selected, ["a", "b", "c"])
        state.remove(id: "b")
        XCTAssertEqual(state.selected, ["a", "c"],
                       "M13 P3：反向滑回只能取消单个 id，不得清空快照或误删其他项")
        state.remove(id: "unknown")
        XCTAssertEqual(state.selected, ["a", "c"])
    }

    // MARK: - docs/22 §5.4：selectedSet 缓存一致性 / applyRange / applyDelta

    func testSelectedSetCacheMatchesArrayAfterRandomOps() {
        var state = SelectionState()
        let ids = (0..<200).map { "id-\($0)" }
        state.begin(scope: Set(ids))
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<1_000 {
            let id = ids.randomElement(using: &rng) ?? "id-0"
            switch Int.random(in: 0...3, using: &rng) {
            case 0: state.toggle(id)
            case 1: state.select(id)
            case 2: state.remove(id: id)
            default:
                if Bool.random(using: &rng) { state.selectAll() } else { state.deselectAll() }
            }
            XCTAssertEqual(state.selectedSet, Set(state.selected),
                           "selectedSet 必须始终与 selected 数组同步")
        }
    }

    func testApplyRangeAndApplyDelta() {
        var state = SelectionState()
        state.begin(scope: Set((0..<20).map(String.init)))
        state.applyRange(base: ["1", "19"], range: Set((0...5).map(String.init)))
        XCTAssertEqual(state.selectedSet, Set((0...5).map(String.init)).union(["19"]))
        state.applyDelta(add: ["7"], remove: ["0", "1"])
        XCTAssertEqual(state.selectedSet, Set(["2", "3", "4", "5", "7", "19"]))
        XCTAssertTrue(state.contains("7"))
        XCTAssertFalse(state.contains("0"))
    }
}
