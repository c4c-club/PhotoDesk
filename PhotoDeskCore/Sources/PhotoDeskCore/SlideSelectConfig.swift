// MARK: - 职责说明：轨迹滑选命中与边缘自动滚动常量（M18 T03 扩充；禁止 ViewController 散落魔法数字）。
// 长按/方向锁/激活阈值全部在 SelectionGestureConfig（M17 T02）。

import Foundation

public enum SlideSelectConfig {
    /// 边缘自动滚动缓冲区（顶部/底部各 60pt）
    public static let edgeBuffer: Double = 60
    /// 每帧滚动步长 2–12pt（docs/22 §5.5）
    public static let minStep: Double = 2
    public static let maxStep: Double = 12
    /// 线段命中单边扩展（pt）：贴边/亚 pt 采样误差补扫，对齐旧 HitRect 的 1pt 扩展语义（M18 T03）
    public static let hitExpansion: Double = 1
    /// 线段退化分支阈值（pt）：|dx|/|dy| ≤ epsilon 视为垂直/水平分量（近垂直拖动按列命中）（M18 T03）
    public static let segmentEpsilon: Double = 0.5
    /// 行带段间空隙吸附容差（pt）：指尖落段间隙时距某行带边缘 ≤ 容差吸附该行带，超出 → nil（M19 T02）
    public static let rowBandSnapTolerance: Double = 12
    /// 单帧行带展开上限（0 = 不限）：自动滚动位移已由 minStep/maxStep 钳制，T07 实测异常才启用（M19 docs/42 §10.2）
    public static let rowBandMaxExpandPerFrame: Int = 0
}
