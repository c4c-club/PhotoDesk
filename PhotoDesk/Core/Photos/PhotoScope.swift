// MARK: - 职责说明：照片库查询范围（docs/03 §4.1）——网格/浏览页/相簿统一的 scope 抽象。
// .hidden 需 includeHiddenAssets = true（其余 scope 一律 false，主网格不含隐藏——AGENTS.md §4.2）。

import Photos
import PhotoDeskCore

enum PhotoScope: Hashable {
    case all
    case favorites
    case hidden
    case recentlyDeleted
    case videos
    case screenshots
    case album(localIdentifier: String)
    case smartAlbum(subtype: PHAssetCollectionSubtype)
    case search(SearchPredicate)
}

/// 位置筛选维度（docs/09 D10）——完全离线：不请求定位、不联网、不做反向地理编码。
/// near(GeoRegion) 由 PhotoDeskCore.GeoFilter 球面距离判定（App 侧只拆 CLLocation → 经纬度）。
enum LocationFilter: Hashable {
    case any
    case withLocation
    case withoutLocation
    case near(GeoRegion)
}

extension LocationFilter: Codable {
    private enum CodingKeys: String, CodingKey { case type, latitude, longitude, radiusKm }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "any":            self = .any
        case "withLocation":   self = .withLocation
        case "withoutLocation": self = .withoutLocation
        case "near":
            let center = GeoPoint(latitude: try container.decode(Double.self, forKey: .latitude),
                                  longitude: try container.decode(Double.self, forKey: .longitude))
            self = .near(GeoRegion(center: center,
                                   radiusKm: try container.decode(Double.self, forKey: .radiusKm)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container,
                                                   debugDescription: "未知 LocationFilter 类型")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:              try container.encode("any", forKey: .type)
        case .withLocation:     try container.encode("withLocation", forKey: .type)
        case .withoutLocation:  try container.encode("withoutLocation", forKey: .type)
        case .near(let region):
            try container.encode("near", forKey: .type)
            try container.encode(region.center.latitude, forKey: .latitude)
            try container.encode(region.center.longitude, forKey: .longitude)
            try container.encode(region.radiusKm, forKey: .radiusKm)
        }
    }
}

/// 多维筛选谓词（docs/05 M5 任务 5.1/5.2；docs/09 D10 扩展 location）——日期三级下钻 + 媒体类型多选 + 状态 + 位置。
/// 匹配引擎见 PhotoFilter（纯函数可单测）；Codable 供 LibraryQuery 稳定摘要与筛选持久化。
struct SearchPredicate: Hashable, Codable {
    /// 媒体类型维度（照片/视频/Live/截图/人像/全景/慢动作/延时）。
    /// RAW 无公开 subtype（需逐资源枚举 PHAssetResource，万级库不可承受），暂未支持，登记于已知问题
    enum MediaFilter: String, CaseIterable, Identifiable, Hashable, Codable {
        case photo, video, live, screenshot, portrait, panorama, slowMotion, timeLapse

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .photo:      return "照片"
            case .video:      return "视频"
            case .live:       return "Live Photo"
            case .screenshot: return "截图"
            case .portrait:   return "人像"
            case .panorama:   return "全景"
            case .slowMotion: return "慢动作"
            case .timeLapse:  return "延时"
            }
        }
    }

    /// 状态维度（.hidden 仅 scope == .hidden 场景可见，docs/09 D10）
    enum StatusFilter: String, CaseIterable, Identifiable, Hashable, Codable {
        case favorite
        case unorganized
        case hidden

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .favorite:     return "已收藏"
            case .unorganized:  return "未整理"   // 口径：未收藏（docs/01 §E 简化定义）
            case .hidden:       return "已隐藏"
            }
        }
    }

    /// 日期下钻（年 → 月 → 日；nil = 该级不限）
    var year: Int?
    var month: Int?
    var day: Int?

    /// 媒体多选（空 = 全部）
    var media: Set<MediaFilter> = []

    /// 状态（多选）
    var status: Set<StatusFilter> = []

    /// 位置（any/有/无/附近区域）
    var location: LocationFilter = .any

    /// 至少一个维度被设置才视为有效筛选
    var isActive: Bool {
        year != nil || month != nil || day != nil || !media.isEmpty || !status.isEmpty
            || location != .any
    }

    var isDefault: Bool { !isActive }

    static let `default` = SearchPredicate()
}
