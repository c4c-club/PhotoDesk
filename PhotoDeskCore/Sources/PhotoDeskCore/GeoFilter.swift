// MARK: - 职责说明：位置筛选纯逻辑（docs/09 D10）——GeoPoint / GeoRegion / 球面距离 / 0.25° 网格聚类。
// 完全离线：不请求定位权限、不联网、不做反向地理编码（红线：App 侧只做 CLLocation → GeoPoint 适配）。
// 距离用 Haversine（大圆距离，跨日期变更线/极地均正确）；聚类用固定网格分桶（输入输出均无 Apple 类型）。

import Foundation

/// 经纬度点（纬度 [-90, 90]，经度 [-180, 180]）
public struct GeoPoint: Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 圆形区域：中心点 + 半径（km）
public struct GeoRegion: Hashable, Codable {
    public let center: GeoPoint
    public let radiusKm: Double

    public init(center: GeoPoint, radiusKm: Double) {
        self.center = center
        self.radiusKm = radiusKm
    }
}

/// 球面几何（Haversine 公式，地球平均半径 6371.0088 km）
public enum GeoMath {
    public static let earthRadiusKm = 6371.0088

    /// 两点大圆距离（km）；跨日期变更线取劣弧（Haversine 以 sin(Δ/2) 计算，天然正确）
    public static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }
}

/// 一个位置聚类：代表点（桶内均值）+ 张数
public struct GeoCluster: Hashable, Codable {
    public let center: GeoPoint
    public let count: Int

    public init(center: GeoPoint, count: Int) {
        self.center = center
        self.count = count
    }
}

/// 位置聚类器：固定 0.25° 网格分桶，桶中心取算术均值，输出按张数降序（同数按坐标稳定排序）。
/// 注：日期变更线两侧（+179.9 / -179.9）会分属不同桶——对「筛选浏览」场景可接受（docs/09 D10）。
public enum GeoClusterer {
    public static let defaultCellDegrees = 0.25

    public static func clusters(points: [GeoPoint],
                                cellDegrees: Double = GeoClusterer.defaultCellDegrees) -> [GeoCluster] {
        let cell = max(0.01, cellDegrees)
        struct Bucket {
            var latSum = 0.0
            var lonSum = 0.0
            var count = 0
        }
        var buckets: [Int: Bucket] = [:]
        for point in points {
            let key = bucketKey(latitude: point.latitude, longitude: point.longitude, cellDegrees: cell)
            var bucket = buckets[key] ?? Bucket()
            bucket.latSum += point.latitude
            bucket.lonSum += point.longitude
            bucket.count += 1
            buckets[key] = bucket
        }
        return buckets
            .map { _, bucket in
                GeoCluster(center: GeoPoint(latitude: bucket.latSum / Double(bucket.count),
                                            longitude: bucket.lonSum / Double(bucket.count)),
                           count: bucket.count)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.center.latitude != rhs.center.latitude { return lhs.center.latitude > rhs.center.latitude }
                return lhs.center.longitude > rhs.center.longitude
            }
    }

    /// 桶键：把 (lat, lon) 折进一个 Int（lat 占高位）。范围有界（±90/±180 / cell），不会溢出。
    private static func bucketKey(latitude: Double, longitude: Double, cellDegrees: Double) -> Int {
        let latIndex = Int((latitude / cellDegrees).rounded(.down))
        let lonIndex = Int((longitude / cellDegrees).rounded(.down))
        return (latIndex + 400) << 24 | (lonIndex + 800)
    }
}

/// 位置筛选判定（App 侧把 CLLocation 拆成 lat/lon 后调用；nil = 无位置信息）
public enum GeoFilter {
    /// 区域内判定：距离中心 ≤ 半径
    public static func region(latitude: Double, longitude: Double, containsIn region: GeoRegion) -> Bool {
        let point = GeoPoint(latitude: latitude, longitude: longitude)
        return GeoMath.distanceKm(point, region.center) <= region.radiusKm
    }
}
