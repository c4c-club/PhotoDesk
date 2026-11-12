// MARK: - 职责说明：PinchColumnReducer 纯状态机测试矩阵（docs/28 §4.4.4，M16 T02）——
// 边界刻度（NaN/Infinity/0/负）、滞回滞回带、快速反向、单飞互斥、链式消费、回弹带、中断与重置。
// 红→绿口径：旧实现（LibraryViewController.onPinch 逐阈值 setColumns）没有等价决策层，
// 这些用例在 PinchColumnReducer 落地前无法编译（red-library.txt 实录）。

import XCTest
@testable import PhotoDeskCore

final class PinchColumnReducerTests: XCTestCase {

    // MARK: - 刻度消毒

    func testNaNScaleYieldsNoChange() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertNil(r.changed(scale: .nan))
        XCTAssertFalse(r.isBusy)
    }

    func testZeroScaleYieldsNoChange() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertNil(r.changed(scale: 0))
        XCTAssertFalse(r.isBusy)
    }

    func testNegativeScaleYieldsNoChange() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertNil(r.changed(scale: -1.5))
        XCTAssertFalse(r.isBusy)
    }

    func testInfinityScaleResolvesToMinimumColumns() {
        // +∞ 刻度 → raw = 0 → 下限列（决策表固化：极端拉开 = 最少列）
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertEqual(r.changed(scale: .infinity), 2)
    }

    // MARK: - 边界与钳制

    func testClampsToConfiguredBounds() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertEqual(r.changed(scale: 0.5), 5)   // raw 6 → 上限 5
        _ = r.transitionFinished()
        XCTAssertEqual(r.changed(scale: 3), 2)     // raw 1 → 下限 2
    }

    func testCustomConfigBoundsRespected() {
        var r = PinchColumnReducer(config: PinchColumnConfig(minColumns: 3, maxColumns: 3), startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertNil(r.changed(scale: 0.4))
        XCTAssertNil(r.changed(scale: 4))
        XCTAssertFalse(r.isBusy)
    }

    func testBeginClampsStartColumns() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 9, scale: 1)
        XCTAssertEqual(r.currentColumns, 5)
        r.begin(startColumns: 0, scale: 1)
        XCTAssertEqual(r.currentColumns, 2)
    }

    // MARK: - 滞回

    func testSolidCrossingProducesPendingTarget() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertEqual(r.changed(scale: 1.5), 2)   // raw 2.0，越过中点 + 余量
    }

    func testMidpointJitterDoesNotFlipTarget() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        // raw ≈ 2.5 在 2↔3 中点附近抖动：均未越过中点 ± 滞回余量
        XCTAssertNil(r.changed(scale: 3.0 / 2.48))
        XCTAssertNil(r.changed(scale: 3.0 / 2.52))
        XCTAssertFalse(r.isBusy)
    }

    func testReverseSwitchRequiresCrossingHysteresisBack() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertEqual(r.changed(scale: 1.5), 2)
        _ = r.markInFlight()
        _ = r.transitionFinished()
        // 回 3：raw 需 ≥ 2.56（中点 2.5 + 滞回 0.06）；2.52 仍被吸收
        XCTAssertNil(r.changed(scale: 3.0 / 2.52))
        XCTAssertEqual(r.changed(scale: 3.0 / 2.6), 3)
    }

    // MARK: - 单飞与链式消费

    func testMarkInFlightClearsPendingAndSetsInFlight() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertNotNil(r.changed(scale: 1.5))
        XCTAssertTrue(r.shouldCommit)
        XCTAssertEqual(r.markInFlight(), 2)
        XCTAssertNil(r.pendingTarget)
        XCTAssertEqual(r.inFlightColumns, 2)
        XCTAssertFalse(r.shouldCommit)
    }

    func testChangedWhileInFlightOnlyQueuesPending() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        XCTAssertEqual(r.changed(scale: 0.5), 5)
        XCTAssertFalse(r.shouldCommit, "在途时不得再提交")
        XCTAssertTrue(r.isBusy)
    }

    func testDoubleMarkInFlightIsRejected() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        XCTAssertEqual(r.markInFlight(), 2)
        XCTAssertNil(r.markInFlight(), "同一时刻最多一个在途过渡")
    }

    func testTransitionFinishedConsumesChainedPending() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        _ = r.changed(scale: 0.5)
        XCTAssertEqual(r.transitionFinished(), 5, "链式 pending 接续")
        XCTAssertEqual(r.currentColumns, 5)
        XCTAssertNil(r.inFlightColumns)
    }

    func testTransitionFinishedWithoutPendingReturnsNil() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        XCTAssertNil(r.transitionFinished())
        XCTAssertFalse(r.isBusy)
    }

    // MARK: - 回弹带

    func testSnapbackReturnsToStartColumns() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        _ = r.transitionFinished()
        XCTAssertEqual(r.ended(scale: 1.02), 3, "|scale-1|<0.08 → 回起始列数")
        XCTAssertEqual(r.currentColumns, 3)
    }

    func testNoSnapbackOutsideBand() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        _ = r.transitionFinished()
        XCTAssertNil(r.ended(scale: 1.5), "松手刻度未在回弹带内 → 保持当前列数")
    }

    func testSnapbackChainsWhenInFlight() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        _ = r.changed(scale: 0.5)          // 挂起 5
        XCTAssertNil(r.ended(scale: 1.03), "在途回弹只挂链")
        XCTAssertEqual(r.pendingTarget, 3, "最新者胜：回弹目标覆盖挂起")
        XCTAssertEqual(r.transitionFinished(), 3)
    }

    func testSnapbackNoopWhenColumnsUnchanged() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        XCTAssertNil(r.ended(scale: 1.02))
        XCTAssertFalse(r.isBusy)
    }

    // MARK: - 中断与重置

    func testCancelDropsPendingKeepsCurrentColumns() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        _ = r.changed(scale: 0.5)
        r.cancel()
        XCTAssertNil(r.pendingTarget)
        XCTAssertEqual(r.currentColumns, 2, "在途列数保持")
        XCTAssertTrue(r.isBusy, "在途过渡仍待 completion 收尾")
        XCTAssertNil(r.transitionFinished())
        XCTAssertFalse(r.isBusy)
    }

    func testBeginResetsTransactionState() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: 1)
        _ = r.changed(scale: 1.5)
        _ = r.markInFlight()
        r.begin(startColumns: 4, scale: 1.2)
        XCTAssertEqual(r.startColumns, 4)
        XCTAssertEqual(r.currentColumns, 4)
        XCTAssertNil(r.pendingTarget)
        XCTAssertNil(r.inFlightColumns)
        XCTAssertFalse(r.isBusy)
    }

    func testRecordedStartScaleIsSanitized() {
        var r = PinchColumnReducer(startColumns: 3)
        r.begin(startColumns: 3, scale: .nan)
        XCTAssertEqual(r.startScale, 1)
    }
}
