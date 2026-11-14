// MARK: - 职责说明：多选手势编排器（M17 T05，docs/32 §2.3）——长按进入多选、长按/横向拖框选、
// 方向锁、单指滚动保留、边缘自动滚动。全部判定喂 PhotoDeskCore.SelectionGestureMachine
//（docs/32 §2.2 状态表；阈值只取 SelectionGestureConfig / SlideSelectConfig，App 层零判定数字），
// 本类只做 UIKit 事件映射与效果执行：
//   TouchDownObserver（UILongPress minimumPressDuration=0）→ touchDown(point:hitID:)（G3 按下点取证）
//   holdElapsed 双通道交付：UILongPress（时长/位移取自 SelectionGestureConfig）+ 按下定时器
//   （触点在屏时补发，识别器失效不至于丢长按；机器 state/位移守卫保证幂等）
//   marqueePan（单指）→ moved(dx:dy:) / ended / cancelled；edgeEntered/edgeExited 由
//   dragging/autoScrolling 期间的逐帧边缘监视交付（指尖停边缘不动也持续滚动，docs/32 §2.4）
//   scrollViewWillBeginDragging（VC 转发）→ scrollStarted
// 效果执行：enterSelection → VC 进多选并选锚点；beginMarquee / endMarquee 与 isScrollEnabled
// 成对（docs/32 §2.3「进入 armed 后禁滚动」；releaseScroll 由机器在方向让位/收尾时配对补发）；
// updateMarquee → 重算命中（命中集合变化才是 G6 触觉闸门）；startAutoScroll / stopAutoScroll →
// CADisplayLink 60fps（边缘 60pt、2–12pt/帧，Core edgeVelocity + clampedOffset）。
// 框选矩形：机器按下点（content 坐标）→ 当前指尖；零尺寸扩 1pt（起手 cell 命中）。

import UIKit
import PhotoDeskCore

#if DEBUG
/// UI 取证：最近一次框选矩形（content 坐标；T06 覆盖层接入前供 UI 测试取证）。
enum LibrarySelectionDebugState {
    static var lastMarqueeRect: CGRect?
}
#endif

@MainActor
final class LibrarySelectionController: NSObject {

    // MARK: VC 注入

    var isSelectionMode: () -> Bool = { false }
    /// 矩形（内容坐标）→ 命中 id 集合（GridHitTester 真实 attributes + dataSource 映射，T04）。
    var hitTestProvider: (CGRect) -> Set<String> = { _ in [] }
    /// 框选目标集合整体落地（applySlideSelection：可见 cell diff + 计数）。
    var applyTargetIDs: (Set<String>) -> Void = { _ in }
    var scopeProvider: () -> Set<String>? = { nil }
    /// enterSelection 效果 → VC enterSelectionMode(selecting:)（长按进入多选的唯一入口）。
    var onSelectionEntered: (String) -> Void = { _ in }
    /// 框选矩形（内容坐标）变化回调；nil = 结束。T06 在此挂覆盖层。
    var onMarqueeRectChanged: ((CGRect?) -> Void) = { _ in }

    private weak var collectionView: UICollectionView?
    private var machine: SelectionGestureMachine
    private var gestureConfig = SelectionGestureConfig()
    private var baseIDs: Set<String> = []
    private var mode: MarqueeMode = .select
    private var lastTargetIDs: Set<String> = []
    private var lastFingerWindowPoint: CGPoint = .zero
    private var lastPanTranslation: CGPoint = .zero
    private var currentEdgeDirection = 0
    private var autoScrollLink: CADisplayLink?
    /// G6 闸门：updateMarquee 帧命中集合确有变化时才放行机器的 selectionChanged 触觉。
    private var pendingSelectionHaptic = false
    /// 本次触摸已进入过多选（armed 起）：didSelectItemAt 在 touch-up 后 0.3s 内跳过重复 toggle。
    private var consumedTouch = false
    private var consumedTouchEndedAt: TimeInterval = 0
    /// holdElapsed 定时器：识别器判定在合成触控上偶发失效，触点在屏时按同一时长补发（幂等）。
    private var holdElapsedTimer: Timer?
    /// dragging/autoScrolling 期间逐帧边缘监视：指尖停在边缘不动（无 .changed）也要进自动滚动。
    private var edgeMonitorLink: CADisplayLink?
    private let selectHaptic = UISelectionFeedbackGenerator()
    private let impactHaptic = UIImpactFeedbackGenerator(style: .light)

    /// 供 VC delegate / UI 测试观察：框选拖动进行中。
    var isDragSelecting: Bool {
        machine.state == .dragging || machine.state == .autoScrolling
    }

    /// 长按已消费本次触摸：armed/dragging/autoScrolling 期间 + 抬手后 0.3s 内。
    var isConsumingTouch: Bool {
        switch machine.state {
        case .armed, .dragging, .autoScrolling, .ending:
            return consumedTouch
        default:
            return consumedTouch && CACurrentMediaTime() - consumedTouchEndedAt < 0.3
        }
    }

    /// config 注入：UI 测试以 -uiTestingLongPressMovement 放宽 allowableMovement
    ///（XCUI 合成按压存在微漂移，8pt 预算在 CI 上偶发杀死长按识别；Core 单测仍钉 8pt 语义）。
    init(collectionView: UICollectionView, config: SelectionGestureConfig = SelectionGestureConfig()) {
        self.collectionView = collectionView
        self.machine = SelectionGestureMachine(config: config)
        self.gestureConfig = config
        super.init()
        // TouchDownObserver：0 时长长按，只用于记录按下点（G3：框选起点 = 按下点而非 pan 触发点）
        let touchDown = UILongPressGestureRecognizer(target: self, action: #selector(handleTouchDown(_:)))
        touchDown.minimumPressDuration = 0
        touchDown.cancelsTouchesInView = false
        touchDown.delegate = self
        // 长按识别：0.28s / allowableMovement（SelectionGestureConfig，docs/32 §2.3），cancelsTouchesInView=false
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = TimeInterval(config.longPressDuration)
        longPress.allowableMovement = CGFloat(config.allowableMovement)
        longPress.cancelsTouchesInView = false
        longPress.delegate = self
        // 框选 pan：单指；与滚动 pan 同时识别，方向锁由机器判定后本类执行
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMarqueePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        collectionView.addGestureRecognizer(touchDown)
        collectionView.addGestureRecognizer(longPress)
        collectionView.addGestureRecognizer(pan)
        touchDownObserver = touchDown
        longPressRecognizer = longPress
        marqueePan = pan
        impactHaptic.prepare()
        selectHaptic.prepare()
    }

    private(set) var touchDownObserver: UILongPressGestureRecognizer!
    private(set) var longPressRecognizer: UILongPressGestureRecognizer!
    private(set) var marqueePan: UIPanGestureRecognizer!

    #if DEBUG
    /// UI 取证：自动滚动 tick 计数（M15 边缘滚动通道等价物）与机器状态名。
    private(set) var debugAutoScrollTicks = 0
    var debugStateName: String { "\(machine.state)" }
    #endif

    // MARK: UIKit 事件 → 机器

    @objc private func handleTouchDown(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastFingerWindowPoint = gesture.location(in: nil)
            lastPanTranslation = .zero
            consumedTouch = false
            currentEdgeDirection = 0
            guard let content = windowToContent(lastFingerWindowPoint) else { return }
            let hitID = hitIDAtContentPoint(content)
            if let hitID {
                // 锚点语义在按下帧取证（docs/25 §6.1：起手已选 → 取消模式）
                baseIDs = selectedIDsProvider()
                mode = MarqueeSelectionPolicy.mode(baseIDs: baseIDs, anchorID: hitID)
                lastTargetIDs = baseIDs
            }
            feed(.touchDown(point: GridPoint(x: Double(content.x), y: Double(content.y)), hitID: hitID))
            if machine.state == .pressing {
                scheduleHoldElapsed()
            }
        case .ended, .cancelled, .failed:
            feedEnd(cancelled: gesture.state != .ended)
        default:
            break
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            feed(.holdElapsed)
        case .ended, .cancelled, .failed:
            feedEnd(cancelled: gesture.state != .ended)
        default:
            break
        }
    }

    @objc private func handleMarqueePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            lastFingerWindowPoint = gesture.location(in: nil)
            let translation = gesture.translation(in: collectionView)
            let dx = Double(translation.x - lastPanTranslation.x)
            let dy = Double(translation.y - lastPanTranslation.y)
            lastPanTranslation = translation
            feed(.moved(dx: dx, dy: dy))
            feedEdgeEvents()
        case .ended, .cancelled, .failed:
            feedEnd(cancelled: gesture.state != .ended)
        default:
            break
        }
    }

    /// VC scrollViewWillBeginDragging 转发：滚动接管（pressing/armed 让位，选中集保留）。
    func handleScrollStarted() {
        feed(.scrollStarted)
    }

    /// 退出多选统一收尾：滚链/显示恢复、机器复位。
    func finishSelection() {
        invalidateAutoScroll()
        holdElapsedTimer?.invalidate()
        holdElapsedTimer = nil
        edgeMonitorLink?.invalidate()
        edgeMonitorLink = nil
        if collectionView?.isScrollEnabled == false {
            collectionView?.isScrollEnabled = true
        }
        onMarqueeRectChanged(nil)
        baseIDs = []
        lastTargetIDs = []
        mode = .select
        currentEdgeDirection = 0
        lastPanTranslation = .zero
        consumedTouch = false
        machine = SelectionGestureMachine(config: machine.config)
    }

    // MARK: 机器效果执行

    private func feed(_ event: SelectionGestureEvent) {
        machine.isSelectionModeActive = isSelectionMode()
        apply(machine.handle(event, now: CACurrentMediaTime()))
    }

    private func feedEnd(cancelled: Bool) {
        let event: SelectionGestureEvent = cancelled ? .cancelled : .ended
        if consumedTouch {
            consumedTouchEndedAt = CACurrentMediaTime()
        }
        holdElapsedTimer?.invalidate()
        holdElapsedTimer = nil
        feed(event)
    }

    /// docs/32 §2.2 holdElapsed 的定时器交付：时长取自同一 config，机器侧
    /// state == .pressing + 位移资格守卫保证与识别器交付幂等、语义一致。
    private func scheduleHoldElapsed() {
        holdElapsedTimer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(gestureConfig.longPressDuration),
                          target: self,
                          selector: #selector(holdElapsedFired),
                          userInfo: nil,
                          repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        holdElapsedTimer = timer
    }

    @objc private func holdElapsedFired() {
        holdElapsedTimer = nil
        guard touchDownObserver.state == .began, machine.state == .pressing else { return }
        feed(.holdElapsed)
    }

    private func apply(_ effects: [SelectionGestureEffect]) {
        for effect in effects {
            switch effect {
            case .enterSelection(let anchorID):
                consumedTouch = true
                onSelectionEntered(anchorID)
            case .beginMarquee:
                consumedTouch = true
                // armed 即禁滚动（docs/32 §2.3）；endMarquee/releaseScroll 成对恢复
                collectionView?.isScrollEnabled = false
                onMarqueeRectChanged(currentMarqueeRect())
            case .updateMarquee:
                processFinger()
                onMarqueeRectChanged(currentMarqueeRect())
            case .endMarquee:
                collectionView?.isScrollEnabled = true
                onMarqueeRectChanged(nil)
            case .releaseScroll:
                collectionView?.isScrollEnabled = true
                // 纵向占优交还滚动（docs/32 §2.3）：框选 pan 主动失败，滚动 pan 接管
                if marqueePan.state == .changed || marqueePan.state == .began {
                    marqueePan.state = .failed
                }
            case .haptic(let kind):
                switch kind {
                case .impactLight:
                    impactHaptic.impactOccurred()
                case .selectionChanged:
                    // G6：以命中集合变化为最终闸门（processFinger 置位 pendingSelectionHaptic）
                    if pendingSelectionHaptic {
                        selectHaptic.selectionChanged()
                        pendingSelectionHaptic = false
                    }
                }
            case .startAutoScroll:
                // 方向由逐帧 edgeVelocity 决定（与机器 autoScrolling 状态配对）
                ensureAutoScrollLink()
            case .stopAutoScroll:
                invalidateAutoScroll()
            }
        }
        if machine.state == .dragging || machine.state == .autoScrolling {
            ensureEdgeMonitor()
        }
    }

    /// docs/32 §2.4「指尖停在边缘区持续滚动」：逐帧检测边缘进出，
    /// 不依赖 pan 的 .changed 事件（指尖静止时无事件，仅靠它会卡在 dragging 不进 autoScrolling）。
    private func ensureEdgeMonitor() {
        guard edgeMonitorLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(edgeMonitorTick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        edgeMonitorLink = link
    }

    @objc private func edgeMonitorTick(_ link: CADisplayLink) {
        guard machine.state == .dragging || machine.state == .autoScrolling else {
            edgeMonitorLink?.invalidate()
            edgeMonitorLink = nil
            return
        }
        feedEdgeEvents()
    }

    // MARK: 框选命中（矩形语义与 T04 GridHitTester 对接）

    /// VC 注入：当前选中 id 快照（锚点模式取证用）。
    var selectedIDsProvider: () -> Set<String> = { [] }

    /// VC 注入：内容坐标 → 命中 cell 的 assetID（indexPathForItem + dataSource）。
    var hitIDAtContentPoint: (CGPoint) -> String? = { _ in nil }

    private func processFinger() {
        guard machine.state == .dragging || machine.state == .autoScrolling || machine.state == .armed,
              let press = machine.pressPoint else { return }
        guard let current = windowToContent(lastFingerWindowPoint) else { return }
        let minX = min(press.x, current.x)
        let maxX = max(press.x, current.x)
        let minY = min(press.y, current.y)
        let maxY = max(press.y, current.y)
        let clampedMaxX = maxX - minX < 1 ? minX + 1 : maxX
        let clampedMaxY = maxY - minY < 1 ? minY + 1 : maxY
        let rect = CGRect(x: minX, y: minY,
                          width: clampedMaxX - minX, height: clampedMaxY - minY)
        let hitIDs = hitTestProvider(rect)
        let target = MarqueeSelectionPolicy.resolved(base: baseIDs,
                                                     hitIDs: hitIDs,
                                                     mode: mode,
                                                     scope: scopeProvider())
        if target != lastTargetIDs {
            pendingSelectionHaptic = true
        }
        guard target != lastTargetIDs else { return }
        lastTargetIDs = target
        applyTargetIDs(target)
    }

    private func currentMarqueeRect() -> CGRect? {
        guard let press = machine.pressPoint,
              let current = windowToContent(lastFingerWindowPoint) else { return nil }
        return CGRect(x: min(press.x, current.x), y: min(press.y, current.y),
                      width: abs(current.x - press.x), height: abs(current.y - press.y))
    }

    // MARK: 边缘自动滚动

    private func ensureAutoScrollLink() {
        guard autoScrollLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    private func invalidateAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
    }

    @objc private func autoScrollTick(_ link: CADisplayLink) {
        guard machine.state == .autoScrolling else {
            invalidateAutoScroll()
            return
        }
        let velocity = edgeVelocity()
        guard velocity != 0 else { return }   // 指尖不在边缘区：空转，回边缘即续滚
        guard let collectionView else { return }
        #if DEBUG
        debugAutoScrollTicks += 1
        #endif
        let minY = -Double(collectionView.adjustedContentInset.top)
        let maxY = max(minY,
                       Double(collectionView.contentSize.height
                              + collectionView.adjustedContentInset.bottom
                              - collectionView.bounds.height))
        let target = SlideSelectPolicy.clampedOffset(current: Double(collectionView.contentOffset.y),
                                                     delta: velocity,
                                                     min: minY,
                                                     max: maxY)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: target),
                                        animated: false)
        feedEdgeEvents()   // 内容触底/顶后指尖仍在边缘：方向保持，位移由 clampedOffset 钳制
        processFinger()    // 滚动后指尖下内容变化 → 逐帧重算命中（docs/31 §2.4）
    }

    private func edgeVelocity() -> Double {
        guard let collectionView,
              let content = windowToContent(lastFingerWindowPoint) else { return 0 }
        let fingerViewportY = Double(content.y - collectionView.contentOffset.y)
        let top = Double(collectionView.adjustedContentInset.top)
        let bottom = Double(collectionView.bounds.height - collectionView.adjustedContentInset.bottom)
        return SlideSelectPolicy.edgeVelocity(fingerY: fingerViewportY,
                                              top: top,
                                              bottom: bottom,
                                              buffer: SlideSelectConfig.edgeBuffer,
                                              minStep: SlideSelectConfig.minStep,
                                              maxStep: SlideSelectConfig.maxStep)
    }

    private func feedEdgeEvents() {
        guard machine.state == .dragging || machine.state == .autoScrolling else {
            currentEdgeDirection = 0
            return
        }
        let direction = edgeDirection()
        guard direction != currentEdgeDirection else { return }
        if currentEdgeDirection != 0 {
            feed(.edgeExited)
        }
        if direction != 0 {
            feed(.edgeEntered(direction: direction))
        }
        currentEdgeDirection = direction
    }

    private func edgeDirection() -> Int {
        guard let collectionView,
              let content = windowToContent(lastFingerWindowPoint) else { return 0 }
        let viewportY = Double(content.y - collectionView.contentOffset.y)
        let top = Double(collectionView.adjustedContentInset.top)
        let bottom = Double(collectionView.bounds.height - collectionView.adjustedContentInset.bottom)
        if viewportY <= top + SlideSelectConfig.edgeBuffer { return -1 }
        if viewportY >= bottom - SlideSelectConfig.edgeBuffer { return 1 }
        return 0
    }

    private func windowToContent(_ windowPoint: CGPoint) -> CGPoint? {
        guard let collectionView, collectionView.window != nil else { return nil }
        return collectionView.convert(windowPoint, from: nil)
    }
}

// MARK: - 手势仲裁（docs/32 §2.3：识别器只允许「命中 cell」起步，与滚动/长按互相让位）

extension LibrarySelectionController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let collectionView else { return false }
        let point = gestureRecognizer.location(in: collectionView)
        return collectionView.indexPathForItem(at: point) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // 与滚动 pan / 长按 / TouchDownObserver 全部允许同时识别（方向归属由机器判定 + .failed）
        true
    }
}
