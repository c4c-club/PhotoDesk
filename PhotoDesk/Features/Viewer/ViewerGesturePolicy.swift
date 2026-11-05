// MARK: - 职责说明：查看器手势互斥纯策略（docs/16 M12 R02/B1）——
// 决策语义集中此处（单元测试 ViewerGestureGuardTests 锁定），VC 只做接线：
// ① pan 开始判定（无障碍开关 / 双指 / cell 缩放中 / 回弹宽限窗口）；
// ② 删除/隐藏事务与缩放事务互斥（pinchActive 期间 performStaged / executeAction guard 早退）。
// 旧版根因：maximumNumberOfTouches=1 使「双指」分支成死代码；isZoomed 只在 shouldBegin 起始判一次
//（此刻 zoomScale==1 必放行）；shouldRecognizeSimultaneouslyWith 无条件 true → 捏合中的单指位移
// 触发垂直锁 → performBatchUpdates 在 UIScrollView 缩放事务中执行 → CALayer NaN 崩溃。

import UIKit

enum ViewerGesturePolicy {
    /// 当前 cell 的缩放状态快照（VC 从 ZoomableImageCell 采集；nil = 无可见 cell）
    struct CellState {
        let isZooming: Bool
        let zoomScale: CGFloat
        let secondsSinceZoomActivity: TimeInterval
    }

    /// 缩放事务是否活跃：捏合进行中、zoomScale > 1.01、或回弹宽限窗口内
    static func isZoomTransactionActive(_ cell: CellState?) -> Bool {
        guard let cell else { return false }
        if cell.isZooming { return true }
        if cell.zoomScale > 1.01 { return true }
        return cell.secondsSinceZoomActivity < DSMotion.zoomActivityGrace
    }

    /// pan 是否允许开始
    static func shouldPanBegin(gesturesEnabled: Bool, numberOfTouches: Int, cell: CellState?) -> Bool {
        guard gesturesEnabled else { return false }        // 无障碍手势总开关
        guard numberOfTouches <= 1 else { return false }   // 双指 → 捏合（旧版死代码修复）
        return !isZoomTransactionActive(cell)
    }

    /// 删除/隐藏事务是否允许执行（缩放事务与删除事务互斥——B1 核心不变量）
    static func allowsRemovalTransaction(cell: CellState?) -> Bool {
        !isZoomTransactionActive(cell)
    }
}
