// MARK: - 职责说明：位置恢复 v5 单一状态机（docs/25 §5.4 / M15 P0-2，替换 PositionRestoreStateMachine）——
// idle → restoring → applying → verifying → settled / fallback；
// 不设 3s 失败、不设重试上限之外的硬超时：锚点不在当前数据且索引未完成时保持 restoring 等待；
// canSave 只在 settled（I1：恢复完成前任何保存都不得写盘）；verify 失败只重试一次，两次仍失败
// → settled（调用方 DEBUG 记 verify-failed，不阻塞 UI）。纯 Foundation，零 UIKit。

import Foundation

public enum PositionRestorePhaseV5: String, Equatable, Sendable {
    case idle
    case restoring
    case applying
    case verifying
    case settled
    case fallback
}

public struct PositionRestoreMachineV5: Equatable, Sendable {
    public private(set) var phase: PositionRestorePhaseV5
    public private(set) var attempts: Int

    public init() {
        phase = .idle
        attempts = 0
    }

    /// 恢复流程是否进行中（此期间所有保存必须拒绝；settled/fallback 兜底应用也在此列）。
    public var isInFlight: Bool {
        switch phase {
        case .idle, .settled:
            return false
        case .restoring, .applying, .verifying, .fallback:
            return true
        }
    }

    /// v5 门禁：只有恢复彻底完成（settled）才允许写盘。
    public var canSave: Bool { phase == .settled }

    /// 开始恢复：无锚点直接 settled(top)（允许保存）；有锚点进入 restoring。
    @discardableResult
    public mutating func begin(hasAnchor: Bool) -> PositionRestorePhaseV5 {
        attempts = 0
        phase = hasAnchor ? .restoring : .settled
        return phase
    }

    /// 快照/布局/索引状态推进（只在 in-flight 时有意义）：
    /// - bounds 未就绪 → 保持 restoring；
    /// - 锚点在数据但 contentHeight 未达保存值（估算布局未收齐）→ 保持 restoring（等布局稳定）；
    /// - 锚点在数据 → applying；
    /// - 锚点缺失 + 索引未完成 → 保持 restoring（等待全量索引，不失败）；
    /// - 锚点缺失 + 索引完成 → fallback（section/ratio）。
    @discardableResult
    public mutating func dataAvailable(anchorPresent: Bool,
                                       indexComplete: Bool,
                                       boundsReady: Bool,
                                       contentHeightReady: Bool = true) -> PositionRestorePhaseV5 {
        guard isInFlight else { return phase }
        if !boundsReady {
            phase = .restoring
        } else if anchorPresent, contentHeightReady {
            phase = .applying
        } else if anchorPresent {
            // 布局高度未收齐：此时读 minY 会拿估算值，落地必漂——等下一个布局 pass 再试
            phase = .restoring
        } else if !indexComplete {
            phase = .restoring
        } else {
            phase = .fallback
        }
        return phase
    }

    /// offset 已写入（asset 精确落地或 fallback 值）：进入 verifying，下一轮布局校验。
    @discardableResult
    public mutating func applied() -> PositionRestorePhaseV5 {
        if phase == .applying || phase == .fallback {
            phase = .verifying
        }
        return phase
    }

    /// 校验结果：ok → settled；失败累计 attempts，第 1 次失败回 applying 重试（只调 offset），
    /// 第 2 次仍失败 → settled（优雅放弃，不阻塞 UI）。
    @discardableResult
    public mutating func verified(ok: Bool) -> PositionRestorePhaseV5 {
        guard phase == .verifying else { return phase }
        if ok {
            phase = .settled
            return phase
        }
        attempts += 1
        phase = attempts >= 2 ? .settled : .applying
        return phase
    }

    /// fallback 策略已按 section/ratio 落地、无需像素校验时直接收敛。
    @discardableResult
    public mutating func settleFallback() -> PositionRestorePhaseV5 {
        if isInFlight {
            phase = .settled
        }
        return phase
    }

    /// 用户主动接管（月份跳转/回到顶部/手动滚动取消）：立即 settled，此后允许保存。
    @discardableResult
    public mutating func cancel() -> PositionRestorePhaseV5 {
        if isInFlight {
            phase = .settled
        }
        return phase
    }
}
