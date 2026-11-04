// MARK: - 职责说明：查看器手势互斥纯策略（docs/16 M12 R02/B1）——
// M12 先红批次脚手架：接线未完成，恒按基线行为放行（pan 仅受无障碍开关约束；删除事务恒允许）。
// 断言红由 ViewerGestureGuardTests 锁定；实现提交替换本文件语义（缩放事务/回弹宽限/双指互斥）。

import UIKit

enum ViewerGesturePolicy {
    /// 当前 cell 的缩放状态快照（VC 从 ZoomableImageCell 采集；nil = 无可见 cell）
    struct CellState {
        let isZooming: Bool
        let zoomScale: CGFloat
        let secondsSinceZoomActivity: TimeInterval
    }

    /// pan 是否允许开始（脚手架：基线行为——只看无障碍总开关）
    static func shouldPanBegin(gesturesEnabled: Bool, numberOfTouches: Int, cell: CellState?) -> Bool {
        gesturesEnabled
    }

    /// 删除/隐藏事务是否允许执行（脚手架：基线行为——恒允许）
    static func allowsRemovalTransaction(cell: CellState?) -> Bool {
        true
    }
}
