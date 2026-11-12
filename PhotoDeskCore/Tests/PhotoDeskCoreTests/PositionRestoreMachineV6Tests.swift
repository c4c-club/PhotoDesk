// MARK: - PositionRestoreMachineV6Tests：位置恢复 v6 单一状态机（docs/28 §5.4 / M16 T03）——
// 不变量：① canSave 只在 settled；② 无锚点 → settled；③ windowStart > 0 必进 waitingForHead
//（禁止直接 applying）；④ waitingForHead 结束 = isIndexComplete && headGeneration 连续两轮不变；
// ⑤ applying 只允许一次（重复调用直接返回）；⑥ verify nil/失败：第一次回 applying 重试，
// 第二次 → fallback（v6 硬化：绝不假 settled）；⑦ 锚点缺失+索引完成 → fallback。

import XCTest
@testable import PhotoDeskCore

final class PositionRestoreMachineV6Tests: XCTestCase {
    func testInitialPhaseIdleAndCannotSave() {
        let machine = PositionRestoreMachineV6()
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.canSave, "idle 未完成恢复，禁止保存")
        XCTAssertFalse(machine.isInFlight)
    }

    func testBeginWithoutAnchorSettlesImmediately() {
        var machine = PositionRestoreMachineV6()
        XCTAssertEqual(machine.begin(hasAnchor: false), .settled)
        XCTAssertTrue(machine.canSave, "无锚点 → settled(top)，允许保存")
        XCTAssertFalse(machine.isInFlight)
    }

    func testBeginWithAnchorEntersLoading() {
        var machine = PositionRestoreMachineV6()
        XCTAssertEqual(machine.begin(hasAnchor: true), .loading, "v6：begin 后先 loading，等首批窗口")
        XCTAssertTrue(machine.isInFlight)
        XCTAssertFalse(machine.canSave, "I1：恢复完成前任何保存都不得写盘")
    }

    func testBoundsNotReadyKeepsWaitingForWindow() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        XCTAssertEqual(machine.windowResolved(windowStart: 0, boundsReady: false), .waitingForWindow,
                       "首帧 bounds=0 必须保持等待，不得失败")
        XCTAssertFalse(machine.canSave)
    }

    func testZeroWindowGoesStraightToApplying() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        XCTAssertEqual(machine.windowResolved(windowStart: 0, boundsReady: true), .applying,
                       "windowStart == 0：无 head 回填，直接 applying")
    }

    func testNonZeroWindowMustEnterWaitingForHead() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        XCTAssertEqual(machine.windowResolved(windowStart: 250, boundsReady: true), .waitingForHead,
                       "§5.4：windowStart > 0 必进 waitingForHead，禁止直接 applying")
        XCTAssertFalse(machine.canSave)
    }

    func testFirstHeadProgressReportKeepsWaiting() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 250, boundsReady: true)
        XCTAssertEqual(machine.headProgress(generation: 3, indexComplete: true), .waitingForHead,
                       "第一轮代际报告只有一轮稳定，不得放行")
    }

    func testTwoStableRoundsWithCompleteIndexEnterApplying() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 250, boundsReady: true)
        machine.headProgress(generation: 3, indexComplete: true)
        XCTAssertEqual(machine.headProgress(generation: 3, indexComplete: true), .applying,
                       "§5.4：isIndexComplete && 代际连续两轮不变 → applying")
    }

    func testGenerationChangeResetsStability() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 250, boundsReady: true)
        machine.headProgress(generation: 3, indexComplete: true)
        XCTAssertEqual(machine.headProgress(generation: 4, indexComplete: true), .waitingForHead,
                       "代际变化（新 head 批次落地）→ 稳定轮数清零，重新等两轮")
    }

    func testStableRoundsWithoutCompleteIndexKeepWaiting() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 250, boundsReady: true)
        machine.headProgress(generation: 3, indexComplete: false)
        XCTAssertEqual(machine.headProgress(generation: 3, indexComplete: false), .waitingForHead,
                       "代际稳定但索引未完成 → 继续等待，不得 applying")
    }

    func testApplyingEntryIsAllowedOnlyOnce() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 0, boundsReady: true)
        XCTAssertEqual(machine.apply(), .applying)
        XCTAssertTrue(machine.hasApplied)
        XCTAssertEqual(machine.apply(), .applying, "重复 apply 调用直接返回，不得重置代际/尝试数")
        XCTAssertEqual(machine.attempts, 0)
    }

    func testAppliedMovesToVerifying() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 0, boundsReady: true)
        machine.apply()
        XCTAssertEqual(machine.applied(), .verifying)
    }

    func testVerifiedOkSettles() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 0, boundsReady: true)
        machine.apply()
        machine.applied()
        XCTAssertEqual(machine.verified(ok: true), .settled)
        XCTAssertTrue(machine.canSave)
        XCTAssertFalse(machine.isInFlight)
    }

    func testFirstVerifyFailureRetriesOnce() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 0, boundsReady: true)
        machine.apply()
        machine.applied()
        XCTAssertEqual(machine.verified(ok: false), .applying, "第一次 verify 失败 → 回 applying 重试一次")
        XCTAssertEqual(machine.attempts, 1)
        XCTAssertFalse(machine.canSave)
    }

    func testSecondVerifyFailureFallsBackNotFakeSettled() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 0, boundsReady: true)
        machine.apply()
        machine.applied()
        machine.verified(ok: false)
        machine.applied()
        XCTAssertEqual(machine.verified(ok: false), .fallback,
                       "v6 硬化：两次 verify 仍失败 → fallback（锚点 cell 顶部），绝不假 settled")
        XCTAssertTrue(machine.isInFlight, "fallback 落地前仍在恢复中")
        XCTAssertEqual(machine.settleFallback(), .settled)
        XCTAssertTrue(machine.canSave)
    }

    func testAnchorMissingWithIncompleteIndexKeepsWaiting() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 250, boundsReady: true)
        XCTAssertEqual(machine.anchorMissing(indexComplete: false), .waitingForHead,
                       "锚点暂不在数据且索引未完成 → 保持等待（I4 无硬超时）")
    }

    func testAnchorMissingWithCompleteIndexFallsBack() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 0, boundsReady: true)
        XCTAssertEqual(machine.anchorMissing(indexComplete: true), .fallback,
                       "索引完成仍无锚点 → section/ratio fallback")
        XCTAssertEqual(machine.settleFallback(), .settled)
    }

    func testForceFallbackFromLoadingSkipsAssetPath() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        XCTAssertEqual(machine.forceFallback(), .fallback, "§5.3 无效记录 → 跳过 asset 精确路径直接 fallback")
        XCTAssertFalse(machine.canSave)
        XCTAssertEqual(machine.settleFallback(), .settled)
        XCTAssertTrue(machine.canSave)
    }

    func testCancelFromWaitingForHeadSettlesImmediately() {
        var machine = PositionRestoreMachineV6()
        machine.begin(hasAnchor: true)
        machine.windowResolved(windowStart: 250, boundsReady: true)
        XCTAssertEqual(machine.cancel(), .settled, "用户接管（月跳/手动滚动取消）→ 立即 settled 允许保存")
        XCTAssertTrue(machine.canSave)
    }
}