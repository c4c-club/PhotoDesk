// MARK: - 职责说明：单指滑选状态机（docs/22 §5.5 重写）——
// idle → pressing → selecting → autoScrolling → finished；激活不再做方向锁（移动 6pt 且起点在 cell 内）。
// 每次 move/tick 用「窗口坐标」重新换算当前 cell；anchor/current 交给 Core SlideSelectRangePolicy 计算整行区间；
// 目标 = 拖动开始快照 base ∪ range，按集合 diff 只刷新可见 cell；边缘 60pt 自动滚动逐帧重命中。

import UIKit
import PhotoDeskCore

@MainActor
final class SlideSelectGestureController: NSObject {
    private enum State: Equatable {
        case idle
        case pressing
        case selecting
        case autoScrolling
        case finished
    }

    private weak var collectionView: UICollectionView?
    private var state: State = .idle
    private var anchorCell: SlideSelectCell?
    private var lastCurrentCell: SlideSelectCell?
    private var baseIDs: Set<String> = []
    private var lastTargetIDs: Set<String> = []
    private var hasMovedAwayFromAnchor = false
    private var lastFingerWindowPoint: CGPoint = .zero
    private var autoScrollLink: CADisplayLink?
    private let haptic = UISelectionFeedbackGenerator()

    /// VC 注入：是否处于多选模式（非选择模式 delegate 直接让位给滚动）。
    var isSelectionMode: () -> Bool = { false }
    /// VC 注入：拖动开始帧的选中 id 快照。
    var selectedIDsProvider: () -> Set<String> = { [] }
    /// VC 注入：IndexPath → PhotoItem.id（apply 窗口内必须经 dataSource，不能用数组下标）。
    var itemIDProvider: (IndexPath) -> String? = { _ in nil }
    /// VC 注入：把目标选中 id 集合整体落到 selectionState / 可见 cell / 徽标 / 计数。
    var applyTargetIDs: (Set<String>) -> Void = { _ in }
    /// VC 注入：当前列数（2–5）。
    var columnsProvider: () -> Int = { 3 }

    /// 单指滑选 pan（delegate 由 VC 设置）。
    let pan = UIPanGestureRecognizer()

    /// 供 VC delegate / UI 测试观察：拖动选择是否已激活。
    var isDragSelecting: Bool {
        state == .selecting || state == .autoScrolling
    }

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.addTarget(self, action: #selector(handlePan(_:)))
        collectionView.addGestureRecognizer(pan)
        haptic.prepare()
    }

    func attachDelegate(_ delegate: UIGestureRecognizerDelegate) {
        pan.delegate = delegate
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let collectionView else { return }
        switch gesture.state {
        case .began:
            lastFingerWindowPoint = gesture.location(in: nil)
            guard isSelectionMode(),
                  let point = windowToContent(lastFingerWindowPoint),
                  let indexPath = collectionView.indexPathForItem(at: point) else {
                state = .idle
                return
            }
            state = .pressing
            anchorCell = SlideSelectCell(section: indexPath.section, item: indexPath.item)
            lastCurrentCell = anchorCell
            baseIDs = selectedIDsProvider()
            lastTargetIDs = baseIDs
            hasMovedAwayFromAnchor = false
            haptic.prepare()
        case .changed:
            lastFingerWindowPoint = gesture.location(in: nil)
            let translation = gesture.translation(in: collectionView)
            if state == .pressing,
               hypot(Double(translation.x), Double(translation.y)) >= SlideSelectConfig.activationThreshold {
                beginDragSelection()
            }
            guard isDragSelecting else { return }
            processFinger(atWindowPoint: lastFingerWindowPoint)
            updateEdgeAutoScroll()
        case .ended, .cancelled, .failed:
            finishSlideSelection()
        default:
            break
        }
    }

    private func beginDragSelection() {
        guard let collectionView, let anchor = anchorCell else { return }
        state = .selecting
        collectionView.allowsSelection = false
        // 起手 cell 立即进入目标（即使 range 为空）；回拖到起点时由 processFinger 恢复 base。
        if let path = indexPathForCell(anchor), let id = itemIDProvider(path) {
            var target = baseIDs
            target.insert(id)
            lastTargetIDs = target
            applyTargetIDs(target)
            haptic.selectionChanged()
        }
    }

    private func processFinger(atWindowPoint: CGPoint) {
        guard let collectionView,
              let point = windowToContent(atWindowPoint),
              let indexPath = collectionView.indexPathForItem(at: point) else { return }
        let cell = SlideSelectCell(section: indexPath.section, item: indexPath.item)
        if cell == anchorCell, !hasMovedAwayFromAnchor { return }
        if cell != anchorCell { hasMovedAwayFromAnchor = true }
        guard cell != lastCurrentCell else { return }
        lastCurrentCell = cell
        guard let anchor = anchorCell else { return }

        let metrics = SlideGridMetrics(columns: max(1, columnsProvider()),
                                       sectionItemCounts: (0..<collectionView.numberOfSections).map {
                                           collectionView.numberOfItems(inSection: $0)
                                       })
        let range = SlideSelectRangePolicy.cells(anchor: anchor, current: cell, metrics: metrics)
        var target = baseIDs
        for rangeCell in range {
            if let path = indexPathForCell(rangeCell), let id = itemIDProvider(path) {
                target.insert(id)
            }
        }
        guard target != lastTargetIDs else { return }
        let grew = target.count > lastTargetIDs.count
        lastTargetIDs = target
        applyTargetIDs(target)
        if grew { haptic.selectionChanged() }
    }

    private func indexPathForCell(_ cell: SlideSelectCell) -> IndexPath? {
        guard let collectionView,
              cell.section >= 0, cell.section < collectionView.numberOfSections,
              cell.item >= 0, cell.item < collectionView.numberOfItems(inSection: cell.section) else { return nil }
        return IndexPath(item: cell.item, section: cell.section)
    }

    /// 窗口坐标 → collectionView 内容坐标（滚动后仍对应手指下的 cell）。
    private func windowToContent(_ windowPoint: CGPoint) -> CGPoint? {
        guard let collectionView, collectionView.window != nil else { return nil }
        return collectionView.convert(windowPoint, from: nil)
    }

    // MARK: - 边缘自动滚动

    private func updateEdgeAutoScroll() {
        guard isDragSelecting, edgeVelocity() != 0 else {
            invalidateAutoScroll()
            return
        }
        guard autoScrollLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
        state = .autoScrolling
    }

    @objc private func autoScrollTick(_ link: CADisplayLink) {
        guard let collectionView, isDragSelecting else {
            invalidateAutoScroll()
            return
        }
        let velocity = edgeVelocity()
        guard velocity != 0 else {
            invalidateAutoScroll()
            if state == .autoScrolling { state = .selecting }
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
        processFinger(atWindowPoint: lastFingerWindowPoint)
    }

    private func edgeVelocity() -> Double {
        guard let collectionView else { return 0 }
        let point = windowToContent(lastFingerWindowPoint)
        let fingerViewportY = Double((point?.y ?? 0) - collectionView.contentOffset.y)
        let top = Double(collectionView.adjustedContentInset.top)
        let bottom = Double(collectionView.bounds.height - collectionView.adjustedContentInset.bottom)
        return SlideSelectPolicy.edgeVelocity(fingerY: fingerViewportY,
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

    /// 结束/取消/失败统一收尾：恢复点选、清快照/标记/displayLink。
    func finishSlideSelection() {
        invalidateAutoScroll()
        state = .finished
        anchorCell = nil
        lastCurrentCell = nil
        baseIDs = []
        lastTargetIDs = []
        hasMovedAwayFromAnchor = false
        if let collectionView {
            DispatchQueue.main.async { [weak collectionView] in
                collectionView?.allowsSelection = true
            }
        }
        DispatchQueue.main.async { [weak self] in
            if self?.state == .finished { self?.state = .idle }
        }
    }
}
