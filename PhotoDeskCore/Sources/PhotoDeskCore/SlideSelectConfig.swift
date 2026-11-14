// MARK: - 职责说明：边缘自动滚动常量（M17 T05 起由 LibrarySelectionController 引用），
// 禁止 ViewController 散落魔法数字。长按/方向锁/激活阈值全部在 SelectionGestureConfig
//（M17 T02；旧 activationThreshold 随 SlideSelectGestureController 于 T05 一并退役）。

import Foundation

public enum SlideSelectConfig {
    /// 边缘自动滚动缓冲区（顶部/底部各 60pt）
    public static let edgeBuffer: Double = 60
    /// 每帧滚动步长 2–12pt（docs/22 §5.5）
    public static let minStep: Double = 2
    public static let maxStep: Double = 12
}