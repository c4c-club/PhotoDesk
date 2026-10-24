// MARK: - 职责说明：全屏浏览 UIKit 分页器（docs/05 M2 任务 2.1）★核心——
// UICollectionView + Compositional Layout paging，cell = ZoomableImageCell / VideoCell；
// UIPanGestureRecognizer 上下滑经 SwipeGestureEngine 调 PhotoDeskCore.SwipeResolver 判定，
// 方向锁：垂直时 pager.isScrollEnabled = false，放大（zoomScale > 1.01）时上下滑禁用（AGENTS.md §7）。
// 红线提醒：任何删除只允许 PHAssetChangeRequest.deleteAssets（移到最近删除），UI 文案不得出现「彻底删除」。
// TODO(P2): 手势挂载 + 方向锁 + ActionOverlayView + 执行管线 + Toast 撤销 + 底部胶片条。
