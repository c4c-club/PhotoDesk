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

/// 搜索谓词占位：字段随 M5 筛选维度（日期下钻 / 媒体类型 / 状态）定型
struct SearchPredicate: Hashable {
    // TODO(P5): 关键词 / 日期区间 / 媒体类型 / 收藏与隐藏状态
}
