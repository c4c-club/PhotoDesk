// MARK: - 职责说明：PhotoFilter 位置维度单元测试（docs/09 D10）——有/无位置/附近区域（离线球面距离）。

import XCTest
import CoreLocation
import PhotoDeskCore
@testable import PhotoDesk

final class PhotoFilterLocationTests: XCTestCase {
    private func item(id: String, latitude: Double?, longitude: Double?) -> PhotoItem {
        let location: CLLocation?
        if let latitude, let longitude {
            location = CLLocation(latitude: latitude, longitude: longitude)
        } else {
            location = nil
        }
        return PhotoItem(id: id,
                         mediaType: .image,
                         mediaSubtypes: [],
                         creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                         modificationDate: nil,
                         pixelWidth: 10, pixelHeight: 10, duration: 0,
                         isFavorite: false, isHidden: false,
                         location: location,
                         burstIdentifier: nil,
                         isCloudOnly: false)
    }

    func testWithLocation() {
        let items = [item(id: "gps", latitude: 31.2, longitude: 121.5),
                     item(id: "nogps", latitude: nil, longitude: nil)]
        var predicate = SearchPredicate.default
        predicate.location = .withLocation
        let result = PhotoFilter.apply(items, predicate: predicate)
        XCTAssertEqual(result.map(\.id), ["gps"])
    }

    func testWithoutLocation() {
        let items = [item(id: "gps", latitude: 31.2, longitude: 121.5),
                     item(id: "nogps", latitude: nil, longitude: nil)]
        var predicate = SearchPredicate.default
        predicate.location = .withoutLocation
        let result = PhotoFilter.apply(items, predicate: predicate)
        XCTAssertEqual(result.map(\.id), ["nogps"])
    }

    func testNearRegion() {
        // 上海 25 km 内；北京（~1,070 km 外）不命中
        let items = [item(id: "shanghai", latitude: 31.23, longitude: 121.47),
                     item(id: "beijing", latitude: 39.9, longitude: 116.4),
                     item(id: "nogps", latitude: nil, longitude: nil)]
        var predicate = SearchPredicate.default
        predicate.location = .near(GeoRegion(center: GeoPoint(latitude: 31.23, longitude: 121.47),
                                             radiusKm: 25))
        let result = PhotoFilter.apply(items, predicate: predicate)
        XCTAssertEqual(result.map(\.id), ["shanghai"])
    }

    func testLocationIsActiveFlag() {
        var predicate = SearchPredicate.default
        XCTAssertFalse(predicate.isActive)
        predicate.location = .withLocation
        XCTAssertTrue(predicate.isActive, "location 纳入 isActive（docs/09 D10）")
        predicate.location = .any
        XCTAssertFalse(predicate.isActive)
    }

    func testAnyLocationReturnsAll() {
        let items = [item(id: "a", latitude: nil, longitude: nil),
                     item(id: "b", latitude: 1, longitude: 1)]
        let result = PhotoFilter.apply(items, predicate: .default)
        XCTAssertEqual(result.count, 2)
    }

    func testCombinedFilterYearAndLocation() {
        let calendar = Calendar.current
        func dated(_ id: String, year: Int, lat: Double?) -> PhotoItem {
            var date = DateComponents()
            date.year = year; date.month = 6; date.day = 1
            let item = item(id: id, latitude: lat, longitude: lat != nil ? 121.0 : nil)
            return PhotoItem(id: item.id,
                             mediaType: item.mediaType,
                             mediaSubtypes: item.mediaSubtypes,
                             creationDate: calendar.date(from: date),
                             modificationDate: nil,
                             pixelWidth: 10, pixelHeight: 10, duration: 0,
                             isFavorite: false, isHidden: false,
                             location: lat != nil ? item.location : nil,
                             burstIdentifier: nil, isCloudOnly: false)
        }
        let items = [dated("old-near", year: 2023, lat: 31.2),
                     dated("old-far", year: 2023, lat: 39.9),
                     dated("new-near", year: 2026, lat: 31.2)]
        var predicate = SearchPredicate.default
        predicate.year = 2023
        predicate.location = .near(GeoRegion(center: GeoPoint(latitude: 31.2, longitude: 121.0),
                                             radiusKm: 50))
        let result = PhotoFilter.apply(items, predicate: predicate)
        XCTAssertEqual(result.map(\.id), ["old-near"], "年份 AND 位置组合筛选")
    }
}
