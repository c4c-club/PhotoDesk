// MARK: - 职责说明：设置存取（docs/03 §4.3 @AppStorage 全表）——键名与文档完全一致。
// 纯 UserDefaults 包装（主线程使用）；M7 设置页全量接线，M1/M2 先用 gridColumns 与手势组。

import SwiftUI

/// 上滑/下滑可绑定的动作（docs/03 §4.3）
enum SwipeAction: String, CaseIterable, Codable {
    case favorite, unfavorite, toggleFavorite
    case hide, unhide, delete
    case addToAlbum, share, showInfo, rotate, dismiss, none

    /// 展示名（docs/04 §7 文案口径：删除一律「移到最近删除」）
    var displayName: String {
        switch self {
        case .favorite:        return "收藏"
        case .unfavorite:      return "取消收藏"
        case .toggleFavorite:  return "切换收藏"
        case .hide:            return "隐藏"
        case .unhide:          return "取消隐藏"
        case .delete:          return "移到最近删除"
        case .addToAlbum:      return "加入相簿"
        case .share:           return "分享"
        case .showInfo:        return "查看信息"
        case .rotate:          return "旋转"
        case .dismiss:         return "退出浏览"
        case .none:            return "无"
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
