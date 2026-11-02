// MARK: - GeoFilterTests：球面距离（赤道/日期变更线/极地/半径边界）+ 0.25° 网格聚类（docs/09 §6.1）

import XCTest
@testable import PhotoDeskCore

final class GeoFilterTests: XCTestCase {
    private func point(_ lat: Double, _ lon: Double) -> GeoPoint {
        GeoPoint(latitude: lat, longitude: lon)
    }

    // MARK: - Haversine 距离

    func testDistanceAlongEquator() {
        // 赤道上 1° 经度 ≈ 111.19 km
        let a = point(0, 0)
        let b = point(0, 1)
        let d = GeoMath.distanceKm(a, b)
        XCTAssertEqual(d, 111.19, accuracy: 0.5)
    }

    func testDistanceAcrossDateLine() {
        // +179.9 与 -179.9 实际相距约 22.2 km（劣弧），不是 40,000 km
        let west = point(0, 179.9)
        let east = point(0, -179.9)
        let d = GeoMath.distanceKm(west, east)
        XCTAssertEqual(d, 22.25, accuracy: 1.0)
    }

    func testDistanceNearPole() {
        // 北极点沿经线 0.5° ≈ 55.6 km
        let pole = point(90, 0)
        let nearby = point(89.5, 0)
        XCTAssertEqual(GeoMath.distanceKm(pole, nearby), 55.6, accuracy: 0.5)
        // 两点都在极点附近但经度差 180°：距离由纬度差决定（经线汇聚）
        let sameLat = point(89.5, 0)
        let otherSide = point(89.5, 180)
        XCTAssertEqual(GeoMath.distanceKm(sameLat, otherSide), 111.19, accuracy: 0.5)
    }

    func testSamePointDistanceZero() {
        XCTAssertEqual(GeoMath.distanceKm(point(31.2, 121.5), point(31.2, 121.5)), 0, accuracy: 1e-9)
    }

    // MARK: - 区域包含（半径边界）

    func testRegionBoundaryInclusive() {
        // 赤道上每度弧长（由地球半径推导，避免硬编码 111.19 的舍入误差）
        let degreesPerKm = 180.0 / (.pi * GeoMath.earthRadiusKm)
        let region = GeoRegion(center: point(0, 0), radiusKm: 25)
        // 半径内 24.999 km（含边界语义：≤ radiusKm）
        let inside = point(0, 24.999 * degreesPerKm)
        XCTAssertTrue(GeoFilter.region(latitude: inside.latitude, longitude: inside.longitude, containsIn: region))
        // 半径外 25.001 km
        let outside = point(0, 25.001 * degreesPerKm)
        XCTAssertFalse(GeoFilter.region(latitude: outside.latitude, longitude: outside.longitude, containsIn: region))
        // 常规远点
        let far = point(0, 0.5)   // ≈ 55.6 km
        XCTAssertFalse(GeoFilter.region(latitude: far.latitude, longitude: far.longitude, containsIn: region))
    }

    func testRegionAcrossDateLine() {
        // 中心 +179.95，半径 25km；-179.95（跨变更线 11 km）应命中
        let region = GeoRegion(center: point(0, 179.95), radiusKm: 25)
        XCTAssertTrue(GeoFilter.region(latitude: 0, longitude: -179.95, containsIn: region))
    }

    // MARK: - 聚类

    func testClusterGroupsWithinCell() {
        // 0.25° 网格：同一桶内的点聚为一组
        let points = [point(31.20, 121.50), point(31.22, 121.52), point(31.24, 121.54),
                      point(40.00, 116.00)]
        let clusters = GeoClusterer.clusters(points: points)
        XCTAssertEqual(clusters.count, 2, " Shanghai 3 点同桶 + 北京 1 点 = 2 组")
        XCTAssertEqual(clusters.first?.count, 3, "按张数降序")
        // 桶中心 = 均值
        let shanghai = clusters.first!
        XCTAssertEqual(shanghai.center.latitude, 31.22, accuracy: 1e-6)
        XCTAssertEqual(shanghai.center.longitude, 121.52, accuracy: 1e-6)
    }

    func testClusterEmptyInput() {
        XCTAssertTrue(GeoClusterer.clusters(points: []).isEmpty)
    }

    func testClusterSortedByCountDesc() {
        var points: [GeoPoint] = []
        for _ in 0..<5 { points.append(point(10.0, 10.0)) }
        for _ in 0..<3 { points.append(point(20.0, 20.0)) }
        points.append(point(30.0, 30.0))
        let clusters = GeoClusterer.clusters(points: points)
        XCTAssertEqual(clusters.map(\.count), [5, 3, 1])
    }

    func testClusterDefaultCellIsQuarterDegree() {
        // 相差 0.3° > 0.25° 桶宽 → 分属两桶（桶宽为默认 0.25°）
        let clusters = GeoClusterer.clusters(points: [point(31.0, 121.0), point(31.3, 121.0)])
        XCTAssertEqual(clusters.count, 2)
    }
}
