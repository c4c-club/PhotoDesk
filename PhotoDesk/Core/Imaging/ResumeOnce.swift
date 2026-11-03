// MARK: - 职责说明：单次 resume 保护（docs/13 §3.2 S02）——
// 包住所有 withCheckedContinuation 的恢复点：PhotoKit 的 .opportunistic 多次回调 /
// 取消路径与回调路径同时到达时，只有第一次 resume 生效，其余忽略并记日志，
// 杜绝「SWIFT TASK CONTINUATION MISUSE」闪退。

import Foundation
import os.log

final class ResumeOnce<T> {
    private let lock = NSLock()
    private var didResume = false
    private static let logger = Logger(subsystem: "com.example.PhotoDesk", category: "imaging")

    /// 第一次调用恢复 continuation，之后全部忽略（线程安全）
    func resume(_ value: T, _ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        let isFirst = !didResume
        if isFirst { didResume = true }
        lock.unlock()
        if isFirst {
            continuation.resume(returning: value)
        } else {
            Self.logger.warning("duplicate resume suppressed (continuation already resumed)")
        }
    }

    var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didResume
    }
}
