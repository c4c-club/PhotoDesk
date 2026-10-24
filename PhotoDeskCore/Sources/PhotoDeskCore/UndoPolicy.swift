// MARK: - 职责说明：撤销窗口与过期判定（docs/03 §5.1 撤销实现 / docs/02 §3.5 撤销体系）。
// 时间来源一律由调用方注入（now 由 Clock/Date 参数传入），保证可单测（docs/03 §8）。
// TODO(P1): 过期判定 + 撤销栈条目结构（配合 App 侧 UndoCenter / Core Data ActionLog）。

import Foundation

public struct UndoPolicy {
    /// 撤销窗口时长（秒；默认 5，可设 3/5/10）
    public let window: TimeInterval

    public init(window: TimeInterval) {
        self.window = window
    }

    /// 动作是否已超出撤销窗口
    public func isExpired(since actionDate: Date, now: Date) -> Bool {
        // TODO(P1): now.timeIntervalSince(actionDate) > window
        return false
    }
}
