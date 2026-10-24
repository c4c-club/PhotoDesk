// MARK: - 职责说明：设计系统间距 / 圆角 / 阴影 token（docs/04 §3、§5.4）——
// 魔法数字唯一出处（AGENTS.md §5：禁止散落），SwipeConfig 手势阈值见 PhotoDeskCore.GestureConfig。

import CoreGraphics

enum DSSpacing {
    // 网格（docs/04 §3.1：间距 2pt、缩略图圆角 4pt）
    static let gridSpacing: CGFloat = 2
    static let gridCornerRadius: CGFloat = 4

    // 卡片与按钮（docs/04 §5.4：卡片 14pt、按钮 12pt、阴影 0/2/8 rgba(0,0,0,0.06)）
    static let cardCornerRadius: CGFloat = 14
    static let buttonCornerRadius: CGFloat = 12
    static let cardShadowOpacity: Float = 0.06
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowOffset = CGSize(width: 0, height: 2)

    // 动作浮层（docs/04 §3.2：96×96 圆形 + 36pt 图标）
    static let actionOverlaySize: CGFloat = 96
    static let actionOverlayIconSize: CGFloat = 36

    // 通用留白与 Toast（docs/04 §3.2：距底部 16pt）
    static let screenPadding: CGFloat = 16
    static let toastBottomOffset: CGFloat = 16
}
