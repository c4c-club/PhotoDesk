// MARK: - 职责说明：BiometricGate 单元测试（docs/09 D06）——mock evaluator 五态：
// 成功 / 生物识别失败 / 取消 / 不可用（密码兜底）/ 全不可用 + 宽限期 + 离开即锁。

import XCTest
import LocalAuthentication
@testable import PhotoDesk

@MainActor
private final class MockBiometricEvaluator: BiometricEvaluating {
    var biometricsAvailable = true
    var passwordAvailable = true
    var biometricsError: Error?
    var passwordError: Error?
    private(set) var biometricsCalls = 0
    private(set) var passwordCalls = 0

    func canEvaluateBiometrics() -> Bool { biometricsAvailable }

    func evaluateBiometrics(reason: String) async throws {
        biometricsCalls += 1
        if let biometricsError { throw biometricsError }
    }

    func canEvaluatePassword() -> Bool { passwordAvailable }

    func evaluatePassword(reason: String) async throws {
        passwordCalls += 1
        if let passwordError { throw passwordError }
    }
}

@MainActor
final class BiometricGateTests: XCTestCase {

    func testUnlockSuccessViaBiometrics() async {
        let evaluator = MockBiometricEvaluator()
        let gate = BiometricGate(evaluator: evaluator)
        let ok = await gate.unlockIfNeeded(reason: "test")
        XCTAssertTrue(ok)
        XCTAssertEqual(evaluator.biometricsCalls, 1)
        XCTAssertEqual(evaluator.passwordCalls, 0, "生物识别成功不弹密码")
        XCTAssertEqual(gate.status, .unlocked)
    }

    func testBiometricsFailureShowsFailedNotPasswordFallback() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.biometricsError = LAError(.userCancel)
        let gate = BiometricGate(evaluator: evaluator)
        let ok = await gate.unlockIfNeeded(reason: "test")
        XCTAssertFalse(ok)
        XCTAssertEqual(gate.status, .failed("验证已取消"))
        XCTAssertEqual(evaluator.passwordCalls, 0, "取消后不自动连弹密码（用户手动重试）")
    }

    func testPasswordFallbackWhenBiometricsUnavailable() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.biometricsAvailable = false
        let gate = BiometricGate(evaluator: evaluator)
        let ok = await gate.unlockIfNeeded(reason: "test")
        XCTAssertTrue(ok, "生物识别不可用 → 密码兜底")
        XCTAssertEqual(evaluator.passwordCalls, 1)
        XCTAssertEqual(gate.status, .unlocked)
    }

    func testUnavailableWhenNothingConfigured() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.biometricsAvailable = false
        evaluator.passwordAvailable = false
        let gate = BiometricGate(evaluator: evaluator)
        let ok = await gate.unlockIfNeeded(reason: "test")
        XCTAssertFalse(ok)
        guard case .unavailable = gate.status else {
            return XCTFail("应进入 unavailable 态：\(gate.status)")
        }
    }

    func testGracePeriodSkipsReEvaluation() async {
        let evaluator = MockBiometricEvaluator()
        let gate = BiometricGate(evaluator: evaluator)
        _ = await gate.unlockIfNeeded(reason: "first")
        _ = await gate.unlockIfNeeded(reason: "second")
        XCTAssertEqual(evaluator.biometricsCalls, 1, "宽限期内免重复验证")
    }

    func testLockResetsGrace() async {
        let evaluator = MockBiometricEvaluator()
        let gate = BiometricGate(evaluator: evaluator)
        _ = await gate.unlockIfNeeded(reason: "test")
        XCTAssertTrue(gate.isWithinGracePeriod)
        gate.lock()
        XCTAssertFalse(gate.isWithinGracePeriod, "离开即锁")
        XCTAssertEqual(gate.status, .idle)
        _ = await gate.unlockIfNeeded(reason: "again")
        XCTAssertEqual(evaluator.biometricsCalls, 2, "锁定后需重新验证")
    }

    func testBiometryLockoutMessage() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.biometricsError = LAError(.biometryLockout)
        let gate = BiometricGate(evaluator: evaluator)
        _ = await gate.unlockIfNeeded(reason: "test")
        XCTAssertEqual(gate.status, .failed("生物识别已被锁定，请用设备密码解锁后再试"))
    }
}
