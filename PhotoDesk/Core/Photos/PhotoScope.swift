// MARK: - 职责说明：照片库查询范围（docs/03 §4.1）——网格/浏览页/相簿统一的 scope 抽象。
// .hidden 需 includeHiddenAssets = true（其余 scope 一律 false，主网格不含隐藏——AGENTS.md §4.2）。

import Photos

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

/// 多维筛选谓词（docs/05 M5 任务 5.1/5.2）——日期三级下钻 + 媒体类型多选 + 状态。
/// 匹配引擎见 PhotoFilter（纯函数可单测）；OCR 关键词索引未接入，登记于已知问题（后续 OCR 文本索引）。
struct SearchPredicate: Hashable {
    /// 媒体类型维度（照片/视频/Live/截图/人像/全景/慢动作/延时）。
    /// RAW 无公开 subtype（需逐资源枚举 PHAssetResource，万级库不可承受），暂未支持，登记于已知问题
    enum MediaFilter: String, CaseIterable, Identifiable, Hashable {
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

    /// 状态维度
    enum StatusFilter: String, CaseIterable, Identifiable, Hashable {
        case favorite
        case unorganized

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .favorite:     return "已收藏"
            case .unorganized:  return "未整理"   // 口径：未收藏（docs/01 §E 简化定义）
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

    /// 至少一个维度被设置才视为有效筛选
    var isActive: Bool {
        year != nil || month != nil || day != nil || !media.isEmpty || !status.isEmpty
    }

    var isDefault: Bool { !isActive }

    static let `default` = SearchPredicate()
}
