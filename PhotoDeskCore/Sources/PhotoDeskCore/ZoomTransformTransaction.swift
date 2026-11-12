// MARK: - 职责说明：缩放事务边界状态机（docs/28 §4.2/§4.4.2 / M16 P0-1A T01）——
// 手势/动画/复用窗口的事件决策下沉 Core（红线 2：纯 Double/枚举，零 Apple 依赖）。
// 契约：① 拒绝手势 = 直接 return，绝不改写 UIGestureRecognizer.state（App 侧 state 赋值清零）；
// ② 动画用代际 token——复用/新动画开启后旧 completion 一律失效；
// ③ invalidated（复用/旋转/布局/手势总开关关闭）立即回 idle 并清 token；
// ④ sanitizedTransform/isUsableViewport 是 cell 写入层最后一道闸：非有限/零 bounds 一律拒绝。

import Foundation

/// 缩放事务内的手势种类
public enum ZoomGestureKind: Equatable, Sendable {
    case pinch
    case pan
    case doubleTap
}

/// 事务边界状态快照：App 侧 ZoomInteractionController 每次决策前生成
public struct ZoomTransactionSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case interacting
        case animating
    }

    public let phase: Phase
    /// 最近一次动画的代际 token；0 = 无动画
    public let animationToken: Int

    public init(phase: Phase, animationToken: Int = 0) {
        self.phase = phase
        self.animationToken = animationToken
    }

    public static let idle = ZoomTransactionSnapshot(phase: .idle, animationToken: 0)
}

/// 进入事务边界的事件
public enum ZoomTransactionEvent: Equatable, Sendable {
    case gestureBegan(ZoomGestureKind)
    case gestureChanged
    case gestureEnded
    case animationRequested
    case animationCompleted(token: Int)
    case invalidated
}

/// 边界决策。App 侧必须按决策行动：ignoreGesture = 直接 return（不改手势 state）；
/// ignoreCompletion = completion 直接 return；invalidate = 取消动画并立即回 identity。
public enum ZoomTransactionDecision: Equatable, Sendable {
    case beginInteraction
    case continueInteraction
    case ignoreGesture
    case beginAnimation
    case finishAnimation
    case ignoreCompletion
    case settle
    case invalidate
}

public enum ZoomTransformTransaction {
    /// 决策表：唯一事实源。App 侧禁止绕过本表直接改写手势/事务状态。
    public static func decide(state: ZoomTransactionSnapshot,
                              event: ZoomTransactionEvent) -> ZoomTransactionDecision {
        switch event {
        case .gestureBegan(let kind):
            guard kind != .doubleTap else { return .ignoreGesture }
            switch state.phase {
            case .idle: return .beginInteraction
            case .interacting, .animating: return .ignoreGesture
            }
        case .gestureChanged:
            return state.phase == .interacting ? .continueInteraction : .ignoreGesture
        case .gestureEnded:
            return state.phase == .interacting ? .settle : .ignoreGesture
        case .animationRequested:
            return state.phase == .idle ? .beginAnimation : .ignoreGesture
        case .animationCompleted(let token):
            guard state.phase == .animating, token == state.animationToken else { return .ignoreCompletion }
            return .finishAnimation
        case .invalidated:
            return .invalidate
        }
    }

    /// 决策配套的状态推进。beginAnimation 使 token 单调递增（旧 completion 立即失配）。
    public static func advanced(_ state: ZoomTransactionSnapshot,
                                by decision: ZoomTransactionDecision) -> ZoomTransactionSnapshot {
        switch decision {
        case .beginInteraction:
            return ZoomTransactionSnapshot(phase: .interacting, animationToken: state.animationToken)
        case .continueInteraction, .ignoreGesture, .ignoreCompletion:
            return state
        case .settle, .finishAnimation:
            return ZoomTransactionSnapshot(phase: .idle, animationToken: state.animationToken)
        case .beginAnimation:
            return ZoomTransactionSnapshot(phase: .animating, animationToken: state.animationToken + 1)
        case .invalidate:
            return ZoomTransactionSnapshot(phase: .idle, animationToken: 0)
        }
    }

    /// cell 写入层消毒：任一分量非有限或 scale 非正 → nil（调用方必须复位 identity，不得写 CALayer）
    public static func sanitizedTransform(scale: Double,
                                          translationX: Double,
                                          translationY: Double) -> ZoomTransform? {
        guard scale.isFinite, translationX.isFinite, translationY.isFinite, scale > 0 else { return nil }
        return ZoomTransform(scale: scale, translationX: translationX, translationY: translationY)
    }

    /// 视口可用性：0/负/非有限 bounds 一律拒绝写入
    public static func isUsableViewport(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }

    /// geometryState 派生：交互中 = active，动画/收敛 = settling（对齐 ViewerGesturePolicy.ZoomTransactionState）
    public static func geometryState(for phase: ZoomTransactionSnapshot.Phase) -> GeometryState {
        switch phase {
        case .idle: return .idle
        case .interacting: return .active
        case .animating: return .settling
        }
    }

    /// 与 App 侧 ViewerGesturePolicy.ZoomTransactionState 对齐的三态（Core 自带副本，保持零 Apple 依赖）
    public enum GeometryState: Equatable, Sendable {
        case idle
        case active
        case settling
    }
}
