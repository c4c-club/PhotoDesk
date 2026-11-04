// MARK: - 职责说明：分类菜单装配纯逻辑（docs/16 M12 §3.3 / R06）——
// 5 项「全部/收藏/视频/截图/已隐藏」+ .limited「管理可见照片」；勾选由 viewModel.query.scope 派生
//（删掉漂移的独立 @State scopeOption）；当前项计数 = filteredItems.count，其他项 = 异步 count(scope:)；
// 已隐藏不 setScope（走 VaultView）且解锁前不泄露数量（countText = nil）。
// 筛选按钮完全独立（仍打开 LibraryFilterSheet）——分类菜单绝不并入筛选面板。

import Foundation

struct CategoryMenuItem: Equatable {
    let title: String
    /// nil = 已隐藏 / 管理入口（不走 setScope）
    let scope: PhotoScope?
    /// nil = 不显示计数（已隐藏解锁前不泄露数量）
    let countText: String?
    let isSelected: Bool
    let isLimitedManagement: Bool

    /// 菜单标题（带计数）
    var displayTitle: String {
        guard let countText else { return title }
        return "\(title) · \(countText)"
    }
}

enum LibraryCategoryMenuBuilder {
    /// 菜单顺序：全部 → 收藏 → 视频 → 截图 →（已隐藏）→（管理可见照片）
    static let scopeOrder: [PhotoScope] = [.all, .favorites, .videos, .screenshots]

    static func title(_ scope: PhotoScope) -> String {
        switch scope {
        case .all:         return "全部"
        case .favorites:   return "收藏"
        case .videos:      return "视频"
        case .screenshots: return "截图"
        default:           return "全部"
        }
    }

    static func items(currentScope: PhotoScope,
                      isLimitedAccess: Bool,
                      counts: [PhotoScope: Int],
                      currentCount: Int) -> [CategoryMenuItem] {
        var items: [CategoryMenuItem] = []
        for scope in scopeOrder {
            let selected = (scope == currentScope)
            let count = selected ? currentCount : counts[scope]
            items.append(CategoryMenuItem(title: title(scope),
                                          scope: scope,
                                          countText: count.map(String.init),
                                          isSelected: selected,
                                          isLimitedManagement: false))
        }
        items.append(CategoryMenuItem(title: "已隐藏",
                                      scope: nil,
                                      countText: nil,
                                      isSelected: false,
                                      isLimitedManagement: false))
        if isLimitedAccess {
            items.append(CategoryMenuItem(title: "管理可见照片",
                                          scope: nil,
                                          countText: nil,
                                          isSelected: false,
                                          isLimitedManagement: true))
        }
        return items
    }
}
