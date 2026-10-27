// MARK: - 职责说明：全局动效 token（docs/04 §6 动效规范）——
// 转场/飞出 0.35s spring；Toast/淡入淡出 0.25s easeOut。禁止在调用点散落魔法数字。
// 全部动效尊重「减弱动态效果」（usesMotion 由各调用点自行判断）。

import UIKit

enum DSMotion {
    /// Toast 出入场（easeOut）
    static let toastDuration: TimeInterval = 0.25
    /// 工具栏/图层淡入淡出（easeOut）
    static let fadeDuration: TimeInterval = 0.25
    /// 上下滑手势飞出（spring）
    static let flyOutDuration: TimeInterval = 0.35
    /// spring 阻尼（0.85：轻微过冲，不弹跳）
    static let springDamping: CGFloat = 0.85
    /// spring 初速度
    static let springVelocity: CGFloat = 0.3
    /// 双击缩放回弹（spring，较短）
    static let zoomDuration: TimeInterval = 0.25

    /// 统一 easeOut 参数（Toast/淡入淡出共用）
    static var fadeOptions: UIView.AnimationOptions { [.curveEaseOut, .beginFromCurrentState] }
}
