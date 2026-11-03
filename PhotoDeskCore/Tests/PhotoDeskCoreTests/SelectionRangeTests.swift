// MARK: - SelectionRangeTests：有序列表内 anchor→target 连续范围（docs/13 S07：≥10 条）

import XCTest
@testable import PhotoDeskCore

final class SelectionRangeTests: XCTestCase {
    private let ordered = ["a", "b", "c", "d", "e"]

    func testForwardRange() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "b", to: "d"), ["b", "c", "d"])
    }

    func testReverseRange() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "d", to: "b"), ["b", "c", "d"])
    }

    func testSameAnchorAndTargetReturnsSingle() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "c", to: "c"), ["c"])
    }

    func testMissingAnchorReturnsEmpty() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "zzz", to: "c"), [])
    }

    func testMissingTargetReturnsEmpty() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "a", to: "zzz"), [])
    }

    func testEmptyListReturnsEmpty() {
        XCTAssertEqual(SelectionRange.ids(in: [], from: "a", to: "b"), [])
    }

    func testWholeListRange() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "a", to: "e"), ordered)
    }

    func testAdjacentElementsReturnTwo() {
        XCTAssertEqual(SelectionRange.ids(in: ordered, from: "c", to: "d"), ["c", "d"])
    }

    func testDuplicatesInListAreDeduped() {
        let duplicated = ["a", "b", "a", "c", "b"]
        XCTAssertEqual(SelectionRange.ids(in: duplicated, from: "a", to: "c"), ["a", "b", "c"])
    }

    func testLargeListWithin10ms() {
        let large = (0..<10_000).map { "id-\($0)" }
        let start = Date()
        let result = SelectionRange.ids(in: large, from: "id-0", to: "id-9999")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.count, 10_000)
        XCTAssertLessThan(elapsed, 0.010, "10k 列表范围选择应 < 10ms，实际 \(elapsed * 1000)ms")
    }

    func testRangeKeepsListOrderNotSelectionOrder() {
        // 反向拖选（target 在 anchor 前）结果仍按列表顺序
        let result = SelectionRange.ids(in: ordered, from: "e", to: "a")
        XCTAssertEqual(result, ordered)
    }
}
