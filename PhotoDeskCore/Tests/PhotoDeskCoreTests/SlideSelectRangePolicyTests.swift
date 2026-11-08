// MARK: - 职责说明：滑动多选整行区间测试（docs/22 §5.7）——
// 右列下滑选整行、回拖恢复快照、跨月、单月不泄漏、横向整行、最后一行不满。

import XCTest
@testable import PhotoDeskCore

final class SlideSelectRangePolicyTests: XCTestCase {
    func testVerticalDragOnRightColumnSelectsWholeRows() {
        let metrics = SlideGridMetrics(columns: 3, sectionItemCounts: [30])
        let range = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 2),
                                                 current: SlideSelectCell(section: 0, item: 14),
                                                 metrics: metrics)
        XCTAssertEqual(range.count, 15, "第 0 行右列到第 4 行右列必须选中 15 个")
        XCTAssertTrue(range.contains(SlideSelectCell(section: 0, item: 0)),
                      "用户原话：右列下滑时最左列同行也必须选中")
        XCTAssertTrue(range.contains(SlideSelectCell(section: 0, item: 1)))
    }

    func testDragBackRestoresOriginalSnapshot() {
        let metrics = SlideGridMetrics(columns: 3, sectionItemCounts: [30])
        let base: Set<String> = ["4"]
        var state = SelectionState()
        state.begin(scope: Set((0..<30).map(String.init)))
        state.replaceSelection(Array(base))

        let forward = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 0),
                                                   current: SlideSelectCell(section: 0, item: 12),
                                                   metrics: metrics)
        let forwardIDs = Set(forward.map { String($0.item) })
        state.applyRange(base: base, range: forwardIDs)
        XCTAssertEqual(state.selectedSet, Set((0...14).map(String.init)), "前进到第 4 行应选中 0...14 + 原选中 4")

        let back = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 0),
                                                current: SlideSelectCell(section: 0, item: 0),
                                                metrics: metrics)
        state.applyRange(base: base, range: Set(back.map { String($0.item) }))
        XCTAssertEqual(state.selectedSet, base, "回拖到起始行必须只恢复拖动前快照，不误取消原选中")
    }

    func testCrossMonthSelectsFullRowsInEachSection() {
        let metrics = SlideGridMetrics(columns: 3, sectionItemCounts: [9, 6])
        let range = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 7),
                                                 current: SlideSelectCell(section: 1, item: 4),
                                                 metrics: metrics)
        XCTAssertTrue(range.contains(SlideSelectCell(section: 0, item: 6)))
        XCTAssertTrue(range.contains(SlideSelectCell(section: 0, item: 8)))
        XCTAssertTrue(range.contains(SlideSelectCell(section: 1, item: 0)))
        XCTAssertTrue(range.contains(SlideSelectCell(section: 1, item: 5)))
        XCTAssertEqual(range.count, 9, "section0 末行 3 个 + section1 两整行 6 个")
    }

    func testMonthScopeDoesNotLeakToOtherSections() {
        let metrics = SlideGridMetrics(columns: 3, sectionItemCounts: [9])
        let range = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 0),
                                                 current: SlideSelectCell(section: 0, item: 8),
                                                 metrics: metrics)
        XCTAssertEqual(range.count, 9)
        XCTAssertFalse(range.contains(SlideSelectCell(section: 1, item: 0)))
    }

    func testHorizontalDragSelectsWholeRow() {
        let metrics = SlideGridMetrics(columns: 3, sectionItemCounts: [9])
        let range = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 1),
                                                 current: SlideSelectCell(section: 0, item: 2),
                                                 metrics: metrics)
        XCTAssertEqual(range, Set((0...2).map { SlideSelectCell(section: 0, item: $0) }))
    }

    func testLastRowPartialFill() {
        let metrics = SlideGridMetrics(columns: 3, sectionItemCounts: [8])
        let range = SlideSelectRangePolicy.cells(anchor: SlideSelectCell(section: 0, item: 6),
                                                 current: SlideSelectCell(section: 0, item: 7),
                                                 metrics: metrics)
        XCTAssertEqual(range, Set([SlideSelectCell(section: 0, item: 6),
                                   SlideSelectCell(section: 0, item: 7)]))
        XCTAssertFalse(range.contains(SlideSelectCell(section: 0, item: 8)),
                       "最后一行不满时不得越界生成 item 8")
    }

    func testRowCalculation() {
        XCTAssertEqual(SlideSelectRangePolicy.row(of: SlideSelectCell(section: 0, item: 0), columns: 3), 0)
        XCTAssertEqual(SlideSelectRangePolicy.row(of: SlideSelectCell(section: 0, item: 2), columns: 3), 0)
        XCTAssertEqual(SlideSelectRangePolicy.row(of: SlideSelectCell(section: 0, item: 3), columns: 3), 1)
    }
}
