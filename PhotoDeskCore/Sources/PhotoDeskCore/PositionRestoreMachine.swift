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

// MARK: - 位置恢复 v6 单一状态机（docs/28 §5.4 / M16 T03）——
// idle → loading → waitingForWindow → waitingForHead → applying → verifying → settled；
// 任一步失败 → fallback（锚点 cell 顶部 / section / ratio）。v6 相对 v5 的硬化：
// ① windowStart > 0 必进 waitingForHead（禁止直接 applying，§5.4 关键门禁）；
// ② waitingForHead 结束条件 = isIndexComplete && headInsertGeneration 连续两轮不变；
// ③ applying 只允许一次，重复调用直接返回；④ verify 两次失败 → fallback（绝不假 settled）；
// ⑤ 锚点缺失 + 索引完成 → fallback；canSave 仍只在 settled。

public enum PositionRestorePhaseV6: String, Equatable, Sendable {
    case idle
    case loading
    case waitingForWindow
    case waitingForHead
    case applying
    case verifying
    case settled
    case fallback
}

public struct PositionRestoreMachineV6: Equatable, Sendable {
    public private(set) var phase: PositionRestorePhaseV6
    public private(set) var attempts: Int
    /// applying 是否已经执行（v6：入口只允许一次）
    public private(set) var hasApplied: Bool
    private var lastHeadGeneration: Int
    private var headStableRounds: Int

    public init() {
        phase = .idle
        attempts = 0
        hasApplied = false
        lastHeadGeneration = Int.min
        headStableRounds = 0
    }

    /// 恢复流程是否进行中（此期间所有保存必须拒绝）。
    public var isInFlight: Bool {
        switch phase {
        case .idle, .settled:
            return false
        case .loading, .waitingForWindow, .waitingForHead, .applying, .verifying, .fallback:
            return true
        }
    }

    /// v6 门禁：只有恢复彻底完成（settled）才允许写盘。
    public var canSave: Bool { phase == .settled }

    /// 开始恢复：无锚点直接 settled(top)（允许保存）；有锚点进入 loading（等首批窗口）。
    @discardableResult
    public mutating func begin(hasAnchor: Bool) -> PositionRestorePhaseV6 {
        attempts = 0
        hasApplied = false
        lastHeadGeneration = Int.min
        headStableRounds = 0
        phase = hasAnchor ? .loading : .settled
        return phase
    }

    /// 首批窗口就绪（fetchFirstBatch 完成，windowStart 已知）：
    /// - bounds 未就绪 → 保持 waitingForWindow；
    /// - windowStart > 0 → waitingForHead（头部批次还会前插，禁止直接 applying）；
    /// - windowStart == 0 → 无 head 回填，直接 applying。
    @discardableResult
    public mutating func windowResolved(windowStart: Int, boundsReady: Bool) -> PositionRestorePhaseV6 {
        guard isInFlight, phase == .loading || phase == .waitingForWindow else { return phase }
        if !boundsReady {
            phase = .waitingForWindow
        } else if windowStart > 0 {
            phase = .waitingForHead
        } else {
            phase = .applying
        }
        return phase
    }

    /// 每个 head 批次 / 每轮恢复尝试后的代际推进：generation 连续两轮不变且索引完成 → applying。
    @discardableResult
    public mutating func headProgress(generation: Int, indexComplete: Bool) -> PositionRestorePhaseV6 {
        guard phase == .waitingForHead else { return phase }
        if generation == lastHeadGeneration {
            headStableRounds += 1
        } else {
            headStableRounds = 0
            lastHeadGeneration = generation
        }
        if indexComplete && headStableRounds >= 1 {
            phase = .applying
        }
        return phase
    }

    /// 锚点暂不在数据：索引未完成 → 保持当前等待态（I4 无硬超时）；索引完成 → fallback。
    @discardableResult
    public mutating func anchorMissing(indexComplete: Bool) -> PositionRestorePhaseV6 {
        guard isInFlight else { return phase }
        if indexComplete {
            phase = .fallback
        }
        return phase
    }

    /// applying 入口：只允许一次；重复调用直接返回（不重置 attempts / 代际追踪）。
    @discardableResult
    public mutating func apply() -> PositionRestorePhaseV6 {
        guard phase == .applying, !hasApplied else { return phase }
        hasApplied = true
        return phase
    }

    /// offset 已写入（asset 精确落地或 fallback 值）：进入 verifying，下一轮布局校验。
    @discardableResult
    public mutating func applied() -> PositionRestorePhaseV6 {
        if phase == .applying || phase == .fallback {
            phase = .verifying
        }
        return phase
    }

    /// 校验结果：ok → settled；失败累计 attempts，第 1 次失败回 applying 重试（只调 offset），
    /// 第 2 次仍失败 → fallback（v6 硬化：绝不假 settled，docs/28 §5.5 步骤 6）。
    @discardableResult
    public mutating func verified(ok: Bool) -> PositionRestorePhaseV6 {
        guard phase == .verifying else { return phase }
        if ok {
            phase = .settled
            return phase
        }
        attempts += 1
        phase = attempts >= 2 ? .fallback : .applying
        return phase
    }

    /// fallback（锚点 cell 顶部 / section / ratio）已落地、无需像素校验时直接收敛。
    @discardableResult
    public mutating func settleFallback() -> PositionRestorePhaseV6 {
        if isInFlight {
            phase = .settled
        }
        return phase
    }

    /// 用户主动接管（月份跳转/回到顶部/手动滚动取消）：立即 settled，此后允许保存。
    @discardableResult
    public mutating func cancel() -> PositionRestorePhaseV6 {
        if isInFlight {
            phase = .settled
        }
        return phase
    }
}
