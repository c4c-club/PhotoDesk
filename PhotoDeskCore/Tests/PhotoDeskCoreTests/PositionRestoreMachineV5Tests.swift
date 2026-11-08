// MARK: - PositionRestoreMachineV5Tests：位置恢复 v5 单一状态机（docs/25 §5.4 / M15 P0-2）——
// 不变量：① canSave 只在 settled；② 无锚点 → settled(top)；③ 锚点缺失+索引未完成 → 保持 restoring
// （不设 3s 超时，不做失败）；④ 索引完成仍缺锚点 → fallback；⑤ verify 失败只重试一次，
// 两次仍失败 → settled（不阻塞 UI）；⑥ 用户接管 cancel → settled。

import XCTest
@testable import PhotoDeskCore

final class PositionRestoreMachineV5Tests: XCTestCase {
    func testInitialPhaseIdleAndCannotSave() {
        let machine = PositionRestoreMachineV5()
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.canSave, "idle 未完成恢复，禁止保存")
        XCTAssertFalse(machine.isInFlight)
    }

    func testBeginWithoutAnchorSettlesImmediately() {
        var machine = PositionRestoreMachineV5()
        let phase = machine.begin(hasAnchor: false)
        XCTAssertEqual(phase, .settled)
        XCTAssertTrue(machine.canSave, "无锚点 → settled(top)，允许保存")
        XCTAssertFalse(machine.isInFlight)
    }

    func testBeginWithAnchorRestoringBlocksSave() {
        var machine = PositionRestoreMachineV5()
        let phase = machine.begin(hasAnchor: true)
        XCTAssertEqual(phase, .restoring)
        XCTAssertTrue(machine.isInFlight)
        XCTAssertFalse(machine.canSave, "I1：恢复完成前任何保存都不得写盘")
    }

    func testBoundsNotReadyKeepsRestoring() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        let phase = machine.dataAvailable(anchorPresent: true, indexComplete: true, boundsReady: false)
        XCTAssertEqual(phase, .restoring, "首帧 bounds=0 必须保持等待，不得失败")
        XCTAssertFalse(machine.canSave)
    }

    func testAnchorMissingKeepsRestoringWhileIndexIncomplete() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        let phase = machine.dataAvailable(anchorPresent: false, indexComplete: false, boundsReady: true)
        XCTAssertEqual(phase, .restoring, "I4：锚点不在当前数据且索引未完成 → 保持等待，不得硬超时失败")
        XCTAssertFalse(machine.canSave)
    }

    func testAnchorMissingWithCompleteIndexFallsBack() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        let phase = machine.dataAvailable(anchorPresent: false, indexComplete: true, boundsReady: true)
        XCTAssertEqual(phase, .fallback, "索引完成仍无锚点 → section/ratio fallback")
        XCTAssertTrue(machine.isInFlight, "fallback 应用前仍在恢复中")
        XCTAssertFalse(machine.canSave)
    }

    func testFallbackSettlesAfterAppliedAndVerified() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: false, indexComplete: true, boundsReady: true)
        XCTAssertEqual(machine.applied(), .verifying, "fallback 写 offset 后同样走 verify")
        XCTAssertEqual(machine.verified(ok: true), .settled)
        XCTAssertTrue(machine.canSave)
    }

    func testAnchorPresentMovesToApplying() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        let phase = machine.dataAvailable(anchorPresent: true, indexComplete: false, boundsReady: true)
        XCTAssertEqual(phase, .applying)
    }

    func testAppliedMovesToVerifying() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: true, indexComplete: false, boundsReady: true)
        XCTAssertEqual(machine.applied(), .verifying)
    }

    func testVerifiedOkSettles() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: true, indexComplete: false, boundsReady: true)
        machine.applied()
        let phase = machine.verified(ok: true)
        XCTAssertEqual(phase, .settled)
        XCTAssertTrue(machine.canSave)
        XCTAssertFalse(machine.isInFlight)
    }

    func testVerifyFailureRetriesOnce() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: true, indexComplete: false, boundsReady: true)
        machine.applied()
        XCTAssertEqual(machine.verified(ok: false), .applying, "第一次 verify 失败 → 重试一次（只调 offset）")
        XCTAssertEqual(machine.attempts, 1)
        XCTAssertFalse(machine.canSave)
    }

    func testSecondVerifyFailureSettlesGracefully() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: true, indexComplete: false, boundsReady: true)
        machine.applied()
        machine.verified(ok: false)
        XCTAssertEqual(machine.phase, .applying, "重试：调用方只调 offset，随后 applied() 重新进入 verify")
        machine.applied()
        let phase = machine.verified(ok: false)
        XCTAssertEqual(phase, .settled, "两次仍失败 → settled（DEBUG 记 verify-failed），不阻塞 UI")
        XCTAssertEqual(machine.attempts, 2)
        XCTAssertTrue(machine.canSave)
    }

    func testSettleFallbackCompletes() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: false, indexComplete: true, boundsReady: true)
        XCTAssertEqual(machine.settleFallback(), .settled)
        XCTAssertTrue(machine.canSave)
    }

    func testCancelFromRestoringSettles() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: true)
        machine.dataAvailable(anchorPresent: false, indexComplete: false, boundsReady: true)
        machine.cancel()
        XCTAssertEqual(machine.phase, .settled, "用户主动月份跳转/接管 → cancelRestore → settled")
        XCTAssertTrue(machine.canSave)
    }

    func testRepeatedBeginOnlyFromIdleSemantics() {
        var machine = PositionRestoreMachineV5()
        machine.begin(hasAnchor: false)
        XCTAssertTrue(machine.canSave)
        // settled 后再次 begin（queryKey 未变时协调器不会调用；状态机自身允许重入）
        machine.begin(hasAnchor: true)
        XCTAssertFalse(machine.canSave)
    }
}
