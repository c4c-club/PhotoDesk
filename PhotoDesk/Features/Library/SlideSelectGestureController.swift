// MARK: - 职责说明：M13 P3 单指滑选手势编排（docs/19 §3.3 / docs/20 用户 6 条硬约束）——
// ① maximumNumberOfTouches=1 / cancelsTouchesInView=false / delegate 两方法（由 LibraryViewController 实现）；
// ② .began 只记起点；.changed 用 SlideSelectPolicy.shouldActivate 方向锁，垂直占优锁死本手势余生；
// ③ 激活帧拍 [IndexPath: Bool] 快照，经过 cell 时经 SlideSelectPolicy.resolvedSelection 恢复/置 true（反向滑回恢复）；
// ④ indexPathForItem(at:) + lastProcessedIndexPath 去重；
// ⑤ isScrollEnabled 协同 + finish 恢复滚动/清快照/清标记；
// ⑥ 60pt 边缘 CADisplayLink 按距离算速度，逐帧 setContentOffset 后重算命中屏幕外 cell，离开/结束销毁。
// 本类只做 UIKit↔Core 映射；所有判定来自 PhotoDeskCore.SlideSelectPolicy / SlideSelectConfig，不重写规则。

import UIKit
import PhotoDeskCore

@MainActor
final class SlideSelectGestureController: NSObject {
    /// ⑤ 选择期是否冻结了 CollectionView 滚动（供 VC delegate / 测试观察）。
    private(set) var isDragSelecting = false
    /// ② 手势起点（collectionView 坐标）+ 垂直锁（余生不再激活选择）。
    private var dragStartPoint: CGPoint = .zero
    private var verticalScrollLocked = false
    /// ③ 滑动开始帧的原始选中快照（只保存「开始时已选中」，字典值恒 true）。
    private var originallySelected: [IndexPath: Bool] = [:]
    /// ③ Core 版原始选中集合（供 resolvedSelection 纯函数使用）。
    private var originallySelectedCore: Set<SlideSelectCell> = []
    /// ③ 去重后的访问序列（a→b→a 的回滑路径必须保留）。
    private var visitedCore: [SlideSelectCell] = []
    /// ④ 上次实际处理的 indexPath，去重防同一 cell 闪烁。
    private var lastProcessedIndexPath: IndexPath?
    /// ⑥ 边缘自动滚动。
    private var autoScrollLink: CADisplayLink?
    private var lastFingerLocation: CGPoint = .zero

    private weak var collectionView: UICollectionView?

    /// VC 注入：是否处于多选模式（非选择模式手势 delegate 直接让位给滚动）。
    var isSelectionMode: () -> Bool = { false }
    /// VC 注入：激活帧已选中的 indexPath 集合（来自 selectionState，经 dataSource 映射）。
    var initiallySelectedIndexPaths: () -> [IndexPath] = { [] }
    /// VC 注入：把 indexPath 的目标选中态落到 selectionState / collectionView / 徽标 / 计数。
    var applyTarget: (IndexPath, Bool) -> Void = { _, _ in }

    /// ① 单指滑选 pan（delegate 由 VC 设置）。
    let pan = UIPanGestureRecognizer()

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.addTarget(self, action: #selector(handlePan(_:)))
        collectionView.addGestureRecognizer(pan)
    }

    func attachDelegate(_ delegate: UIGestureRecognizerDelegate) {
        pan.delegate = delegate
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let collectionView else { return }
        switch gesture.state {
        case .began:
            // ② .began 只记起点并清空标记；严禁此刻激活 isDragSelecting。
            dragStartPoint = gesture.location(in: collectionView)
            lastFingerLocation = dragStartPoint
            verticalScrollLocked = false
            isDragSelecting = false
            originallySelected.removeAll()
            originallySelectedCore.removeAll()
            visitedCore.removeAll()
            lastProcessedIndexPath = nil
        case .changed:
            let location = gesture.location(in: collectionView)
            lastFingerLocation = location
            if !isDragSelecting {
                let translation = gesture.translation(in: collectionView)
                switch SlideSelectPolicy.shouldActivate(dx: Double(translation.x),
                                                        dy: Double(translation.y),
                                                        wasLocked: verticalScrollLocked) {
                case .horizontal:
                    beginDragSelection()
                case .verticalLocked:
                    verticalScrollLocked = true   // 本手势余生不再激活，纵向滚动完全让位
                    return
                case .none:
                    return
                }
            }
            processFinger(at: location)
            updateEdgeAutoScroll()
        case .ended, .cancelled, .failed:
            finishSlideSelection()
        default:
            break
        }
    }

    private func beginDragSelection() {
        guard let collectionView, isSelectionMode() else { return }
        isDragSelecting = true
        collectionView.isScrollEnabled = false                     // ⑤
        let initial = initiallySelectedIndexPaths()
        originallySelected = Dictionary(initial.map { ($0, true) }, uniquingKeysWith: { first, _ in first })
        originallySelectedCore = Set(initial.map { SlideSelectCell(section: $0.section, item: $0.item) })
        visitedCore = []
        lastProcessedIndexPath = nil
        processFinger(at: dragStartPoint)                           // 起点 cell 立即处理
    }

    /// ④ 同 cell 去重；③ 经 Core 纯函数按访问次数奇偶得到目标态，再映射回 VC。
    private func processFinger(at location: CGPoint) {
        guard let collectionView, let ip = collectionView.indexPathForItem(at: location) else { return }
        guard ip != lastProcessedIndexPath else { return }
        lastProcessedIndexPath = ip
        let cell = SlideSelectCell(section: ip.section, item: ip.item)
        visitedCore.append(cell)
        let resolved = SlideSelectPolicy.resolvedSelection(originallySelected: originallySelectedCore,
                                                           visited: visitedCore)
        let target = resolved[cell] ?? (originallySelected[ip] ?? true)
        applyTarget(ip, target)
    }

    // MARK: ⑥ 边缘自动滚动

    private func updateEdgeAutoScroll() {
        guard isDragSelecting, edgeVelocity() != 0 else {
            invalidateAutoScroll()
            return
        }
        guard autoScrollLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    @objc private func autoScrollTick(_ link: CADisplayLink) {
        guard let collectionView, isDragSelecting else {
            invalidateAutoScroll()
            return
        }
        let velocity = edgeVelocity()
        guard velocity != 0 else {
            invalidateAutoScroll()
            return
        }
        let minY = -Double(collectionView.adjustedContentInset.top)
        let maxY = max(minY,
                       Double(collectionView.contentSize.height
                              + collectionView.adjustedContentInset.bottom
                              - collectionView.bounds.height))
        let target = SlideSelectPolicy.clampedOffset(current: Double(collectionView.contentOffset.y),
                                                     delta: velocity,
                                                     min: minY,
                                                     max: maxY)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: CGFloat(target)),
                                        animated: false)
        processFinger(at: lastFingerLocation)     // 滚动后用同一手指坐标重算命中（屏幕外 cell）
    }

    private func edgeVelocity() -> Double {
        guard let collectionView else { return 0 }
        let top = Double(collectionView.bounds.minY + collectionView.adjustedContentInset.top)
        let bottom = Double(collectionView.bounds.maxY - collectionView.adjustedContentInset.bottom)
        return SlideSelectPolicy.edgeVelocity(fingerY: Double(lastFingerLocation.y),
                                              top: top,
                                              bottom: bottom,
                                              buffer: SlideSelectConfig.edgeBuffer,
                                              minStep: SlideSelectConfig.minStep,
                                              maxStep: SlideSelectConfig.maxStep)
    }

    private func invalidateAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
    }

    /// ⑤ 结束/取消/失败统一收尾：恢复滚动、清快照/标记/displayLink。
    func finishSlideSelection() {
        collectionView?.isScrollEnabled = true
        isDragSelecting = false
        verticalScrollLocked = false
        originallySelected.removeAll()
        originallySelectedCore.removeAll()
        visitedCore.removeAll()
        lastProcessedIndexPath = nil
        invalidateAutoScroll()
    }
}
