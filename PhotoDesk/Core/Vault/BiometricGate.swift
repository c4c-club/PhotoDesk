// MARK: - 职责说明：生物识别门禁（docs/03 §5.7 / docs/05 M3 任务 3.4）——
// LAContext.evaluatePolicy(.deviceOwnerAuthentication)（Face ID / Touch ID / 设备密码兜底），
// 成功后 5 分钟内免重复验证；模拟器（targetEnvironment(simulator)）跳过生物识别直接放行（AGENTS.md §7）；
// 设备完全无密码时放行（docs/03 §5.7 DEBUG 口径）。

import LocalAuthentication
import Foundation

@MainActor
final class BiometricGate: ObservableObject {
    /// 免重复验证宽限（docs/03 §5.7：5 分钟）
    static let graceInterval: TimeInterval = 300

    @Published private(set) var lastUnlockAt: Date = .distantPast

    var isWithinGracePeriod: Bool {
        Date().timeIntervalSince(lastUnlockAt) < Self.graceInterval
    }

    /// - Returns: 是否已解锁（宽限期内直接 true）
    func unlockIfNeeded(reason: String) async -> Bool {
        if isWithinGracePeriod { return true }

        #if targetEnvironment(simulator)
        // 模拟器无 Face ID：直接放行（AGENTS.md §7 常见陷阱）
        lastUnlockAt = Date()
        return true
        #else
        let context = LAContext()
        var evaluationError: NSError?
        // 无密码设备无法评估策略：放行（本 App 无需强制安全；「已隐藏」页非唯一防线）
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            lastUnlockAt = Date()
            return true
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: reason)
            if success {
                lastUnlockAt = Date()
                return true
            }
            return false
        } catch {
            return false
        }
        #endif
    }

    func lock() {
        lastUnlockAt = .distantPast
    }
}
