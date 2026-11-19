// MARK: - 职责说明：多选手势编排器（M17 T05 建立，M18 T05 轨迹滑选接线，docs/38 §2/§3）——
// 长按进入多选、轨迹滑选（滑到哪选到哪、回滑收缩、允许滚动）、方向锁、边缘自动滚动。
// 全部判定喂 PhotoDeskCore.SelectionGestureMachine（docs/32 §2.2 状态表 + M18 T04 effect 改名；
// 阈值只取 SelectionGestureConfig / SlideSelectConfig，App 层零判定数字），
// 本类只做 UIKit 事件映射与效果执行：
//   TouchDownObserver（UILongPress minimumPressDuration=0）→ touchDown(point:hitID:)（G3 按下点取证）
//   holdElapsed 双通道交付：UILongPress（时长/位移取自 SelectionGestureConfig）+ 按下定时器
//   （触点在屏时补发，识别器失效不至于丢长按；机器 state/位移守卫保证幂等）
//   trailPan（单指）→ moved(dx:dy:) / ended / cancelled；edgeEntered/edgeExited 由
//   dragging/autoScrolling 期间的逐帧边缘监视交付（指尖停边缘不动也持续滚动，docs/32 §2.4）
//   scrollViewWillBeginDragging（VC 转发）→ scrollStarted
// 效果执行：enterSelection → VC 进多选并选锚点；beginTrail / endTrail 与 isScrollEnabled
// 成对（docs/32 §2.3「进入 armed 后禁滚动」；releaseScroll 由机器在方向让位/收尾时配对补发）；
// updateTrail → rowBandHitProvider 行带展开有序命中 + SlideSelectTrail 路径事务净 delta
//（滑到哪选到哪、回滑截断出栈、delta 空不触觉）；startAutoScroll / stopAutoScroll →
// CADisplayLink 60fps（边缘 60pt、2–12pt/帧，Core edgeVelocity + clampedOffset）；
// 自动滚动 tick 以滚动前后同一窗口坐标换算的 content 两点喂轨迹（屏外内容按序入栈）。
// 选中集唯一写入口：applySelectionDelta → VC applySelectionChanges（SelectionState.applyDelta）。

import UIKit
import PhotoDeskCore

@MainActor
final class LibrarySelectionController: NSObject {

    // MARK: VC 注入

    var isSelectionMode: () -> Bool = { false }
    /// 行带（内容坐标起止）→ 已展开、行主序 assetID 序列（GridHitTester.rowBandHitTest + dataSource 映射，
    /// 只过滤 nil、保持行带平铺序；零长度 = 所在整行，docs/42 §3.2）。
    var rowBandHitProvider: (CGPoint, CGPoint) -> [String] = { _, _ in [] }
    /// 路径事务净增量落地（applySelectionChanges：SelectionState.applyDelta + 可见 cell diff）。
    var applySelectionDelta: (Set<String>, Set<String>) -> Void = { _, _ in }
    var scopeProvider: () -> Set<String>? = { nil }
    /// 快照 apply 窗口取证（M17 T07）：true = diffable apply 进行中，真实 attributes 不可靠。
    var isApplyingSnapshotProvider: () -> Bool = { false }
    /// enterSelection 效果 → VC enterSelectionMode(selecting:)（长按进入多选的唯一入口）。
    var onSelectionEntered: (String) -> Void = { _ in }
    /// 轨迹活跃变化（beginTrail → true；endTrail/finishSelection → false）：多选栏提示由 VC 切换。
    var onTrailActiveChanged: (Bool) -> Void = { _ in }

    private weak var collectionView: UICollectionView?
    private var machine: SelectionGestureMachine
    private var gestureConfig = SelectionGestureConfig()
    /// 本次手势的路径事务（beginTrail 构造、consume 逐帧推进；endTrail/finishSelection 销毁）。
    private var trail: SlideSelectTrail?
    /// 最近一次轨迹命中点（content 坐标）：线段起点；autoScroll 前后两点取同一窗口坐标换算。
    private var lastTrailContentPoint: CGPoint?
    /// enterSelection 交付的锚点 id（beginTrail 帧构造事务的起点 cell）。
    private var trailAnchorID: String?
    /// 锚点语义按下帧取证（docs/25 §6.1）：true = 起手已选（取消模式），false = 选择模式。
    private(set) var anchorInitiallySelected = false
    /// 最近一次按下帧取证：基集合大小与命中 id（UI 测试定位锚点判定分歧）。
    private(set) var debugTouchDownBaseCount = -1
    private(set) var debugTouchDownHitID: String = "-"
    private var lastFingerWindowPoint: CGPoint = .zero
    private var lastPanTranslation: CGPoint = .zero
    private var currentEdgeDirection = 0
    private var autoScrollLink: CADisplayLink?
    /// G6 闸门：updateTrail 帧净增量确有变化时才放行机器的 selectionChanged 触觉。
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

    /// 供 VC delegate / UI 测试观察：轨迹滑选拖动进行中。
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
        // TouchDownObserver：0 时长长按，只用于记录按下点（G3：轨迹滑选起点 = 按下点而非 pan 触发点）
        let touchDown = UILongPressGestureRecognizer(target: self, action: #selector(handleTouchDown(_:)))
        touchDown.minimumPressDuration = 0
        // 观察器身份：只记录按下点与触点存续，位移不构成失败——否则按压相位的微漂移
        // 会使其 .failed → feedEnd(.cancelled) 复位机器并作废 holdElapsed 定时器（T06 取证）。
        touchDown.allowableMovement = .greatestFiniteMagnitude
        touchDown.cancelsTouchesInView = false
        touchDown.delegate = self
        // 长按识别：0.28s / allowableMovement（SelectionGestureConfig，docs/32 §2.3），cancelsTouchesInView=false
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = TimeInterval(config.longPressDuration)
        longPress.allowableMovement = CGFloat(config.allowableMovement)
        longPress.cancelsTouchesInView = false
        longPress.delegate = self
        // 轨迹 pan：单指；与滚动 pan 同时识别，方向锁由机器判定后本类执行
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTrailPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        collectionView.addGestureRecognizer(touchDown)
        collectionView.addGestureRecognizer(longPress)
        collectionView.addGestureRecognizer(pan)
        touchDownObserver = touchDown
        longPressRecognizer = longPress
        trailPan = pan
        impactHaptic.prepare()
        selectHaptic.prepare()
    }

    private(set) var touchDownObserver: UILongPressGestureRecognizer!
    private(set) var longPressRecognizer: UILongPressGestureRecognizer!
    private(set) var trailPan: UIPanGestureRecognizer!

    #if DEBUG
    /// UI 取证：触觉实发计数（验收：≤16 次/秒 = 60ms 节流生效）。
    private(set) var debugHapticCount = 0
    /// UI 取证：自动滚动 tick 计数（M15 边缘滚动通道等价物）与机器状态名。
    private(set) var debugAutoScrollTicks = 0
    /// UI 取证：最近一次边缘判定（-1 顶 / +1 底 / 0 区外）与指尖视口 y、视口几何。
    private(set) var debugLastEdgeDirection = 0
    private(set) var debugLastFingerViewportY: Double = -1
    private(set) var debugViewportBottom: Double = -1
    /// UI 取证：当前路径事务深度（SlideSelectTrail 路径栈长度；无事务 -1）。
    private(set) var debugTrailPathCount = -1
    /// UI 取证：最近一次净增量（"+add/-remove" 计数；"+0/-0" = 空帧）。
    private(set) var debugLastDelta = "-"
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
                // 锚点语义在按下帧取证（docs/25 §6.1：起手已选 → 取消模式；M18 由 SlideSelectTrail
                // init 快照，App 不再持有 base 集合）
                anchorInitiallySelected = selectedIDsProvider().contains(hitID)
                #if DEBUG
                debugTouchDownBaseCount = selectedIDsProvider().count
                debugTouchDownHitID = hitID
                #endif
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

    @objc private func handleTrailPan(_ gesture: UIPanGestureRecognizer) {
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

    /// 退出多选统一收尾：滚链/显示恢复、机器复位；不清空 selectionState（退出多选由 VC 负责）。
    func finishSelection() {
        invalidateAutoScroll()
        holdElapsedTimer?.invalidate()
        holdElapsedTimer = nil
        edgeMonitorLink?.invalidate()
        edgeMonitorLink = nil
        trail = nil
        lastTrailContentPoint = nil
        trailAnchorID = nil
        anchorInitiallySelected = false
        if collectionView?.isScrollEnabled == false {
            collectionView?.isScrollEnabled = true
        }
        onTrailActiveChanged(false)
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
                trailAnchorID = anchorID
                onSelectionEntered(anchorID)
            case .beginTrail:
                consumedTouch = true
                // armed 即禁滚动（docs/32 §2.3）；endTrail/releaseScroll 成对恢复
                collectionView?.isScrollEnabled = false
                // 事务基集 = enterSelection 之后的真实选中集（含锚点），按下帧锚点语义定 mode
                guard let anchor = trailAnchorID else { break }
                var started = SlideSelectTrail(base: selectedIDsProvider(),
                                               anchorInitiallySelected: anchorInitiallySelected,
                                               scope: scopeProvider())
                let delta = started.consume([anchor])
                trail = started
                if let press = machine.pressPoint {
                    lastTrailContentPoint = CGPoint(x: press.x, y: press.y)
                }
                #if DEBUG
                debugTrailPathCount = started.path.count
                debugLastDelta = "+\(delta.add.count)/-\(delta.remove.count)"
                #endif
                if !delta.isEmpty {
                    pendingSelectionHaptic = true
                    applySelectionDelta(delta.add, delta.remove)
                }
                onTrailActiveChanged(true)
            case .updateTrail:
                if let last = lastTrailContentPoint,
                   let current = windowToContent(lastFingerWindowPoint) {
                    processTrail(from: last, to: current)
                }
            case .endTrail:
                collectionView?.isScrollEnabled = true
                trail = nil
                lastTrailContentPoint = nil
                onTrailActiveChanged(false)
            case .releaseScroll:
                collectionView?.isScrollEnabled = true
                // 纵向占优交还滚动（docs/32 §2.3）：轨迹 pan 主动失败，滚动 pan 接管
                if trailPan.state == .changed || trailPan.state == .began {
                    trailPan.state = .failed
                }
            case .haptic(let kind):
                switch kind {
                case .impactLight:
                    impactHaptic.impactOccurred()
                    #if DEBUG
                    debugHapticCount += 1
                    #endif
                case .selectionChanged:
                    // G6：以路径净增量变化为最终闸门（processTrail 置位 pendingSelectionHaptic），
                    // 60ms 节流由机器 hapticMinInterval 承担（验收 ≤16 次/秒）
                    if pendingSelectionHaptic {
                        selectHaptic.selectionChanged()
                        pendingSelectionHaptic = false
                        #if DEBUG
                        debugHapticCount += 1
                        #endif
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

    // MARK: 轨迹命中（线段语义与 M18 TrailHitResolver 对接，docs/38 §2/§3）

    /// VC 注入：当前选中 id 快照（锚点模式取证用）。
    var selectedIDsProvider: () -> Set<String> = { [] }

    /// VC 注入：内容坐标 → 命中 cell 的 assetID（indexPathForItem + dataSource）。
    var hitIDAtContentPoint: (CGPoint) -> String? = { _ in nil }

    /// 一段轨迹推进：from→to 线段取有序命中 id 喂 SlideSelectTrail.consume，净增量落地。
    /// delta 空 → 不置触觉、不触发 apply（G6 闸门；docs/38 §2.3 第 5 行）。
    /// apply 窗口内命中为空：保持线段起点不前进，下一帧重扫同段（M17 T07 语义；
    /// 快照完成后几何自愈，无需帧数上限——endTrail/finishSelection 收口）。
    private func processTrail(from: CGPoint, to: CGPoint) {
        guard machine.state == .dragging || machine.state == .autoScrolling,
              var current = trail else { return }
        let orderedIDs = rowBandHitProvider(from, to)
        if orderedIDs.isEmpty, isApplyingSnapshotProvider() { return }
        let delta = current.consume(orderedIDs)
        trail = current
        lastTrailContentPoint = to
        #if DEBUG
        debugTrailPathCount = current.path.count
        debugLastDelta = "+\(delta.add.count)/-\(delta.remove.count)"
        #endif
        guard !delta.isEmpty else { return }
        pendingSelectionHaptic = true
        applySelectionDelta(delta.add, delta.remove)
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
        // 自动滚动采样（docs/38 §2）：指尖窗口坐标不变、content 坐标随 offset 平移——
        // 滚动前后取同一窗口坐标换算的两点喂轨迹，屏外内容按滚动方向依序入栈（顺序语义）。
        let before = windowToContent(lastFingerWindowPoint)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: target),
                                        animated: false)
        feedEdgeEvents()   // 内容触底/顶后指尖仍在边缘：方向保持，位移由 clampedOffset 钳制
        if let startPoint = before, let endPoint = windowToContent(lastFingerWindowPoint) {
            processTrail(from: startPoint, to: endPoint)   // 滚动推进路径（docs/31 §2.4 每帧重算的轨迹等价）
        }
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
        #if DEBUG
        debugLastEdgeDirection = direction
        #endif
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
        #if DEBUG
        debugLastFingerViewportY = viewportY
        debugViewportBottom = bottom
        #endif
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
