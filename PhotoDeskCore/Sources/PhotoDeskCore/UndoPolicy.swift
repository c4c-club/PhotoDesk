// MARK: - 职责说明：撤销窗口与过期判定（docs/03 §5.1 撤销实现 / docs/02 §3.5 撤销体系）——
// 时间来源一律注入（Clock 协议 / now 参数），保证可单测（docs/03 §8）。
// P3：补全 Clock 协议与窗口边界判定；App 侧 UndoCenter 持久化（ActionLog）依赖本模块判定过期。

import Foundation

/// 可注入的时钟（docs/03 §8 可测试性：struct 化 Clock 注入，替代单例全局时间）
public protocol Clock {
    var now: Date { get }
}

/// 系统时钟（生产环境唯一实现；测试注入假时钟）
public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }
}

public struct UndoPolicy {
    /// 撤销窗口时长（秒；默认 5，可设 3/5/10）
    public let window: TimeInterval

    public init(window: TimeInterval) {
        self.window = window
    }

    /// 动作是否已超出撤销窗口（严格大于：恰好等于 window 仍可撤销）
    public func isExpired(since actionDate: Date, now: Date) -> Bool {
        now.timeIntervalSince(actionDate) > window
    }

    /// 动作是否仍在撤销窗口内（便于持久化恢复路径复用）
    public func isWithinWindow(since actionDate: Date, clock: Clock) -> Bool {
        !isExpired(since: actionDate, now: clock.now)
    }
}
