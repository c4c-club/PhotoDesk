// MARK: - 职责说明：App 侧日期分组适配层测试（docs/05 M1 验收）——
// zh_CN 标题（iOS ICU 保证完整格式）、分组数与计数一致、组内顺序保持倒序。
// 核心纯逻辑的分组/时区测试在 PhotoDeskCoreTests（Docker + core-linux 双跑）。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

final class DateSectionizerTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testMonthTitleInChinese() {
        let calendar = self.calendar()
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let result = DateSectionizerAdapter.monthSections(ids: ["a"], dates: [date])

        XCTAssertEqual(result.sections.count, 1)
        XCTAssertEqual(result.sections[0].title, "2026年10月")
        XCTAssertEqual(result.sections[0].headerTitle, "2026年10月 · 1 张")
        XCTAssertEqual(result.orderedIDs, ["a"])
    }

    func testCountsAndOrdering() {
        let calendar = self.calendar()
        let ids = ["a", "b", "c", "d"]
        let dates: [Date?] = [
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 31)),
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)),
            nil,
        ]
        let result = DateSectionizerAdapter.monthSections(ids: ids, dates: dates)

        XCTAssertEqual(result.sections.map(\.id), ["2026-10", "2026-09", DateSectionizer.unknownIdentifier])
        XCTAssertEqual(result.sections.map(\.count), [2, 1, 1])
        // orderedIDs 与输入条目一一对应、组内保持输入顺序、未知组置尾
        XCTAssertEqual(result.orderedIDs, ["a", "b", "c", "d"])
    }

    func testEmpty() {
        let result = DateSectionizerAdapter.monthSections(ids: [], dates: [])
        XCTAssertTrue(result.sections.isEmpty)
        XCTAssertTrue(result.orderedIDs.isEmpty)
    }
}
