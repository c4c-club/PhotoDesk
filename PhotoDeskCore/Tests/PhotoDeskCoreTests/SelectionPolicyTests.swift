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
}
