// MARK: - 职责说明：生物识别门禁（docs/03 §5.7；docs/09 D06 重做）★——
// 评估顺序：生物识别（.deviceOwnerAuthenticationWithBiometrics）→ 失败/不可用 → 设备密码兜底
//（.deviceOwnerAuthentication）→ 都不可用 = .unavailable（UI 给「去系统设置」）。
// 协议化（BiometricEvaluating）供单测注入 mock；5 分钟宽限；离开即锁（lock()）。
// 测试钩子仅 DEBUG + 启动参数（-uiTestingFaceIDBypass / -uiTestingFaceIDFailure），Release 绝不绕过；
// 模拟器不再静默放行（显示不可用 + 允许测试参数绕过，docs/09 D06）。

import LocalAuthentication
import Foundation

/// 生物评估抽象（单测 mock 注入点）
@MainActor
protocol BiometricEvaluating: AnyObject {
    /// 设备能否评估生物识别（Face ID / Touch ID 已注册）
    func canEvaluateBiometrics() -> Bool
    /// 生物识别（失败/取消/不可用抛 LAError）
    func evaluateBiometrics(reason: String) async throws
    /// 设备密码兜底是否可用
    func canEvaluatePassword() -> Bool
    /// 设备密码兜底
    func evaluatePassword(reason: String) async throws
}

/// 真实实现：LAContext（每次评估新建，避免缓存已失效状态）
@MainActor
final class LAContextEvaluator: BiometricEvaluating {
    func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func evaluateBiometrics(reason: String) async throws {
        let context = LAContext()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing error ?? LAError(.authenticationFailed))
                }
            }
        }
    }

    func canEvaluatePassword() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func evaluatePassword(reason: String) async throws {
        let context = LAContext()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing error ?? LAError(.authenticationFailed))
                }
            }
        }
    }
}

@MainActor
final class BiometricGate: ObservableObject {
    /// 免重复验证宽限（docs/03 §5.7：5 分钟）
    static let graceInterval: TimeInterval = 300

    /// 门禁状态（UI 显示失败原因 / 不可用引导）
    enum GateStatus: Equatable {
        case idle
        case unlocking
        case unlocked
        case failed(String)         // 用户取消 / 验证失败（可重试）
        case unavailable(String)    // 设备没有生物识别与密码（引导去设置）
    }

    @Published private(set) var lastUnlockAt: Date = .distantPast
    @Published private(set) var status: GateStatus = .idle

    private let evaluator: BiometricEvaluating

    init(evaluator: BiometricEvaluating = LAContextEvaluator()) {
        self.evaluator = evaluator
    }

    var isWithinGracePeriod: Bool {
        Date().timeIntervalSince(lastUnlockAt) < Self.graceInterval
    }

    var isUnlocked: Bool { isWithinGracePeriod }

    /// - Returns: 是否已解锁（宽限期内直接 true；失败/取消 false，status 带原因）
    @discardableResult
    func unlockIfNeeded(reason: String) async -> Bool {
        if isWithinGracePeriod {
            status = .unlocked
            return true
        }
        status = .unlocking

        // 测试钩子：仅 DEBUG + 启动参数（docs/09 D06 §6）
        #if DEBUG
        if UITestHooks.enabled("-uiTestingFaceIDBypass") {
            markUnlocked()
            return true
        }
        if UITestHooks.enabled("-uiTestingFaceIDFailure") {
            status = .failed("Face ID 验证失败（测试注入）")
            return false
        }
        #endif

        #if targetEnvironment(simulator)
        // 模拟器无 Face ID：不再静默放行（docs/09 D06）；UI 测试走 -uiTestingFaceIDBypass
        if !evaluator.canEvaluateBiometrics() {
            status = .unavailable("模拟器不支持 Face ID。真机将弹出系统验证；UI 测试请加 -uiTestingFaceIDBypass 参数。")
            return false
        }
        #endif

        // 1. 生物识别优先
        if evaluator.canEvaluateBiometrics() {
            do {
                try await evaluator.evaluateBiometrics(reason: reason)
                markUnlocked()
                return true
            } catch {
                // 用户取消 / 失败 → 明确失败态（不直接掉到密码，避免连弹两窗；用户可手动重试或用密码）
                status = .failed(Self.message(for: error))
                return false
            }
        }
        // 2. 密码兜底
        if evaluator.canEvaluatePassword() {
            do {
                try await evaluator.evaluatePassword(reason: reason)
                markUnlocked()
                return true
            } catch {
                status = .failed(Self.message(for: error))
                return false
            }
        }
        // 3. 都不可用
        status = .unavailable("此设备没有设置 Face ID / Touch ID / 密码，无法验证身份")
        return false
    }

    func lock() {
        lastUnlockAt = .distantPast
        status = .idle
    }

    /// 模拟器演示路径（仅模拟器编译）：标记解锁（AGENTS §7：模拟器无 Face ID 硬件）
    #if targetEnvironment(simulator)
    func markSimulatorBypass() {
        markUnlocked()
    }
    #endif

    private func markUnlocked() {
        lastUnlockAt = Date()
        status = .unlocked
    }

    private static func message(for error: Error) -> String {
        if let laError = error as? LAError {
            switch laError.code {
            case .userCancel, .userFallback, .systemCancel, .appCancel:
                return "验证已取消"
            case .biometryLockout:
                return "生物识别已被锁定，请用设备密码解锁后再试"
            default:
                break
            }
        }
        return "验证失败，请重试"
    }
}
