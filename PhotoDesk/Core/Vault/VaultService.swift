// MARK: - 职责说明：已隐藏相册服务（docs/05 M3 任务 3.4）——
// 门禁状态（BiometricGate）+「已隐藏」范围的资源访问。主网格 includeHiddenAssets = false 已在
// AssetRepository 保证（AGENTS.md §4.2）；本服务只管「进入已隐藏页」的解锁语义。

import Foundation

@MainActor
final class VaultService: ObservableObject {
    let gate = BiometricGate()

    /// 已隐藏页是否处于解锁状态（进页解锁；锁键/离开页面即重新加锁）
    @Published private(set) var isUnlocked = false

    /// Face ID / 设备密码解锁；成功后 5 分钟内免重复验证
    @discardableResult
    func unlock() async -> Bool {
        let ok = await gate.unlockIfNeeded(reason: "解锁「已隐藏」相册，保护你的隐私照片")
        isUnlocked = ok
        return ok
    }

    func lock() {
        isUnlocked = false
        gate.lock()
    }
}
