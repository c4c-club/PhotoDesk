// MARK: - 职责说明：单指滑选 App 侧（SlideSelectGestureController）仍引用的常量集中在 Core，
// 禁止 ViewController 散落魔法数字。长按/方向锁阈值已迁往 SelectionGestureConfig（M17 T02）；
// 本文件的 activationThreshold 等待 T05 接线切换后一并退役。

import Foundation

public enum SlideSelectConfig {
    /// 边缘自动滚动缓冲区（顶部/底部各 60pt）
    public static let edgeBuffer: Double = 60
    /// 每帧滚动步长 2–12pt（docs/22 §5.5）
    public static let minStep: Double = 2
    public static let maxStep: Double = 12
    /// 激活阈值：移动 6pt 且起点在 cell 内即进入选择（T05 接线后由 SelectionGestureConfig.activationDistance 接管）
    public static let activationThreshold: Double = 6
}
