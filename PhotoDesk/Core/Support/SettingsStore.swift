// MARK: - 职责说明：设置存取（docs/03 §4.3 @AppStorage 全表）——键名与文档完全一致。
// 纯 UserDefaults 包装（主线程使用）；M7 设置页全量接线，M1/M2 先用 gridColumns 与手势组。

import SwiftUI
import PhotoDeskCore

/// 上滑/下滑可绑定的动作（docs/03 §4.3）
enum SwipeAction: String, CaseIterable, Codable {
    case favorite, unfavorite, toggleFavorite
    case hide, unhide, moveToRecentlyDeleted
    case addToAlbum, share, showInfo, rotate, dismiss, none

    /// 展示名（docs/04 §7 文案口径：删除一律「移到最近删除」，禁用「彻底删除」）
    var displayName: String {
        switch self {
        case .favorite:               return "收藏"
        case .unfavorite:             return "取消收藏"
        case .toggleFavorite:         return "切换收藏"
        case .hide:                   return "隐藏"
        case .unhide:                 return "取消隐藏"
        case .moveToRecentlyDeleted:  return "移到最近删除"
        case .addToAlbum:             return "加入相簿"
        case .share:                  return "分享"
        case .showInfo:               return "查看信息"
        case .rotate:                 return "旋转"
        case .dismiss:                return "退出浏览"
        case .none:                   return "无"
        }
    }

    /// Toast 文案（docs/04 §7：「已收藏 · 撤销」「已隐藏 · 撤销」「已移到最近删除 · 撤销」）
    var toastText: String {
        switch self {
        case .favorite:              return "已收藏"
        case .unfavorite:            return "已取消收藏"
        case .toggleFavorite:        return "已切换收藏"
        case .hide:                  return "已隐藏"
        case .unhide:                return "已取消隐藏"
        case .moveToRecentlyDeleted: return "已移到最近删除"
        case .addToAlbum:            return "已加入相簿"
        case .share:                 return "已分享"
        case .showInfo:              return "信息"
        case .rotate:                return "已旋转"
        case .dismiss:               return "已退出"
        case .none:                  return ""
        }
    }

    /// 浮层「松手…」文案（docs/04 §3.2）
    var overlayPrompt: String {
        "松手" + displayName
    }

    /// 破坏性动作：需要二次确认（设置 gesture.confirmDestructive 开启时）
    var isDestructive: Bool {
        switch self {
        case .hide, .moveToRecentlyDeleted: return true
        default: return false
        }
    }
}

/// 外观模式
enum Appearance: String, CaseIterable {
    case system, light, dark
}

final class SettingsStore: ObservableObject {
    // MARK: 手势（docs/04 §3.4 手势设置 ★）
    @AppStorage("gesture.up")              var swipeUpAction: SwipeAction = .favorite
    @AppStorage("gesture.down")            var swipeDownAction: SwipeAction = .hide
    @AppStorage("gesture.sensitivity")     var sensitivityRaw: String = Sensitivity.standard.rawValue
    @AppStorage("gesture.haptics")         var hapticsEnabled = true
    @AppStorage("gesture.confirmDestructive") var confirmDestructive = true
    @AppStorage("gesture.undoWindow")      var undoWindow: Double = 5.0
    @AppStorage("gesture.autoAdvance")     var autoAdvance = true
    @AppStorage("gesture.reduceMotionRespected") var respectReduceMotion = true

    // MARK: 网格 / 排序 / 外观
    @AppStorage("grid.columns")            var gridColumns = 3
    @AppStorage("grid.sortAsc")            var sortAscending = false
    @AppStorage("appearance")              var appearanceRaw: String = Appearance.system.rawValue

    // MARK: iCloud / 隐私 / 缓存
    @AppStorage("icloud.autoDownload")     var autoDownloadOriginal = false
    @AppStorage("vault.lockEnabled")       var vaultLockEnabled = true
    @AppStorage("trash.safetyCopyEnabled") var safetyCopyEnabled = true
    @AppStorage("trash.limitMB")           var trashLimitMB = 2048

    // MARK: 清理阈值（docs/04 §3.3：阈值可调；M7 设置页接线）
    /// 去重汉明距离阈值（≤4 高置信 / ≤8 疑似；默认 8）
    @AppStorage("dedup.hammingDistance")   var dedupHammingDistance = 8
    /// 模糊方差阈值（默认 60，低于判模糊）
    @AppStorage("blur.varianceThreshold")  var blurVarianceThreshold = 60.0

    // MARK: 便捷读取（PhotoDeskCore 类型经这里适配，红线 2：App 侧做类型转换）
    var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: sensitivityRaw) ?? .standard }
        set { sensitivityRaw = newValue.rawValue }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }
}
