// MARK: - 职责说明：DateSectionizer 单元测试（docs/03 §8 可测试性设计）——
// 跨月/跨年分组、组间倒序、组内保持输入顺序、无日期「未知时间」组、时区注入、空输入。
// 标题断言用宽松口径（含年份）以兼容 Docker/Linux ICU 的语言数据差异；zh_CN 完整标题在 iOS 侧 PhotoDeskTests 断言。

import XCTest
import Foundation
@testable import PhotoDeskCore

final class DateSectionizerTests: XCTestCase {
    /// 固定时区的日历，保证测试与运行机器无关
    private func calendar(timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testMonthGroupingAcrossYears() {
        let calendar = calendar()
        // 输入约定：时间倒序
        let ids = ["a", "b", "c", "d"]
        let dates: [Date?] = [date(calendar, 2026, 10, 31),
                              date(calendar, 2026, 10, 2),
                              date(calendar, 2026, 9, 15),
                              date(calendar, 2025, 1, 1)]
        let sections = DateSectionizer.sections(ids: ids, dates: dates, granularity: .month, calendar: calendar)

        XCTAssertEqual(sections.map(\.identifier), ["2026-10", "2026-09", "2025-01"])
        XCTAssertEqual(sections[0].itemIDs, ["a", "b"])   // 组内保持输入顺序
        XCTAssertEqual(sections[0].itemIDs.count, 2)
        XCTAssertEqual(sections[1].itemIDs, ["c"])
        XCTAssertEqual(sections[2].itemIDs, ["d"])
        // 宽松标题断言（跨平台 ICU 差异安全）
        XCTAssertTrue(sections[0].title.contains("2026"))
        XCTAssertTrue(sections[2].title.contains("2025"))
    }

    func testDayGranularity() {
        let calendar = calendar()
        let ids = ["a", "b", "c"]
        let dates: [Date?] = [date(calendar, 2026, 10, 3, hour: 20),
                              date(calendar, 2026, 10, 3, hour: 8),
                              date(calendar, 2026, 10, 2, hour: 9)]
        let sections = DateSectionizer.sections(ids: ids, dates: dates, granularity: .day, calendar: calendar)

        XCTAssertEqual(sections.map(\.identifier), ["2026-10-03", "2026-10-02"])
        XCTAssertEqual(sections[0].itemIDs, ["a", "b"])
    }

    func testYearGranularity() {
        let calendar = calendar()
        let ids = ["a", "b", "c"]
        let dates: [Date?] = [date(calendar, 2026, 3, 1), date(calendar, 2026, 1, 1), date(calendar, 2024, 7, 7)]
        let sections = DateSectionizer.sections(ids: ids, dates: dates, granularity: .year, calendar: calendar)

        XCTAssertEqual(sections.map(\.identifier), ["2026", "2024"])
        XCTAssertEqual(sections[0].itemIDs, ["a", "b"])
    }

    func testNilDatesGoToUnknownSectionAtEnd() {
        let calendar = calendar()
        let ids = ["a", "n1", "b", "n2"]
        let dates: [Date?] = [date(calendar, 2026, 5, 1), nil, date(calendar, 2026, 4, 1), nil]
        let sections = DateSectionizer.sections(ids: ids, dates: dates, granularity: .month, calendar: calendar)

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].itemIDs, ["a"])
        XCTAssertEqual(sections[1].itemIDs, ["b"])
        let unknown = sections[2]
        XCTAssertEqual(unknown.identifier, DateSectionizer.unknownIdentifier)
        XCTAssertEqual(unknown.title, "未知时间")
        XCTAssertEqual(unknown.itemIDs, ["n1", "n2"])
    }

    func testTimezoneRespected() {
        // 2026-10-31 23:30 UTC：上海时区已是 11 月 1 日，UTC 仍是 10 月 31 日
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let instant = utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!

        let shanghai = calendar() // +8
        let inShanghai = DateSectionizer.sections(ids: ["x"], dates: [instant], granularity: .day, calendar: shanghai)
        let inUTC = DateSectionizer.sections(ids: ["x"], dates: [instant], granularity: .day, calendar: utcCalendar)

        XCTAssertEqual(inShanghai.first?.identifier, "2026-11-01")
        XCTAssertEqual(inUTC.first?.identifier, "2026-10-31")
    }

    func testEmptyInput() {
        XCTAssertTrue(DateSectionizer.sections(ids: [], dates: [], granularity: .month).isEmpty)
    }

    func testSingleItemWithDate() {
        let calendar = calendar()
        let sections = DateSectionizer.sections(ids: ["only"],
                                                dates: [date(calendar, 2026, 1, 2)],
                                                granularity: .month,
                                                calendar: calendar)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].identifier, "2026-01")
        XCTAssertEqual(sections[0].itemIDs, ["only"])
    }
}
