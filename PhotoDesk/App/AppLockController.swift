// MARK: - 职责说明：App 启动锁（docs/09 D06）——冷启动 / 后台超过宽限重新锁；
// UserDefaults + @Published（不用 @AppStorage：ObservableObject 内不自动刷新，docs/09 明令）；
// 解锁走 BiometricGate（生物识别 → 密码兜底）；测试钩子仅 DEBUG（-uiTestingAppLock 强制锁屏）。

import Foundation
import SwiftUI

@MainActor
final class AppLockController: ObservableObject {
    /// 启动锁开关（默认关）
    @Published var lockEnabled: Bool {
        didSet { defaults.set(lockEnabled, forKey: Self.lockEnabledKey) }
    }
    /// 后台宽限秒数（超过则重新锁）
    @Published var graceSeconds: Double {
        didSet { defaults.set(graceSeconds, forKey: Self.graceKey) }
    }
    /// 当前是否处于锁定态（覆盖 AppLockView）
    @Published private(set) var isLocked = false
    /// 解锁失败原因（AppLockView 显示）
    @Published private(set) var failureMessage: String?

    private let gate: BiometricGate
    private let defaults: UserDefaults
    private var backgroundedAt: Date?
    /// 本次会话已解锁（冷启动需要重新验证）
    private var unlockedThisSession = false

    private static let lockEnabledKey = "app.lockEnabled"
    private static let graceKey = "app.lockGraceSeconds"

    init(gate: BiometricGate, defaults: UserDefaults = .standard) {
        self.gate = gate
        self.defaults = defaults
        self.lockEnabled = defaults.object(forKey: Self.lockEnabledKey) as? Bool ?? false
        self.graceSeconds = defaults.object(forKey: Self.graceKey) as? Double ?? 60
        // UI 测试钩子（仅 DEBUG）：强制启动锁屏
        #if DEBUG
        if UITestHooks.enabled("-uiTestingAppLock") {
            isLocked = true
        } else if lockEnabled {
            isLocked = true   // 冷启动即锁（docs/09 D06 §3）
        }
        #else
        if lockEnabled {
            isLocked = true
        }
        #endif
    }

    // MARK: - 生命周期挂钩

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            if let backgroundedAt {
                let elapsed = Date().timeIntervalSince(backgroundedAt)
                self.backgroundedAt = nil
                if lockEnabled, elapsed > graceSeconds {
                    lockNow()
                }
            }
        default:
            break
        }
    }

    /// 立即锁定（设置页「立即锁定」）
    func lockNow() {
        guard lockEnabled else { return }
        isLocked = true
        unlockedThisSession = false
        failureMessage = nil
        gate.lock()
    }

    /// 解锁（生物识别 → 密码兜底；成功后本会话内后台宽限内不再弹）
    func unlock() async {
        failureMessage = nil
        let reason = "解锁照片管家"
        let ok = await gate.unlockIfNeeded(reason: reason)
        if ok {
            isLocked = false
            unlockedThisSession = true
        } else {
            switch gate.status {
            case .failed(let message):
                failureMessage = message
            case .unavailable(let message):
                failureMessage = message
            default:
                failureMessage = "验证未通过"
            }
        }
    }

    /// 解锁是否可用（无生物识别且无密码 → AppLockView 引导去设置）
    var isBiometryAvailable: Bool {
        gate.status != .unavailable("")
    }
}
