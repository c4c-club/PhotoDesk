// MARK: - MarqueeSelectionPolicyTests：框选集合语义（M17 T04 起仅剩 resolved 层）——
// 基于参数推算的 cells(in:) 几何用例已随实现删除；命中正确性由 App 层
// PhotoDeskTests/LibraryGridGeometryTests 用真实 layoutAttributes 覆盖（docs/32 §4.2）。

import XCTest
@testable import PhotoDeskCore

final class MarqueeSelectionPolicyTests: XCTestCase {
    func testDragBackShrinkYieldsSubset() {
        // 大矩形命中 9 格 → 回拖成小矩形只命中 1 格：同一 base 下目标集合自然收缩
        let base = Set<String>()
        let big = MarqueeSelectionPolicy.resolved(base: base,
                                                  hitIDs: Set((0..<9).map { "id-\($0)" }),
                                                  mode: .select)
        let small = MarqueeSelectionPolicy.resolved(base: base,
                                                    hitIDs: ["id-0"],
                                                    mode: .select)
        XCTAssertTrue(small.isSubset(of: big), "回拖后目标必须是之前的子集")
        XCTAssertEqual(small, ["id-0"])
    }
}

// MARK: - MarqueeModeTests：select / deselect 模式（docs/25 §6.5，≥6 条）

final class MarqueeModeTests: XCTestCase {
    func testModeSelectionByAnchorSelectionState() {
        XCTAssertEqual(MarqueeSelectionPolicy.mode(baseIDs: [], anchorID: "a"), .select)
        XCTAssertEqual(MarqueeSelectionPolicy.mode(baseIDs: ["a"], anchorID: "a"), .deselect)
    }

    func testSelectModeUnions() {
        let result = MarqueeSelectionPolicy.resolved(base: ["a"], hitIDs: ["b", "c"], mode: .select)
        XCTAssertEqual(result, ["a", "b", "c"])
    }

    func testDeselectModeSubtracts() {
        let result = MarqueeSelectionPolicy.resolved(base: ["a", "b", "c"], hitIDs: ["b", "c"], mode: .deselect)
        XCTAssertEqual(result, ["a"])
    }

    func testDeselectMixedBaseOnlyRemovesHits() {
        // base 含未命中的格：deselect 只去掉矩形内（命中）的
        let result = MarqueeSelectionPolicy.resolved(base: ["a", "b", "x"], hitIDs: ["a", "b"], mode: .deselect)
        XCTAssertEqual(result, ["x"])
    }

    func testEmptyHitKeepsBase() {
        XCTAssertEqual(MarqueeSelectionPolicy.resolved(base: ["a"], hitIDs: [], mode: .select), ["a"])
        XCTAssertEqual(MarqueeSelectionPolicy.resolved(base: ["a"], hitIDs: [], mode: .deselect), ["a"])
    }

    func testDeselectCanEmptyBase() {
        let result = MarqueeSelectionPolicy.resolved(base: ["a", "b"], hitIDs: ["a", "b"], mode: .deselect)
        XCTAssertTrue(result.isEmpty)
    }

    func testScopeFiltersHitsInSelectMode() {
        // 月份 scope：矩形跨出 scope 的 cell 不参与选择
        let result = MarqueeSelectionPolicy.resolved(base: [],
                                                     hitIDs: ["in-1", "in-2", "out-1"],
                                                     mode: .select,
                                                     scope: ["in-1", "in-2"])
        XCTAssertEqual(result, ["in-1", "in-2"])
    }

    func testScopeFiltersHitsInDeselectMode() {
        let result = MarqueeSelectionPolicy.resolved(base: ["in-1", "out-1"],
                                                     hitIDs: ["in-1", "out-1"],
                                                     mode: .deselect,
                                                     scope: ["in-1"])
        XCTAssertEqual(result, ["out-1"], "scope 外的格不被取消")
    }

    func testSelectModeIsIdempotent() {
        let first = MarqueeSelectionPolicy.resolved(base: ["a"], hitIDs: ["b"], mode: .select)
        let second = MarqueeSelectionPolicy.resolved(base: first, hitIDs: ["b"], mode: .select)
        XCTAssertEqual(first, second)
    }
}
