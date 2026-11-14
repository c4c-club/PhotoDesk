// MARK: - 职责说明：多选手势纯逻辑状态机（M17 T02，docs/32 §2.2）——
// idle → pressing → armed → dragging ⇄ autoScrolling → ending → idle；
// 长按进入 / 方向锁 / 滚动让位 / 边缘自动滚动判定全部收口在此（Foundation-only，可 Docker 单测），
// 触点用 Core 自有 GridPoint（Double 版）：Foundation 导入的 CGPoint 在 Darwin 不满足 Equatable 合成，
// 且红线 2 禁止几何类型进 Core；
// App 层（T05 接线）只做 UIKit 事件映射与效果执行。
// 事件在 docs/32 §2.2 六事件之外补 edgeEntered(direction:)/edgeExited：状态表第 7/8 行
// 「指尖进/离边缘」的事件载体——边缘检测属于 App 层（知晓视口几何），机器只做判定与配对。
// 迁移契约（每条都有单测，SelectionGestureMachineTests）：
// - touchDown：hitID 为 nil 或触点非有限 → 忽略；否则入 pressing 并记录真实按下点（G3 锚点取证）。
// - holdElapsed：now − 按下 ≥ longPressDuration 且累计位移 ≤ allowableMovement 才 armed；
//   副作用 [haptic(.impactLight), enterSelection(anchorID:), beginMarquee]（表第 2 行，0 尺寸选框）。
// - pressing moved：累计距离 ≥ directionLockDistance 时定方向——横向占优（|dx| > |dy|·horizontalRatio）
//   → dragging，未在多选时先 enterSelection（表第 3 行「必要时先进入多选」，App 侧最终把关）；
//   纵向占优（|dy| ≥ |dx|·horizontalRatio）→ idle + releaseScroll（让位滚动，G2）。
//   累计位移 > allowableMovement 即判长按死亡（对角未决时仍 pressing，但不再响应 holdElapsed）。
// - armed moved：累计距离 ≥ activationDistance → dragging（框选开始，任意方向——表第 6 行无
//   方向限定：长按已表达选择意图，T05 修正；0 尺寸选框已在 armed 就位）。
// - dragging/autoScrolling moved → updateMarquee + haptic(.selectionChanged)（受 hapticMinInterval
//   节流；App 侧以命中集合变化为最终闸门，G6）。反向拖逐帧上报，收缩由调用方计算（卡内附加 3）。
// - edgeEntered(d)：dragging → autoScrolling + startAutoScroll(d)；autoScrolling 中反向进边缘 → 换向重启；
//   edgeExited：autoScrolling → dragging + stopAutoScroll（进出严格配对，无泄漏）。
// - ended/cancelled：armed/dragging/autoScrolling 收尾（stopAutoScroll → endMarquee → releaseScroll）
//   后进 .ending，下一事件先复位 idle 再正常处理（表第 9 行 ending → idle）；
//   idle/pressing 无活动资源，直接复位（短按交 tap，表第 5 行）。
// - 非有限 dx/dy/now/触点：异常安全路径直接回 idle（不走 ending），带资源先收尾（卡内附加 5）。
// 抬手兜底：pressing + ended 时长若已达长按阈值（计时器迟到）按原生语义进入多选并选中锚点。
// 所有阈值只从 SelectionGestureConfig 取，禁止散落数字。

import Foundation

public enum SelectionGestureState: Equatable, Sendable {
    case idle, pressing, armed, dragging, autoScrolling, ending
}

public enum SelectionGestureHaptic: Equatable, Sendable {
    case impactLight
    case selectionChanged
}

public enum SelectionGestureEvent: Equatable, Sendable {
    case touchDown(point: GridPoint, hitID: String?)
    case holdElapsed
    case moved(dx: Double, dy: Double)
    case scrollStarted
    case ended
    case cancelled
    /// App 层检测到指尖进入边缘区（direction: +1 底缘 / -1 顶缘）；仅 dragging/autoScrolling 有效。
    case edgeEntered(direction: Int)
    /// App 层检测到指尖离开边缘区。
    case edgeExited
}

public struct SelectionGestureConfig: Equatable, Sendable {
    public var longPressDuration: TimeInterval = 0.28
    public var allowableMovement: Double = 8
    public var directionLockDistance: Double = 8
    public var horizontalRatio: Double = 1.2
    public var activationDistance: Double = 6
    public var hapticMinInterval: TimeInterval = 0.06

    public init() {}
}

public enum SelectionGestureEffect: Equatable, Sendable {
    case enterSelection(anchorID: String)
    case beginMarquee
    case updateMarquee
    case endMarquee
    case releaseScroll
    case haptic(kind: SelectionGestureHaptic)
    case startAutoScroll(direction: Int)
    case stopAutoScroll
}

public struct SelectionGestureMachine: Sendable {
    public var config: SelectionGestureConfig
    /// App 侧注入：当前是否已处于多选模式（表第 3 行「必要时先进入多选」的判断输入）。
    public var isSelectionModeActive = false
    public private(set) var state: SelectionGestureState = .idle
    /// 本次手势的真实按下点（G3：框选起点必须是按下点而非 pan 触发点）；收尾后为 nil。
    public private(set) var pressPoint: GridPoint?

    private var pressStartTime: TimeInterval = 0
    private var anchorID: String?
    private var totalDX: Double = 0
    private var totalDY: Double = 0
    private var longPressDead = false
    private var scrollLocked = false
    private var autoScrollDirection: Int?
    private var lastHapticAt: TimeInterval = -.infinity

    public init(config: SelectionGestureConfig = SelectionGestureConfig()) {
        self.config = config
    }

    /// 唯一入口：事件 + 当前时间 → 状态迁移 + 有序副作用。所有时间语义由 now 驱动，机器不自取时钟。
    public mutating func handle(_ event: SelectionGestureEvent,
                                now: TimeInterval) -> [SelectionGestureEffect] {
        guard now.isFinite else { return safetyReset() }
        if state == .ending {
            state = .idle   // 表第 9 行 ending → idle：复位后才处理新事件
        }
        switch event {
        case .touchDown(let point, let hitID):
            return handleTouchDown(point: point, hitID: hitID, now: now)
        case .holdElapsed:
            return handleHoldElapsed(now: now)
        case .moved(let dx, let dy):
            return handleMoved(dx: dx, dy: dy, now: now)
        case .scrollStarted:
            return handleScrollStarted()
        case .ended, .cancelled:
            return handleEnded(now: now)
        case .edgeEntered(let direction):
            return handleEdgeEntered(direction: direction)
        case .edgeExited:
            return handleEdgeExited()
        }
    }

    // MARK: - 触点与长按

    private mutating func handleTouchDown(point: GridPoint,
                                          hitID: String?,
                                          now: TimeInterval) -> [SelectionGestureEffect] {
        guard state == .idle, let hitID, point.x.isFinite, point.y.isFinite else { return [] }
        state = .pressing
        pressPoint = point
        pressStartTime = now
        anchorID = hitID
        totalDX = 0
        totalDY = 0
        longPressDead = false
        scrollLocked = false
        autoScrollDirection = nil
        return []
    }

    private mutating func handleHoldElapsed(now: TimeInterval) -> [SelectionGestureEffect] {
        guard state == .pressing else { return [] }
        guard canStillLongPress(now: now) else { return [] }
        state = .armed
        let anchor = anchorID ?? ""
        var effects: [SelectionGestureEffect] = []
        if now - lastHapticAt >= config.hapticMinInterval {
            effects.append(.haptic(kind: .impactLight))
            lastHapticAt = now
        }
        effects.append(.enterSelection(anchorID: anchor))
        effects.append(.beginMarquee)
        return effects
    }

    /// 长按资格：时长达标、位移未超 allowableMovement、未判死。
    private func canStillLongPress(now: TimeInterval) -> Bool {
        now - pressStartTime >= config.longPressDuration
            && !longPressDead
            && displacement() <= config.allowableMovement
    }

    private func displacement() -> Double {
        (totalDX * totalDX + totalDY * totalDY).squareRoot()
    }

    // MARK: - 移动与方向锁

    private mutating func handleMoved(dx: Double, dy: Double,
                                      now: TimeInterval) -> [SelectionGestureEffect] {
        guard dx.isFinite, dy.isFinite else { return safetyReset() }
        switch state {
        case .pressing:
            totalDX += dx
            totalDY += dy
            let distance = displacement()
            if distance > config.allowableMovement { longPressDead = true }
            guard distance >= config.directionLockDistance else { return [] }
            if abs(totalDX) > abs(totalDY) * config.horizontalRatio {
                // 表第 3 行：横向锁定 → dragging，必要时先进入多选
                state = .dragging
                scrollLocked = true
                var effects: [SelectionGestureEffect] = []
                if !isSelectionModeActive, let anchor = anchorID {
                    effects.append(.enterSelection(anchorID: anchor))
                }
                effects.append(.beginMarquee)
                return effects
            }
            if abs(totalDY) >= abs(totalDX) * config.horizontalRatio {
                // 表第 4 行：纵向占优 → 失败回 idle，交还滚动
                state = .idle
                resetGesture()
                return [.releaseScroll]
            }
            return []   // 对角未决：继续 pressing 等方向明朗
        case .armed:
            totalDX += dx
            totalDY += dy
            guard displacement() >= config.activationDistance else { return [] }
            // 表第 6 行：armed moved → dragging（框选开始，任意方向——表无方向限定：长按已表达
            // 选择意图，「长按后拖到第 5 行」「底缘自动滚动」都依赖纵向拖框，T05 修正）
            state = .dragging
            scrollLocked = true
            return marqueeUpdateEffects(now: now)
        case .dragging, .autoScrolling:
            // 表第 7 行：逐帧重算命中；反向拖同样上报（收缩由调用方计算）
            return marqueeUpdateEffects(now: now)
        default:
            return []
        }
    }

    private mutating func marqueeUpdateEffects(now: TimeInterval) -> [SelectionGestureEffect] {
        var effects: [SelectionGestureEffect] = [.updateMarquee]
        if now - lastHapticAt >= config.hapticMinInterval {
            effects.append(.haptic(kind: .selectionChanged))
            lastHapticAt = now
        }
        return effects
    }

    // MARK: - 滚动让位

    private mutating func handleScrollStarted() -> [SelectionGestureEffect] {
        switch state {
        case .pressing:
            state = .idle
            resetGesture()
            return []
        case .armed:
            state = .idle
            resetGesture()
            return [.endMarquee]
        case .dragging:
            state = .idle
            resetGesture()
            return [.endMarquee, .releaseScroll]
        case .autoScrolling:
            state = .idle
            resetGesture()
            return [.stopAutoScroll, .endMarquee, .releaseScroll]
        default:
            return []
        }
    }

    // MARK: - 边缘自动滚动（表第 8/9 行）

    private mutating func handleEdgeEntered(direction: Int) -> [SelectionGestureEffect] {
        guard direction != 0 else { return [] }
        switch state {
        case .dragging:
            state = .autoScrolling
            autoScrollDirection = direction
            return [.startAutoScroll(direction: direction)]
        case .autoScrolling:
            guard autoScrollDirection != direction else { return [] }
            autoScrollDirection = direction
            return [.startAutoScroll(direction: direction)]
        default:
            return []
        }
    }

    private mutating func handleEdgeExited() -> [SelectionGestureEffect] {
        guard state == .autoScrolling else { return [] }
        state = .dragging
        autoScrollDirection = nil
        return [.stopAutoScroll]
    }

    // MARK: - 收尾（表第 9/10 行）

    private mutating func handleEnded(now: TimeInterval) -> [SelectionGestureEffect] {
        switch state {
        case .pressing:
            // 计时器迟到的兜底：时长已达长按阈值且位移合格 → 抬手进入多选（原生语义）
            if canStillLongPress(now: now), let anchor = anchorID {
                state = .idle
                resetGesture()
                var effects: [SelectionGestureEffect] = []
                if now - lastHapticAt >= config.hapticMinInterval {
                    effects.append(.haptic(kind: .impactLight))
                    lastHapticAt = now
                }
                effects.append(.enterSelection(anchorID: anchor))
                return effects
            }
            state = .idle
            resetGesture()
            return []
        case .armed:
            state = .ending
            resetGesture()
            return [.endMarquee]
        case .dragging:
            state = .ending
            resetGesture()
            return [.endMarquee, .releaseScroll]
        case .autoScrolling:
            state = .ending
            resetGesture()
            return [.stopAutoScroll, .endMarquee, .releaseScroll]
        default:
            return []
        }
    }

    /// 异常安全路径：非有限输入直接复位 idle（不走 ending 两段），带资源先收尾。
    private mutating func safetyReset() -> [SelectionGestureEffect] {
        var effects: [SelectionGestureEffect] = []
        switch state {
        case .armed:
            effects = [.endMarquee]
        case .dragging:
            effects = scrollLocked ? [.endMarquee, .releaseScroll] : [.endMarquee]
        case .autoScrolling:
            effects = [.stopAutoScroll, .endMarquee, .releaseScroll]
        default:
            break
        }
        state = .idle
        resetGesture()
        return effects
    }

    /// 手势上下文清零（触觉节流时间戳保留——它是限速器，不是手势状态）。
    private mutating func resetGesture() {
        pressPoint = nil
        anchorID = nil
        totalDX = 0
        totalDY = 0
        longPressDead = false
        scrollLocked = false
        autoScrollDirection = nil
    }
}
