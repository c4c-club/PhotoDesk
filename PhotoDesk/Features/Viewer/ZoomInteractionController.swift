// MARK: - 职责说明：查看器缩放手势控制器（docs/25 §4.4 / M15 P0-1；docs/28 §4.4.2 / M16 P0-1A 事务化）——
// 自管变换：pinch/pan/double-tap 全部只调 PhotoDeskCore.ZoomTransformPolicy，绝不触碰
// UIScrollView 的 zoom API（delegate=nil、min=max zoom=1、isScrollEnabled=false 的纯容器）。
// 状态机 idle → pinching → settling → idle / idle → panning → idle / idle → animating → idle；
// M16 T01：手势/动画窗口的事件决策收口到 Core.ZoomTransformTransaction——
// ① 禁止对 UIGestureRecognizer.state 赋值（旧实现 .cancelled 赋值破坏 UIKit 手势状态机，捏合必崩根因）；
// ② 动画使用代际 token transactionToken，复用/新动画后旧 completion 一律失效；
// ③ invalidated（复用/旋转/布局/程序性复位）立即回 idle 并复位 identity。
// isInteracting 期间 VC 禁用 collectionView 滚动与翻页；reset/invalidate 供复用/翻页/旋转调用。

import UIKit
import PhotoDeskCore

@MainActor
final class ZoomInteractionController: NSObject {
    /// 交互状态
    enum Phase: Equatable {
        case idle
        case pinching
        case panning
        case settling
        case animating
    }

    /// 变换回调：cell 只做 imageView.transform / center 适配。
    var onTransformChanged: ((ZoomTransform) -> Void)?
    /// 双击识别器 action 以任意 state 进入（含 .failed），取证用（dtapIn）。
    var onDoubleTapEntered: (() -> Void)?
    /// shouldBegin 被问双击（取证 sb/sbr：区分"没收到触摸"与"shouldBegin 拒绝"）。
    var onShouldBeginDoubleTap: ((_ result: Bool) -> Void)?
    /// 双击 action 进入次数（任意 state）
    private(set) var doubleTapEnterCount = 0
    /// shouldBegin 被问双击次数
    private(set) var shouldBeginDoubleTapCount = 0
    /// 单击（双击失败后）落在视口：chrome 切换/视频播放的唯一入口（同 view require，无跨 view 互斥）。
    var onSingleTap: (() -> Void)?
    /// 交互状态回调：VC 用来禁用翻页/上下滑动作。
    var onInteractionStateChanged: ((Bool) -> Void)?
    /// 手势回到 idle（含动画完成）后回调一次；VC 用于串行 drain 删除队列。
    var onInteractionDidEnd: (() -> Void)?

    private(set) var phase: Phase = .idle
    private(set) var transform = ZoomTransform.identity
    /// 动画代际 token：每次开动画 +1，invalidated 清零（决策表唯一事实源在 Core）
    private(set) var transactionToken = 0
    private var lastActivity: TimeInterval = 0
    /// cell 注入：视口（viewportScrollView）与内容 aspectFit 尺寸
    private weak var viewportView: UIView?
    private var contentFitSize: CGSize = .zero
    /// 手势是否允许（无图/占位态关闭）
    private var gesturesEnabled = false
    /// 捏合起始快照（anchor 全程固定在起手视口坐标）
    private var pinchStartTransform = ZoomTransform.identity
    private var pinchAnchor: CGPoint = .zero
    private var panStartTransform = ZoomTransform.identity

    let pinch = UIPinchGestureRecognizer()
    let pan = UIPanGestureRecognizer()
    let doubleTap = UITapGestureRecognizer()
    /// 单击（chrome 切换）：与双击同 view，require(toFail:) 教科书序——双击成功则单击 fail（chrome 不闪），
    /// 双击被禁（无图）时依赖视为 vacuous，单击立即可用。chromeTap 不能挂在查看器根 view 上：
    /// 跨 view 互斥规则（任一 delegate 拒绝并行）会在根 tap 识别成功时强制 fail cell 双击（M15 三轮实锤）。
    let tap = UITapGestureRecognizer()

    /// 供 ViewerGesturePolicy / UI 测试观察
    var isInteracting: Bool { phase != .idle }
    var isAnimating: Bool { phase == .animating || phase == .settling }
    var scale: Double { transform.scale }
    var secondsSinceActivity: TimeInterval { CACurrentMediaTime() - lastActivity }

    /// Core 决策输入快照：App 4 态映射到 Core 3 相（pinching/panning → interacting；settling/animating → animating）
    private var transactionSnapshot: ZoomTransactionSnapshot {
        let corePhase: ZoomTransactionSnapshot.Phase
        switch phase {
        case .idle: corePhase = .idle
        case .pinching, .panning: corePhase = .interacting
        case .settling, .animating: corePhase = .animating
        }
        return ZoomTransactionSnapshot(phase: corePhase, animationToken: transactionToken)
    }

    init(viewportView: UIView) {
        self.viewportView = viewportView
        super.init()
        configure(pinch)
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        configure(pan)
        pan.maximumNumberOfTouches = 1
        pan.addTarget(self, action: #selector(handlePan(_:)))
        configure(doubleTap)
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        configure(tap)
        tap.isEnabled = true   // chrome 切换不依赖图片就绪（其余手势按 ready 门禁）
        tap.require(toFail: doubleTap)
        tap.addTarget(self, action: #selector(handleTap(_:)))
        viewportView.addGestureRecognizer(pinch)
        viewportView.addGestureRecognizer(pan)
        viewportView.addGestureRecognizer(doubleTap)
        viewportView.addGestureRecognizer(tap)
    }

    private func configure(_ gesture: UIGestureRecognizer) {
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        gesture.isEnabled = false
    }

    // MARK: - cell 接线

    func updateLayout(contentFitSize: CGSize, viewportSize: CGSize) {
        self.contentFitSize = contentFitSize
        let ready = gesturesEnabled && contentFitSize.width > 0 && contentFitSize.height > 0
            && viewportSize.width > 0 && viewportSize.height > 0
        if pinch.isEnabled != ready {
            pinch.isEnabled = ready
            doubleTap.isEnabled = ready
            // pan 的 shouldBegin 里还有 scale > 1.01 门禁，enabled 只表达内容就绪
            pan.isEnabled = ready
        }
    }

    func setGesturesEnabled(_ enabled: Bool) {
        gesturesEnabled = enabled
        // 门禁变化必须立即重估手势可用性：图片晚于首次布局到达（configure 时无图），
        // 若只等下一次布局回调，捏合/双击会永远停用（docs/26 §5.4 门禁不变量）
        updateLayout(contentFitSize: contentFitSize,
                     viewportSize: viewportView?.bounds.size ?? .zero)
        if !enabled, isInteracting, phase != .animating, phase != .settling {
            endInteraction()
        }
    }

    /// cell 布局/旋转时写入 relayout 结果（不进入交互状态，只同步钳制后的值）。
    func applyRelayout(_ t: ZoomTransform) {
        setTransform(t)
    }

    /// 复用/翻页/删除/旋转：立即回 1× 居中（无动画）。
    /// animated=true 且空闲时走动画收敛；动画/交互窗口一律 invalidate（禁止未 settled 复位半途）。
    func reset(animated: Bool) {
        guard transform != .identity || isInteracting else { return }
        if animated, !isInteracting, !UIAccessibility.isReduceMotionEnabled {
            animate(to: .identity)
        } else {
            invalidateTransaction()
        }
    }

    /// invalidated 决策入口：复用/旋转/布局/程序性复位。
    /// 取消动画代际（旧 completion 失配）并立即回 identity；程序性复位属于一次"事务结束"：
    /// 必须发 didEnd（VC 串行 drain 依赖该信号）。
    /// 程序性复位同时耗尽回弹宽限窗口：宽限只挂在真实用户手势之后
    /// （docs/26 §5.4——否则翻页/复用/批量更新后删除队列会被宽限卡 1 秒）。
    func invalidateTransaction() {
        let wasInteracting = phase != .idle
        let wasTransformed = transform != .identity
        transactionToken = 0
        guard wasInteracting || wasTransformed else { return }
        phase = .idle
        setTransform(.identity)
        if wasInteracting {
            onInteractionStateChanged?(false)
        }
        lastActivity = CACurrentMediaTime() - DSMotion.zoomActivityGrace
        onInteractionDidEnd?()
    }

    // MARK: - 手势处理

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let viewport = viewportView, contentFitSize.width > 0 else { return }
        switch gesture.state {
        case .began:
            // M16 T01：动画/交互窗口直接 return（Core 决策），绝不写 gesture.state（旧实现 .cancelled 赋值 = 崩溃根因）
            guard ZoomTransformTransaction.decide(state: transactionSnapshot,
                                                  event: .gestureBegan(.pinch)) == .beginInteraction else { return }
            pinchStartTransform = transform
            pinchAnchor = gesture.location(in: viewport)
            begin(.pinching)
        case .changed:
            guard phase == .pinching else { return }
            let t = ZoomTransformPolicy.pinch(
                current: pinchStartTransform,
                pinchScale: Double(gesture.scale),
                anchorX: Double(pinchAnchor.x), anchorY: Double(pinchAnchor.y),
                contentWidth: Double(contentFitSize.width), contentHeight: Double(contentFitSize.height),
                viewportWidth: Double(viewport.bounds.width), viewportHeight: Double(viewport.bounds.height))
            setTransform(t)
        case .ended, .cancelled, .failed:
            guard phase == .pinching else { return }
            settleAfterGesture()
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let viewport = viewportView, contentFitSize.width > 0 else { return }
        switch gesture.state {
        case .began:
            // 只在已放大时接管单指平移；1× 时让位给翻页/上下滑；动画/交互窗口直接 return（绝不写 gesture.state）
            guard transform.scale > 1.01,
                  ZoomTransformTransaction.decide(state: transactionSnapshot,
                                                  event: .gestureBegan(.pan)) == .beginInteraction else { return }
            panStartTransform = transform
            begin(.panning)
        case .changed:
            guard phase == .panning else { return }
            let translation = gesture.translation(in: viewport)
            let t = ZoomTransformPolicy.pan(
                current: panStartTransform,
                deltaX: Double(translation.x), deltaY: Double(translation.y),
                contentWidth: Double(contentFitSize.width), contentHeight: Double(contentFitSize.height),
                viewportWidth: Double(viewport.bounds.width), viewportHeight: Double(viewport.bounds.height))
            setTransform(t)
        case .ended, .cancelled, .failed:
            guard phase == .panning else { return }
            settleAfterGesture()
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // 取证：任何 state 进入都计（.failed/.cancelled 也会调 action）
        doubleTapEnterCount += 1
        onDoubleTapEntered?()
        guard let viewport = viewportView, contentFitSize.width > 0,
              gesture.state == .ended,
              ZoomTransformTransaction.decide(state: transactionSnapshot,
                                              event: .animationRequested) == .beginAnimation else { return }
        let point = gesture.location(in: viewport)
        let target: ZoomTransform
        if transform.scale > 1.01 {
            target = .identity
        } else {
            target = ZoomTransformPolicy.doubleTap(
                current: transform,
                tapX: Double(point.x), tapY: Double(point.y),
                contentWidth: Double(contentFitSize.width), contentHeight: Double(contentFitSize.height),
                viewportWidth: Double(viewport.bounds.width), viewportHeight: Double(viewport.bounds.height))
        }
        animate(to: target)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onSingleTap?()
    }

    // MARK: - 状态机

    private func begin(_ newPhase: Phase) {
        phase = newPhase
        lastActivity = CACurrentMediaTime()
        onInteractionStateChanged?(true)
    }

    /// 手势结束：终值在每帧已按策略钳制（scale 恒在 1...5、平移不露白），直接收敛回 idle。
    private func settleAfterGesture() {
        guard ZoomTransformTransaction.decide(state: transactionSnapshot,
                                              event: .gestureEnded) == .settle else { return }
        phase = .settling
        lastActivity = CACurrentMediaTime()
        setTransform(transform)
        endInteraction()
    }

    private func animate(to target: ZoomTransform) {
        let decision = ZoomTransformTransaction.decide(state: transactionSnapshot, event: .animationRequested)
        guard decision == .beginAnimation else { return }
        transactionToken = ZoomTransformTransaction.advanced(transactionSnapshot, by: decision).animationToken
        let token = transactionToken
        phase = .animating
        lastActivity = CACurrentMediaTime()
        onInteractionStateChanged?(true)
        let duration = target == .identity ? 0.22 : 0.25
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.setTransform(target)
        } completion: { _ in
            // 代际校验：复用（invalidateTransaction）或新动画开启后，旧 completion 一律失效（docs/28 §4.4.2 #3）
            let completion = ZoomTransformTransaction.decide(
                state: self.transactionSnapshot,
                event: .animationCompleted(token: token))
            guard completion == .finishAnimation else { return }
            self.endInteraction()
        }
    }

    private func setTransform(_ t: ZoomTransform) {
        transform = t
        onTransformChanged?(t)
    }

    /// 手势/动画结束统一收敛；forceNotify 供程序性 reset 使用（phase 本已 idle 也要发 didEnd）。
    private func endInteraction(forceNotify: Bool = false) {
        let wasInteracting = phase != .idle
        guard forceNotify || wasInteracting else { return }
        phase = .idle
        if wasInteracting {
            onInteractionStateChanged?(false)
            lastActivity = CACurrentMediaTime()
        }
        onInteractionDidEnd?()
    }
}

extension ZoomInteractionController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === tap { return true }   // chrome 切换不依赖图片就绪（tap 不走 ready 门禁）
        let result: Bool
        guard gesturesEnabled, contentFitSize.width > 0, contentFitSize.height > 0,
              let viewport = viewportView,
              viewport.bounds.width > 0, viewport.bounds.height > 0 else {
            result = false
            if gestureRecognizer === doubleTap { shouldBeginDoubleTapCount += 1; onShouldBeginDoubleTap?(false) }
            return result
        }
        if gestureRecognizer === pan {
            result = transform.scale > 1.01
        } else {
            result = true
        }
        if gestureRecognizer === doubleTap { shouldBeginDoubleTapCount += 1; onShouldBeginDoubleTap?(result) }
        return result
    }

    /// 与外层翻页/上下滑手势互斥：捏合与放大平移期间绝不并行识别。
    /// M15 dtap=0 实锤：UIKit 并行规则是"任一方 delegate 拒绝即互斥"——第一击 chrome tap
    /// （view 层、无 require）识别成功后，本 delegate 一律 false 会把 cell 双击强制 fail，
    /// 缩放从未触发。故仅对本 cell 的三个手势拒绝并行；对外部识别器放行——
    /// 放大期间的翻页互斥由 isScrollEnabled 门禁（cell.syncInteraction）与 shouldBegin 承担。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if other === pinch || other === pan || other === doubleTap { return false }
        return true
    }

    /// 放大平移时要求外层 pan 失败（cell pan 优先）。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

#if DEBUG
// 单元测试锚点（Release 不编译）
extension ZoomInteractionController {
    var test_areGesturesEnabled: Bool { pinch.isEnabled }
    var test_transform: ZoomTransform { transform }
    var test_transactionToken: Int { transactionToken }
    func test_invalidate() { invalidateTransaction() }
}
#endif
