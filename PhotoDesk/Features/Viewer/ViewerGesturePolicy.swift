// MARK: - 职责说明：查看器手势互斥纯策略（docs/16 M12 R02/B1；docs/19 M13 P1 扩展）——
// 决策语义集中此处（单元测试 ViewerGestureGuardTests 锁定），VC 只做接线：
// ① pan 开始判定（无障碍开关 / 双指 / cell 缩放中 / 回弹宽限窗口 / 几何事务态）；
// ② 删除/隐藏事务与缩放事务互斥：active/settling 期间 VC 把动作排入 pendingRemovalActions，
//    idle 后串行 drain，绝不在 pinch 中 performBatchUpdates；
// ③ ZoomTransactionState 是 cell 几何写入与 VC 删除事务共享的唯一状态真值。
// 旧版根因：maximumNumberOfTouches=1 使「双指」分支成死代码；isZoomed 只在 shouldBegin 起始判一次
//（此刻 zoomScale==1 必放行）；shouldRecognizeSimultaneouslyWith 无条件 true → 捏合中的单指位移
// 触发垂直锁 → performBatchUpdates 在 UIScrollView 缩放事务中执行 → CALayer NaN 崩溃。
// M12 仅有 isFinite 护栏仍复现：旧滚动缩放方案在活跃期仍从 configure / layoutSubviews /
// 缩放回调多路写回几何，且 allowsRemovalTransaction 只在入口 guard 无排队语义。

import UIKit

/// M13 P1：缩放事务状态机。cell 在 active 冻结几何写入；settling 一次批量提交；idle 才允许删除事务。
enum ZoomTransactionState: String, Equatable, Sendable {
    case idle
    case active
    case settling
}

enum ViewerGesturePolicy {
    /// 当前 cell 的缩放状态快照（VC 从 ZoomableImageCell 采集；nil = 无可见 cell）
    struct CellState {
        let isZooming: Bool
        let zoomScale: CGFloat
        let secondsSinceZoomActivity: TimeInterval
        let geometryState: ZoomTransactionState
    }

    /// 缩放事务是否活跃：几何事务未回 idle、捏合进行中、zoomScale > 1.01、或回弹宽限窗口内。
    /// geometryState 优先，保证「settling 批量提交中」也不会与 performBatchUpdates 同帧。
    static func isZoomTransactionActive(_ cell: CellState?) -> Bool {
        guard let cell else { return false }
        if cell.geometryState != .idle { return true }
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

    /// 删除/隐藏事务是否允许立即执行（缩放事务与删除事务互斥——B1 核心不变量）。
    /// false 时 VC 必须把动作排入 pendingRemovalActions，待 idle 串行执行，不得直接丢弃或同帧执行。
    static func allowsRemovalTransaction(cell: CellState?) -> Bool {
        !isZoomTransactionActive(cell)
    }

    /// M13 P1：排队动作的 drain 门禁——几何事务已回 idle 且未在捏合中即可串行执行。
    /// 与 allowsRemovalTransaction 的区别：即时删除要求 zoomScale≈1 且越过回弹宽限；
    /// 队列 drain 只需几何批量提交完成（geometryState==idle）且无 isZooming，
    /// 避免放大静止态 / 宽限窗口把队列永久挂起，同时保证不与 cell 几何提交同帧 batchUpdates。
    static func allowsQueuedRemovalDrain(cell: CellState?) -> Bool {
        guard let cell else { return true }
        guard cell.zoomScale.isFinite else { return false }
        return cell.geometryState == .idle && !cell.isZooming
    }

    /// 活跃期收到的删除动作必须排队；VC 用此判定决定 queue 还是立即执行。
    static func shouldQueueRemoval(cell: CellState?) -> Bool {
        !allowsRemovalTransaction(cell: cell)
    }
}
