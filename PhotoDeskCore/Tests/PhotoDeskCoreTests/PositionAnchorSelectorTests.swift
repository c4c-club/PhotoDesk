// MARK: - 职责说明：PositionAnchorSelector 纯函数测试（docs/22 §4.6）——
// 首条完整可见、半遮挡、空输入、effectiveTop 边界、跨 section、部分可见兜底。

import XCTest
@testable import PhotoDeskCore

final class PositionAnchorSelectorTests: XCTestCase {
    private func cell(_ section: Int, _ item: Int, _ minY: Double, _ maxY: Double) -> VisibleGridCell {
        VisibleGridCell(section: section, item: item, minY: minY, maxY: maxY)
    }

    func testSelectsFirstFullyVisibleCell() {
        let cells = [cell(0, 0, 0, 100),
                     cell(0, 1, 100, 200),
                     cell(0, 2, 200, 300)]
        let selected = PositionAnchorSelector.select(cells: cells, effectiveTop: 100, viewportBottom: 700)
        XCTAssertEqual(selected?.item, 1, "第一条完整可见应是 item 1（item 0 被粘性头遮挡）")
    }

    func testHalfOccludedCellIsSkipped() {
        let cells = [cell(0, 0, 0, 250),
                     cell(0, 1, 250, 350)]
        let selected = PositionAnchorSelector.select(cells: cells, effectiveTop: 150, viewportBottom: 700)
        XCTAssertEqual(selected?.item, 1, "maxY 很大但 minY 在 effectiveTop 之上：半遮挡必须跳过")
    }

    func testEmptyCellsReturnsNil() {
        XCTAssertNil(PositionAnchorSelector.select(cells: [], effectiveTop: 0, viewportBottom: 700))
    }

    func testNonFiniteOrInvertedViewportReturnsNil() {
        let cells = [cell(0, 0, 0, 100)]
        XCTAssertNil(PositionAnchorSelector.select(cells: cells, effectiveTop: .nan, viewportBottom: 700))
        XCTAssertNil(PositionAnchorSelector.select(cells: cells, effectiveTop: 700, viewportBottom: 700))
        XCTAssertNil(PositionAnchorSelector.select(cells: cells, effectiveTop: 0, viewportBottom: .infinity))
    }

    func testBoundaryEffectiveTopMinusHalfPointIsAccepted() {
        let cells = [cell(0, 0, 99.5, 200)]
        let selected = PositionAnchorSelector.select(cells: cells, effectiveTop: 100, viewportBottom: 700)
        XCTAssertEqual(selected?.item, 0, "minY >= effectiveTop - 0.5 的边界 cell 应视为完整可见")
    }

    func testCrossSectionSortsBySectionThenItem() {
        let cells = [cell(1, 0, 0, 100),
                     cell(0, 1, 100, 200)]
        let selected = PositionAnchorSelector.select(cells: cells, effectiveTop: 50, viewportBottom: 700)
        XCTAssertEqual(selected?.section, 0, "按 (section,item) 升序：section 0 应先于 section 1")
        XCTAssertEqual(selected?.item, 1)
    }

    func testFallsBackToFirstPartiallyVisibleCell() {
        let cells = [cell(0, 0, 0, 80),
                     cell(0, 1, 20, 100),
                     cell(0, 2, 40, 120)]
        let selected = PositionAnchorSelector.select(cells: cells, effectiveTop: 100, viewportBottom: 700)
        XCTAssertEqual(selected?.item, 2, "没有完整可见时取 maxY > effectiveTop 的第一条")
    }

    func testCellBelowViewportIsIgnoredForFullyVisible() {
        let cells = [cell(0, 0, 800, 900),
                     cell(0, 1, 900, 1000)]
        let selected = PositionAnchorSelector.select(cells: cells, effectiveTop: 0, viewportBottom: 700)
        XCTAssertNil(selected, "视口下方 cell 不得被选为锚点")
    }
}
