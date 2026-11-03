// MARK: - MonthNavigatorTests：monthID/descriptors/yearGroups/nearestIndex
// 覆盖闰年/未知/空/排序/跨年/去重（docs/13 S09：≥10 条）

import XCTest
@testable import PhotoDeskCore

final class MonthNavigatorTests: XCTestCase {
    private func section(_ id: String, count: Int = 2, title: String = "") -> MonthSectionInfo {
        MonthSectionInfo(id: id, title: title, count: count)
    }

    // MARK: - monthID

    func testMonthIDFormatting() {
        XCTAssertEqual(MonthNavigator.monthID(year: 2024, month: 5), "2024-05")
        XCTAssertEqual(MonthNavigator.monthID(year: 2024, month: 12), "2024-12")
        XCTAssertEqual(MonthNavigator.monthID(year: 2020, month: 1), "2020-01")
    }

    func testMonthIDClampsMonth() {
        XCTAssertEqual(MonthNavigator.monthID(year: 2024, month: 0), "2024-01")
        XCTAssertEqual(MonthNavigator.monthID(year: 2024, month: 13), "2024-12")
    }

    func testMonthIDInvalidYearIsUnknown() {
        XCTAssertEqual(MonthNavigator.monthID(year: 0, month: 5), MonthNavigator.unknownIdentifier)
        XCTAssertEqual(MonthNavigator.monthID(year: -3, month: 5), MonthNavigator.unknownIdentifier)
    }

    // MARK: - descriptors

    func testDescriptorsParsesIdsAndCounts() {
        let sections = [section("2024-05", count: 7), section("2024-04", count: 3)]
        let descriptors = MonthNavigator.descriptors(from: sections)
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(descriptors[0].id, "2024-05")
        XCTAssertEqual(descriptors[0].year, 2024)
        XCTAssertEqual(descriptors[0].month, 5)
        XCTAssertEqual(descriptors[0].count, 7)
        XCTAssertEqual(descriptors[0].title, "2024年5月")
    }

    func testDescriptorsSkipsUnknown() {
        let sections = [section("unknown"), section("2024-05")]
        let descriptors = MonthNavigator.descriptors(from: sections)
        XCTAssertEqual(descriptors.map(\.id), ["2024-05"])
    }

    func testDescriptorsEmptyInput() {
        XCTAssertTrue(MonthNavigator.descriptors(from: []).isEmpty)
    }

    func testDescriptorsKeepsDescendingOrder() {
        // 输入为时间倒序（2026 → 2020），输出保持同序
        let sections = [section("2026-10"), section("2025-06"), section("2020-01")]
        XCTAssertEqual(MonthNavigator.descriptors(from: sections).map(\.id),
                       ["2026-10", "2025-06", "2020-01"])
    }

    func testDescriptorsDeduplicatesRepeatedSections() {
        let sections = [section("2024-05", count: 2), section("2024-05", count: 3)]
        XCTAssertEqual(MonthNavigator.descriptors(from: sections).count, 1)
    }

    func testDescriptorsMalformedIdSkipped() {
        let sections = [section("2024-13"), section("abc"), section("2024-02")]
        XCTAssertEqual(MonthNavigator.descriptors(from: sections).map(\.id), ["2024-02"])
    }

    // MARK: - yearGroups

    func testYearGroupsCrossYear() {
        let sections = [section("2026-10"), section("2025-06"), section("2024-05"), section("2024-02")]
        let groups = MonthNavigator.yearGroups(MonthNavigator.descriptors(from: sections))
        XCTAssertEqual(groups.map(\.year), [2026, 2025, 2024])
        XCTAssertEqual(groups[2].months.map(\.id), ["2024-05", "2024-02"])
    }

    func testYearGroupsEmpty() {
        XCTAssertTrue(MonthNavigator.yearGroups([]).isEmpty)
    }

    func testYearGroupsSingleYearMultipleMonths() {
        let groups = MonthNavigator.yearGroups(MonthNavigator.descriptors(from: [
            section("2024-03"), section("2024-02"), section("2024-01"),
        ]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].months.count, 3)
    }

    // MARK: - nearestIndex

    func testNearestIndexExactMatch() {
        let ids = ["2026-10", "2024-05", "2020-01"]
        XCTAssertEqual(MonthNavigator.nearestIndex(for: "2024-05", in: ids), 1)
    }

    func testNearestIndexNearestMonth() {
        let ids = ["2026-10", "2025-06", "2020-01"]
        // 请求 2024-05：距离 |2025-06|=13 vs |2020-01|=52 → index 1
        XCTAssertEqual(MonthNavigator.nearestIndex(for: "2024-05", in: ids), 1)
    }

    func testNearestIndexTieTakesFirst() {
        let ids = ["2024-04", "2024-06"]
        // 2024-05 与两者距离都是 1 → 取先出现者
        XCTAssertEqual(MonthNavigator.nearestIndex(for: "2024-05", in: ids), 0)
    }

    func testNearestIndexEmptyReturnsNil() {
        XCTAssertNil(MonthNavigator.nearestIndex(for: "2024-05", in: []))
    }

    func testNearestIndexSkipsUnknownIds() {
        let ids = ["unknown", "2024-05"]
        XCTAssertEqual(MonthNavigator.nearestIndex(for: "2024-05", in: ids), 1)
    }

    func testNearestIndexUnknownTargetReturnsNil() {
        XCTAssertNil(MonthNavigator.nearestIndex(for: "unknown", in: ["2024-05"]))
    }

    func testLeapYearFebruaryParses() {
        // 闰年 2024-02 / 平年 2023-02 均为合法月份 id
        let sections = [section("2024-02"), section("2023-02")]
        let descriptors = MonthNavigator.descriptors(from: sections)
        XCTAssertEqual(descriptors.map(\.month), [2, 2])
        XCTAssertEqual(descriptors.map(\.year), [2024, 2023])
    }
}
