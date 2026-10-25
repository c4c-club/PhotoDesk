// MARK: - 职责说明：领域值类型 PhotoItem（docs/03 §4.1）——跨层传递的照片快照，线程安全值类型。
// Feature 层不得直接引用 PHAsset（AGENTS.md §3.1），统一用本类型；由 AssetRepository 从 PHAsset 映射。
// 注意：含 CLLocation（Apple 类型）故不能下沉 PhotoDeskCore（红线 2），纯逻辑一律经参数传入核心包。

import Photos
import CoreLocation

/// 媒体类型
enum MediaType: Hashable {
    case image
    case video
    case unknown
}

/// 媒体子类型（docs/03 §4.1：截图 / Live / HDR / 慢动作 / 延时）
struct MediaSubtypes: OptionSet, Hashable {
    let rawValue: UInt
    static let photoScreenshot  = MediaSubtypes(rawValue: 1 << 0)
    static let photoLive        = MediaSubtypes(rawValue: 1 << 1)
    static let photoHDR         = MediaSubtypes(rawValue: 1 << 2)
    static let videoSlowMo      = MediaSubtypes(rawValue: 1 << 3)
    static let videoTimelapse   = MediaSubtypes(rawValue: 1 << 4)
    /// 人像（深度虚化）
    static let photoDepthEffect = MediaSubtypes(rawValue: 1 << 5)
    /// 全景
    static let photoPanorama    = MediaSubtypes(rawValue: 1 << 6)
}

struct PhotoItem: Identifiable, Hashable {
    let id: String                      // PHAsset.localIdentifier
    let mediaType: MediaType
    let mediaSubtypes: MediaSubtypes
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let isFavorite: Bool
    let isHidden: Bool
    let location: CLLocation?
    let burstIdentifier: String?
    /// iCloud-only：原件未在本机（网格显示占位，删除前必须已下载——docs/03 §5.8）
    let isCloudOnly: Bool
}
