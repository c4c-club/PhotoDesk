// MARK: - 职责说明：SearchPredicate/PhotoFilter 单元测试（docs/05 M5 验收）——
// 组合筛选正确性（日期下钻/媒体多选/状态/无日期条目）+ 10,000 张合成库 < 500ms 性能验收。

import XCTest
@testable import PhotoDesk

@MainActor
final class SearchPredicateTests: XCTestCase {
    /// 固定时区日历（Asia/Shanghai +8）
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func makeItem(id: String,
                          mediaType: MediaType = .image,
                          subtypes: MediaSubtypes = [],
                          year: Int? = nil, month: Int? = nil, day: Int? = nil,
                          hour: Int = 12,
                          isFavorite: Bool = false) -> PhotoItem {
        let date: Date? = year.flatMap { y in
            calendar.date(from: DateComponents(year: y,
                                               month: month ?? 6,
                                               day: day ?? 15,
                                               hour: hour))
        }
        return PhotoItem(id: id,
                         mediaType: mediaType,
                         mediaSubtypes: subtypes,
                         creationDate: date,
                         modificationDate: nil,
                         pixelWidth: 100,
                         pixelHeight: 100,
                         duration: 0,
                         isFavorite: isFavorite,
                         isHidden: false,
                         location: nil,
                         burstIdentifier: nil,
                         isCloudOnly: false)
    }

    // MARK: - 日期下钻

    func testYearMonthDayDrillDown() {
        let items = [
            makeItem(id: "a", year: 2026, month: 10, day: 3),
            makeItem(id: "b", year: 2026, month: 10, day: 4),
            makeItem(id: "c", year: 2026, month: 9, day: 3),
            makeItem(id: "d", year: 2025, month: 10, day: 3),
        ]
        var predicate = SearchPredicate.default
        predicate.year = 2026
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate, calendar: calendar).map(\.id),
                       ["a", "b", "c"])

        predicate.month = 10
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate, calendar: calendar).map(\.id),
                       ["a", "b"])

        predicate.day = 3
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate, calendar: calendar).map(\.id),
                       ["a"])
    }

    func testMonthOnlyMatchesAcrossYears() {
        let items = [
            makeItem(id: "a", year: 2026, month: 5),
            makeItem(id: "b", year: 2020, month: 5),
            makeItem(id: "c", year: 2026, month: 6),
        ]
        var predicate = SearchPredicate.default
        predicate.month = 5
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate, calendar: calendar).map(\.id),
                       ["a", "b"])
    }

    func testNilDateItemsExcludedWhenDateFilterActive() {
        let items = [
            makeItem(id: "dated", year: 2026),
            makeItem(id: "undated"),   // 无 creationDate（如部分导入图）
        ]
        var predicate = SearchPredicate.default
        predicate.year = 2026
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate, calendar: calendar).map(\.id),
                       ["dated"])
    }

    // MARK: - 媒体多选（OR）

    func testMediaMultiSelectIsOr() {
        let items = [
            makeItem(id: "photo", mediaType: .image),
            makeItem(id: "video", mediaType: .video),
            makeItem(id: "live", subtypes: [.photoLive]),
            makeItem(id: "screenshot", subtypes: [.photoScreenshot]),
            makeItem(id: "portrait", subtypes: [.photoDepthEffect]),
            makeItem(id: "panorama", subtypes: [.photoPanorama]),
            makeItem(id: "slomo", mediaType: .video, subtypes: [.videoSlowMo]),
            makeItem(id: "timelapse", mediaType: .video, subtypes: [.videoTimelapse]),
        ]
        var predicate = SearchPredicate.default
        predicate.media = [.screenshot, .portrait]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate).map(\.id).sorted(),
                       ["portrait", "screenshot"])

        predicate.media = [.slowMotion]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate).map(\.id), ["slomo"])

        predicate.media = [.timeLapse]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate).map(\.id), ["timelapse"])
    }

    // MARK: - 状态（AND）

    func testStatusFilters() {
        let items = [
            makeItem(id: "fav", isFavorite: true),
            makeItem(id: "plain", isFavorite: false),
        ]
        var predicate = SearchPredicate.default
        predicate.status = [.favorite]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate).map(\.id), ["fav"])

        predicate.status = [.unorganized]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate).map(\.id), ["plain"])
    }

    func testCombinedPredicateIsAnd() {
        // 媒体（OR）∩ 状态（AND）∩ 日期
        let items = [
            makeItem(id: "hit", mediaType: .video, year: 2026, isFavorite: true),
            makeItem(id: "wrongType", mediaType: .image, year: 2026, isFavorite: true),
            makeItem(id: "wrongStatus", mediaType: .video, year: 2026, isFavorite: false),
            makeItem(id: "wrongYear", mediaType: .video, year: 2020, isFavorite: true),
        ]
        var predicate = SearchPredicate.default
        predicate.year = 2026
        predicate.media = [.video]
        predicate.status = [.favorite]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: predicate, calendar: calendar).map(\.id),
                       ["hit"])
    }

    func testDefaultPredicateReturnsAll() {
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        XCTAssertEqual(PhotoFilter.apply(items, predicate: .default).count, 2)
    }

    // MARK: - 维度取值

    func testAvailableDimensions() {
        let items = [
            makeItem(id: "a", year: 2026, month: 10),
            makeItem(id: "b", year: 2026, month: 9),
            makeItem(id: "c", year: 2024, month: 10),
        ]
        XCTAssertEqual(PhotoFilter.availableYears(items, calendar: calendar), [2026, 2024])
        XCTAssertEqual(PhotoFilter.availableMonths(items, year: 2026, calendar: calendar), [10, 9])
        XCTAssertEqual(PhotoFilter.availableMonths(items, year: 2024, calendar: calendar), [10])
    }

    // MARK: - 性能验收（docs/05 §7：10,000 张 < 500ms）

    func testTenThousandItemsUnderHalfSecond() {
        var items: [PhotoItem] = []
        items.reserveCapacity(10_000)
        // 基值 2021-01-01，每张 +1h → 跨度约 416 天，2021 年内必有大量命中
        let base = calendar.date(from: DateComponents(year: 2021, month: 1, day: 1))!
        for index in 0..<10_000 {
            let date = base.addingTimeInterval(Double(index) * 3_600)
            items.append(PhotoItem(id: "item-\(index)",
                                   mediaType: index % 7 == 0 ? .video : .image,
                                   mediaSubtypes: index % 11 == 0 ? [.photoScreenshot] : [],
                                   creationDate: date,
                                   modificationDate: nil,
                                   pixelWidth: 100, pixelHeight: 100,
                                   duration: 0,
                                   isFavorite: index % 3 == 0,
                                   isHidden: false,
                                   location: nil,
                                   burstIdentifier: nil,
                                   isCloudOnly: false))
        }

        var predicate = SearchPredicate.default
        predicate.year = 2021
        predicate.media = [.photo, .video, .screenshot]
        predicate.status = [.favorite]

        let start = Date()
        let results = PhotoFilter.apply(items, predicate: predicate, calendar: calendar)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(results.isEmpty, "2021 年应有命中（合成数据覆盖 2021 全年）")
        XCTAssertLessThan(elapsed, 0.5, "10,000 张组合筛选耗时 \(elapsed * 1000)ms，预算 500ms")
    }
}
