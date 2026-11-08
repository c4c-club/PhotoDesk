// MARK: - 职责说明：单指滑选的全部常量集中在 Core，禁止 ViewController 散落魔法数字。

import Foundation

public enum SlideSelectConfig {
    /// 边缘自动滚动缓冲区（顶部/底部各 60pt）
    public static let edgeBuffer: Double = 60
    /// 每帧滚动步长 2–12pt（docs/22 §5.5）
    public static let minStep: Double = 2
    public static let maxStep: Double = 12
    /// 激活阈值：移动 6pt 且起点在 cell 内即进入选择（不再做方向锁）
    public static let activationThreshold: Double = 6
    public static let directionLockEpsilon: Double = 0
}
