// MARK: - 职责说明：单指矩形框选手势控制器（docs/25 §6.3 / M15 P0-3/4 重写）——
// idle → pressing → selecting → autoScrolling → finished；移动 ≥3pt 激活。
// began 记录 startPoint（content 坐标，激活后不再变）、anchorID、baseIDs、
// mode = baseIDs.contains(anchorID) ? .deselect : .select。
// 每帧：MarqueeRect(startPoint, currentContentPoint) → MarqueeSelectionPolicy.cells(in:)
// → itemIDProvider 映射 → resolved(base:hitIDs:mode:scope) → 集合变化才 apply/haptic。
// 回拖自然收缩；无 lastCurrentCell/visited/parity/insert-only；边缘 60pt 自动滚动逐帧重算；
// cancelsTouchesInView=false，轻点仍走 didSelectItemAt。

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
    private var anchorID: String?
    private var startPoint: CGPoint = .zero
    private var baseIDs: Set<String> = []
    private var mode: MarqueeMode = .select
    private var lastTargetIDs: Set<String> = []
    private var lastFingerWindowPoint: CGPoint = .zero
    private var autoScrollLink: CADisplayLink?
    private let haptic = UISelectionFeedbackGenerator()

    /// VC 注入：是否处于多选模式（非选择模式 delegate 直接让位给滚动）。
    var isSelectionMode: () -> Bool = { false }
    /// VC 注入：拖动开始帧的选中 id 快照。
    var selectedIDsProvider: () -> Set<String> = { [] }
    /// VC 注入：当前选择 scope（月份 scope 等子集下过滤矩形命中；nil = 不过滤）。
    var scopeProvider: () -> Set<String>? = { nil }
    /// VC 注入：IndexPath → PhotoItem.id（apply 窗口内必须经 dataSource，不能用数组下标）。
    var itemIDProvider: (IndexPath) -> String? = { _ in nil }
    /// VC 注入：把目标选中 id 集合整体落到 selectionState / 可见 cell / 徽标 / 计数。
    var applyTargetIDs: (Set<String>) -> Void = { _ in }
    /// VC 注入：当前网格几何（列数/单元尺寸/间距/头高/每 section 数量 + section originY）。
    var geometryProvider: () -> (metrics: GridMetrics, sectionOriginY: [Double])? = { nil }

    /// 单指框选 pan（delegate 由 VC 设置）。
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
        switch gesture.state {
        case .began:
            lastFingerWindowPoint = gesture.location(in: nil)
            guard isSelectionMode(),
                  let collectionView,
                  let startPoint = windowToContent(lastFingerWindowPoint),
                  let indexPath = collectionView.indexPathForItem(at: startPoint),
                  let id = itemIDProvider(indexPath) else {
                state = .idle
                return
            }
            state = .pressing
            self.startPoint = startPoint
            anchorID = id
            baseIDs = selectedIDsProvider()
            mode = MarqueeSelectionPolicy.mode(baseIDs: baseIDs, anchorID: id)
            lastTargetIDs = baseIDs
            haptic.prepare()
        case .changed:
            lastFingerWindowPoint = gesture.location(in: nil)
            if state == .pressing {
                let translation = gesture.translation(in: collectionView)
                if hypot(Double(translation.x), Double(translation.y)) >= SlideSelectConfig.activationThreshold {
                    beginDragSelection()
                }
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
        guard let collectionView else { return }
        state = .selecting
        collectionView.allowsSelection = false
        // 激活帧即按矩形语义落一次目标（零尺寸矩形扩展 1pt 命中起手 cell）
        processFinger(atWindowPoint: lastFingerWindowPoint)
    }

    /// 每帧：矩形 → 命中 cell → 目标集合；只有集合变化才刷新/haptic。
    private func processFinger(atWindowPoint: CGPoint) {
        guard let collectionView,
              let current = windowToContent(atWindowPoint),
              let geometry = geometryProvider() else { return }
        let rect = MarqueeRect(startX: Double(startPoint.x), startY: Double(startPoint.y),
                               currentX: Double(current.x), currentY: Double(current.y))
        let hitCells = MarqueeSelectionPolicy.cells(in: rect,
                                                    metrics: geometry.metrics,
                                                    sectionOriginY: geometry.sectionOriginY)
        var hitIDs = Set<String>()
        for cell in hitCells {
            let path = IndexPath(item: cell.item, section: cell.section)
            if let id = itemIDProvider(path) {
                hitIDs.insert(id)
            }
        }
        let target = MarqueeSelectionPolicy.resolved(base: baseIDs,
                                                     hitIDs: hitIDs,
                                                     mode: mode,
                                                     scope: scopeProvider())
        guard target != lastTargetIDs else { return }
        lastTargetIDs = target
        applyTargetIDs(target)
        haptic.selectionChanged()
    }

    /// 窗口坐标 → collectionView 内容坐标（滚动后仍对应手指下的内容点）。
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
        // startPoint 保持 content 坐标不变：滚动后矩形按内容坐标重算，新流入的 cell 自然入集
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

    /// 结束/取消/失败统一收尾：恢复点选、清快照/displayLink。
    func finishSlideSelection() {
        invalidateAutoScroll()
        state = .finished
        anchorID = nil
        startPoint = .zero
        baseIDs = []
        lastTargetIDs = []
        mode = .select
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
