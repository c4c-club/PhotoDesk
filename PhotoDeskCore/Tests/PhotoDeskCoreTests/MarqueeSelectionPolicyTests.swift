// MARK: - MarqueeSelectionPolicyTests：矩形框选几何（docs/25 §6.2 / M15 P0-3，≥14 条）——
// 3/5 列左列竖直下拉只选左列；右列同理；斜向矩形；跨 section；末行不满；间距边界；
// 0/NaN/负值安全；回拖收缩。网格约定：itemWidth=Height=100、spacing=10、header=48，
// 行距/列距 110；section0 top=48，section1 origin=288（top=336）。

import XCTest
@testable import PhotoDeskCore

final class MarqueeSelectionPolicyTests: XCTestCase {
    private let metrics3 = GridMetrics(columns: 3, itemWidth: 100, itemHeight: 100,
                                       interItemSpacing: 10, sectionHeaderHeight: 48,
                                       sectionItemCounts: [9])
    private let originSingle: [Double] = [0]

    private func cells(_ rect: MarqueeRect,
                       metrics: GridMetrics? = nil,
                       origins: [Double]? = nil) -> Set<SlideSelectCell> {
        MarqueeSelectionPolicy.cells(in: rect,
                                     metrics: metrics ?? metrics3,
                                     sectionOriginY: origins ?? originSingle)
    }

    // MARK: - 竖直下拉（核心回归：绝不再选整行）

    func testLeftColumnVerticalDragSelectsOnlyLeftColumn() {
        // 3 列，左列 x≈10 竖直下拉：矩形宽扩展 1pt，只能命中第 0 列
        let result = cells(MarqueeRect(startX: 10, startY: 60, currentX: 10, currentY: 500))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 0),
                                SlideSelectCell(section: 0, item: 3),
                                SlideSelectCell(section: 0, item: 6)])
    }

    func testRightColumnVerticalDragSelectsOnlyRightColumn() {
        let result = cells(MarqueeRect(startX: 230, startY: 60, currentX: 230, currentY: 500))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 2),
                                SlideSelectCell(section: 0, item: 5),
                                SlideSelectCell(section: 0, item: 8)])
    }

    func testFiveColumnsVerticalDragSelectsOnlyOneColumn() {
        let metrics5 = GridMetrics(columns: 5, itemWidth: 70, itemHeight: 70,
                                   interItemSpacing: 8, sectionHeaderHeight: 48,
                                   sectionItemCounts: [10])
        // 5 列：第 1 列 x≈80；行距 78，行高 70；y 60→400 覆盖行 0..4（maxRow=1，共 2 行）
        let result = cells(MarqueeRect(startX: 80, startY: 60, currentX: 80, currentY: 400),
                           metrics: metrics5)
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 1),
                                SlideSelectCell(section: 0, item: 6)])
    }

    // MARK: - 斜向矩形

    func testDiagonalMarqueeSelectsRectangle() {
        // 对角拖动：覆盖 3 列 × 行 0..2（9 项全命中）
        let result = cells(MarqueeRect(startX: 10, startY: 60, currentX: 320, currentY: 400))
        XCTAssertEqual(result.count, 9)
        XCTAssertTrue(result.contains(SlideSelectCell(section: 0, item: 0)))
        XCTAssertTrue(result.contains(SlideSelectCell(section: 0, item: 4)))
        XCTAssertTrue(result.contains(SlideSelectCell(section: 0, item: 8)))
    }

    func testDiagonalMarqueePartialColumns() {
        // 拖到第 2 列中点（x≈165）：命中第 0、1 列
        let result = cells(MarqueeRect(startX: 10, startY: 60, currentX: 165, currentY: 160))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 0),
                                SlideSelectCell(section: 0, item: 1),
                                SlideSelectCell(section: 0, item: 3),
                                SlideSelectCell(section: 0, item: 4)])
    }

    // MARK: - 跨 section / 末行不满

    func testRectSpansMultipleSections() {
        let metrics = GridMetrics(columns: 3, itemWidth: 100, itemHeight: 100,
                                  interItemSpacing: 10, sectionHeaderHeight: 48,
                                  sectionItemCounts: [9, 4])
        let origins: [Double] = [0, 288]   // section1 top = 288+48 = 336
        // 左列下拉 60→400：section0 三行 col0 + section1 行 0（top 336 ≤ 400）col0
        let result = cells(MarqueeRect(startX: 10, startY: 60, currentX: 10, currentY: 400),
                           metrics: metrics, origins: origins)
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 0),
                                SlideSelectCell(section: 0, item: 3),
                                SlideSelectCell(section: 0, item: 6),
                                SlideSelectCell(section: 1, item: 0)])
    }

    func testLastRowNotFullIsClamped() {
        let metrics = GridMetrics(columns: 3, itemWidth: 100, itemHeight: 100,
                                  interItemSpacing: 10, sectionHeaderHeight: 48,
                                  sectionItemCounts: [7])
        // 全宽覆盖行 0..2：行 2 只有 item 6（末行不满）
        let result = cells(MarqueeRect(startX: 0, startY: 60, currentX: 330, currentY: 500),
                           metrics: metrics)
        XCTAssertEqual(result, Set((0..<7).map { SlideSelectCell(section: 0, item: $0) }))
    }

    // MARK: - 0 尺寸 / 间距 / 边界

    func testZeroWidthRectExpandsToOnePoint() {
        // 起手即选中语义：start == current 也必须命中手指下的 cell
        let result = cells(MarqueeRect(startX: 10, startY: 60, currentX: 10, currentY: 60))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 0)])
    }

    func testZeroHeightHorizontalDragHitsRow() {
        let result = cells(MarqueeRect(startX: 10, startY: 200, currentX: 320, currentY: 200))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 3),
                                SlideSelectCell(section: 0, item: 4),
                                SlideSelectCell(section: 0, item: 5)])
    }

    func testTouchingEdgesCountAsIntersection() {
        // rect 右边界恰好等于 cell1 左边界（x=110）：按闭区间相交语义 cell0 与 cell1 都命中
        let result = cells(MarqueeRect(startX: 110, startY: 60, currentX: 95, currentY: 100))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 0),
                                SlideSelectCell(section: 0, item: 1)])
    }

    func testRectFullyInsideGapHitsNothing() {
        // 矩形完全落在列间隙 [101,106]（宽 5pt ≥ 1 不扩展）：与左右 cell 都不相交 → 空
        let result = cells(MarqueeRect(startX: 101, startY: 60, currentX: 106, currentY: 100))
        XCTAssertTrue(result.isEmpty, "列间隙内的矩形不命中任何 cell")
    }

    // MARK: - 非有限 / 负值 / 退化输入

    func testNaNRectReturnsEmpty() {
        let result = cells(MarqueeRect(startX: .nan, startY: 0, currentX: 100, currentY: 100))
        XCTAssertTrue(result.isEmpty, "NaN 输入必须返回空集合")
    }

    func testInfiniteRectReturnsEmpty() {
        let result = cells(MarqueeRect(startX: 0, startY: 0, currentX: .infinity, currentY: 100))
        XCTAssertTrue(result.isEmpty, "∞ 输入必须返回空集合")
    }

    func testNegativeRectClampsToFirstCells() {
        // 负坐标起点（视口上沿外）：钳到第 0 列/行
        let result = cells(MarqueeRect(startX: -50, startY: -50, currentX: 50, currentY: 60))
        XCTAssertEqual(result, [SlideSelectCell(section: 0, item: 0)])
    }

    func testZeroColumnsReturnsEmpty() {
        let bad = GridMetrics(columns: 0, itemWidth: 100, itemHeight: 100,
                              interItemSpacing: 10, sectionHeaderHeight: 48,
                              sectionItemCounts: [9])
        let result = cells(MarqueeRect(startX: 0, startY: 0, currentX: 100, currentY: 100),
                           metrics: bad)
        XCTAssertTrue(result.isEmpty)
    }

    func testZeroItemSizeReturnsEmpty() {
        let bad = GridMetrics(columns: 3, itemWidth: 0, itemHeight: 100,
                              interItemSpacing: 10, sectionHeaderHeight: 48,
                              sectionItemCounts: [9])
        let result = cells(MarqueeRect(startX: 0, startY: 0, currentX: 100, currentY: 100),
                           metrics: bad)
        XCTAssertTrue(result.isEmpty)
    }

    func testOriginCountMismatchReturnsEmpty() {
        let result = cells(MarqueeRect(startX: 0, startY: 0, currentX: 100, currentY: 100),
                           origins: [0, 288, 600])
        XCTAssertTrue(result.isEmpty, "sectionOriginY 与 metrics 数量不一致 → 空集合")
    }

    // MARK: - 回拖收缩（resolved 层面的单调性）

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
