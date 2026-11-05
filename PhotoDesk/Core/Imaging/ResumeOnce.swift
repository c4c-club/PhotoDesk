// MARK: - 职责说明：单次 resume 保护（docs/13 §3.2 S02；docs/16 M12 R01 附带）——
// ResumeOnce 包住所有 withCheckedContinuation 的恢复点：PhotoKit 的 .opportunistic 多次回调 /
// 取消路径与回调路径同时到达时，只有第一次 resume 生效，其余忽略并记日志，
// 杜绝「SWIFT TASK CONTINUATION MISUSE」闪退。
// ContinuationBox（M12 新增）：attach/finish 两端都可能先到——withTaskCancellationHandler 的
// onCancel 与 PhotoKit 回调竞态时，finish 先到则记录值、attach 立即恢复；取消路径强制 finish(nil)
// 后 PhotoKit 不再回调也不会悬挂（旧版 SWIFT TASK CONTINUATION MISUSE 根因）。

import Foundation
import os.log

private enum ResumeOnceLog {
    static let logger = Logger(subsystem: "com.example.PhotoDesk", category: "imaging")
}

/// 取消安全的单次恢复盒：attach（continuation 侧）与 finish（回调/取消侧）任意顺序安全
final class ContinuationBox<Value> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var pending: Value?
    private var didResume = false

    /// 在 withCheckedContinuation body 内登记 continuation（若 finish 已先到则立即恢复）
    func attach(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if didResume, let pending {
            lock.unlock()
            continuation.resume(returning: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// 恢复（只生效一次）：PhotoKit 回调 / 取消路径强制收口共用
    func finish(_ value: Value) {
        lock.lock()
        if didResume {
            lock.unlock()
            ResumeOnceLog.logger.warning("duplicate finish suppressed (already resumed)")
            return
        }
        didResume = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            pending = value   // finish 先到：attach 时立即恢复
            lock.unlock()
        }
    }

    var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didResume
    }
}

final class ResumeOnce<T> {
    private let lock = NSLock()
    private var didResume = false

    /// 第一次调用恢复 continuation，之后全部忽略（线程安全）
    func resume(_ value: T, _ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        let isFirst = !didResume
        if isFirst { didResume = true }
        lock.unlock()
        if isFirst {
            continuation.resume(returning: value)
        } else {
            ResumeOnceLog.logger.warning("duplicate resume suppressed (continuation already resumed)")
        }
    }

    var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didResume
    }
}
