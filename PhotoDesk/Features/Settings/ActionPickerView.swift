// MARK: - 职责说明：动作选择器（docs/04 §3.4）——全屏列表：图标 + 名称 + 说明 + 当前选中打勾；
// 选中即写回 @AppStorage（gesture.up / gesture.down），返回手势设置页立即生效。

import SwiftUI
import PhotoDeskCore

struct ActionPickerView: View {
    enum Direction {
        case up
        case down

        var title: String { self == .up ? "上滑动作" : "下滑动作" }
        var key: String { self == .up ? "gesture.up" : "gesture.down" }
    }

    let direction: Direction
    @AppStorage private var stored: String
    @Environment(\.dismiss) private var dismiss

    init(direction: Direction) {
        self.direction = direction
        _stored = AppStorage(wrappedValue: SwipeAction.favorite.rawValue, direction.key)
    }

    private let selectable: [SwipeAction] = [.favorite, .unfavorite, .toggleFavorite,
                                             .hide, .unhide, .moveToRecentlyDeleted,
                                             .addToAlbum, .share, .showInfo,
                                             .rotate, .dismiss, .none]

    var body: some View {
        List(selectable, id: \.rawValue) { action in
            Button {
                stored = action.rawValue
                UIImpactFeedbackGenerator(style: .light).impactOccurred()   // 选中触觉（docs/04 §3.4）
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: ActionOverlayView.symbol(for: action))
                        .foregroundColor(Color(uiColor: ActionOverlayView.color(for: action)))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.displayName)
                            .foregroundColor(Color(ds: DSColor.textPrimary))
                        Text(description(for: action))
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                    Spacer()
                    if action.rawValue == stored {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color(ds: DSColor.tint))
                    }
                }
            }
            .accessibilityLabel("\(action.displayName)，\(description(for: action))\(action.rawValue == stored ? "，当前已选" : "")")
        }
        .listStyle(.insetGrouped)
        .navigationTitle(direction.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func description(for action: SwipeAction) -> String {
        switch action {
        case .favorite:              return "标记为收藏"
        case .unfavorite:            return "取消收藏标记"
        case .toggleFavorite:        return "在收藏与取消之间切换"
        case .hide:                  return "移入「已隐藏」，不再出现在照片库"
        case .unhide:                return "恢复显示"
        case .moveToRecentlyDeleted: return "移入系统「最近删除」，保留 30 天"
        case .addToAlbum:            return "加入指定相簿"
        case .share:                 return "调出系统分享面板"
        case .showInfo:              return "查看照片信息"
        case .rotate:                return "旋转 90 度"
        case .dismiss:               return "退出全屏浏览"
        case .none:                  return "该方向不触发动作"
        }
    }
}
