// MARK: - 职责说明：位置恢复状态机（docs/22 §4.4.4）——
// idle → waitingSnapshot → waitingLayout → applying → verifying → done / failed；
// 首帧 bounds=0 保持 waitingLayout，快照缺锚点且索引未完成保持 waitingSnapshot；
// 最多 maxAttempts 次应用/校验，3s 超时 failed；generation 用于拒绝旧代际保存。
// 纯 Foundation / Int / Double / Date，零 UIKit。

import Foundation

public enum PositionRestorePhase: String, Equatable, Sendable {
    case idle
    case waitingSnapshot
    case waitingLayout
    case applying
    case verifying
    case done
    case failed
}

public struct PositionRestoreState: Equatable, Sendable {
    public private(set) var phase: PositionRestorePhase
    public private(set) var attempts: Int
    public let maxAttempts: Int
    public let timeout: TimeInterval
    public private(set) var startedAt: Date?
    public private(set) var generation: Int

    public init(maxAttempts: Int = 3, timeout: TimeInterval = 3) {
        self.phase = .idle
        self.attempts = 0
        self.maxAttempts = max(1, maxAttempts)
        self.timeout = max(0.1, timeout)
        self.startedAt = nil
        self.generation = 0
    }

    /// 恢复流程是否进行中（此期间所有保存必须拒绝）。
    public var isInFlight: Bool {
        switch phase {
        case .waitingSnapshot, .waitingLayout, .applying, .verifying:
            return true
        case .idle, .done, .failed:
            return false
        }
    }

    /// 开始新一轮恢复；旧代际的异步回调必须用 accepts(generation:) 拒绝。
    @discardableResult
    public mutating func begin(generation: Int = 0, now: Date = Date()) -> PositionRestorePhase {
        self.generation = generation
        self.attempts = 0
        self.startedAt = now
        self.phase = .waitingSnapshot
        return phase
    }

    /// 没有可恢复锚点：直接完成（不遮罩）。
    @discardableResult
    public mutating func skip() -> PositionRestorePhase {
        phase = .done
        return phase
    }

    /// applySnapshot completion 后调用：快照为空 → waitingSnapshot；bounds=0 → waitingLayout。
    @discardableResult
    public mutating func snapshotAvailable(hasSections: Bool,
                                           boundsReady: Bool,
                                           now: Date = Date()) -> PositionRestorePhase {
        guard isInFlight else { return phase }
        if timedOut(now: now) { return phase }
        if !hasSections {
            phase = .waitingSnapshot
        } else if !boundsReady {
            phase = .waitingLayout
        } else {
            phase = .applying
        }
        return phase
    }

    /// viewDidLayoutSubviews / viewDidAppear 后调用：锚点缺失且索引未完成 → 继续等快照。
    @discardableResult
    public mutating func layoutAvailable(hasSections: Bool,
                                         boundsReady: Bool,
                                         anchorPresent: Bool,
                                         indexComplete: Bool,
                                         now: Date = Date()) -> PositionRestorePhase {
        guard isInFlight else { return phase }
        if timedOut(now: now) { return phase }
        if !hasSections || (!anchorPresent && !indexComplete) {
            phase = .waitingSnapshot
        } else if !boundsReady {
            phase = .waitingLayout
        } else {
            phase = .applying
        }
        return phase
    }

    /// offset 已写入：进入 verifying，下一轮布局校验。
    @discardableResult
    public mutating func applied() -> PositionRestorePhase {
        if phase == .applying { phase = .verifying }
        return phase
    }

    /// 校验结果：ok → done；失败累计 attempts，达到 maxAttempts → failed，否则回到 applying 重试。
    @discardableResult
    public mutating func verified(ok: Bool) -> PositionRestorePhase {
        guard phase == .verifying else { return phase }
        if ok {
            phase = .done
            return phase
        }
        attempts += 1
        phase = attempts >= maxAttempts ? .failed : .applying
        return phase
    }

    /// 超时检查：仅进行中且超过 timeout 时置 failed；返回是否已超时。
    @discardableResult
    public mutating func timedOut(now: Date = Date()) -> Bool {
        guard isInFlight, let startedAt else { return false }
        guard now.timeIntervalSince(startedAt) >= timeout else { return false }
        phase = .failed
        return true
    }

    /// 外部不可恢复错误（无锚点/布局失败）。
    @discardableResult
    public mutating func fail() -> PositionRestorePhase {
        phase = .failed
        return phase
    }

    /// 旧代际的保存/恢复回调必须被拒绝。
    public func accepts(generation: Int) -> Bool {
        generation == self.generation
    }
}
