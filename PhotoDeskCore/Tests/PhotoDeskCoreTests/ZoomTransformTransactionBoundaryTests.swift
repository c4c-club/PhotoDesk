// MARK: - ZoomTransformTransactionBoundaryTests：缩放事务边界状态机（docs/28 §4.2/§4.4.1/§4.4.2 / M16 P0-1A T01）——
// 锁定四类契约：① 手势事件在动画/交互窗口内的决策（绝不对 UIGestureRecognizer.state 赋值，
// 拒绝 = 直接 return 让手势自然结束）；② 动画代际 token（stale completion 必须被忽略）；
// ③ 复用/旋转/布局 invalidated 的取消语义（立即回 idle，旧 completion/手势不再推进）；
// ④ transform 有限值消毒与视口可用性（NaN/∞/零 bounds 一律拒绝写入）。
// ≥20 条：NaN、Infinity、0 bounds、scale 0、min/max、焦点缩放、边界平移、幂等。

import XCTest
@testable import PhotoDeskCore

final class ZoomTransformTransactionBoundaryTests: XCTestCase {

    // MARK: - 决策表：idle 起步

    func testIdleAcceptsPinchBegin() {
        let d = ZoomTransformTransaction.decide(state: .idle, event: .gestureBegan(.pinch))
        XCTAssertEqual(d, .beginInteraction)
    }

    func testIdleAcceptsPanBegin() {
        let d = ZoomTransformTransaction.decide(state: .idle, event: .gestureBegan(.pan))
        XCTAssertEqual(d, .beginInteraction)
    }

    /// 双击只在 .ended 处理并请求动画；.began 不进入交互态（避免空事务卡住翻页门禁）
    func testIdleIgnoresDoubleTapBegin() {
        let d = ZoomTransformTransaction.decide(state: .idle, event: .gestureBegan(.doubleTap))
        XCTAssertEqual(d, .ignoreGesture)
    }

    /// 双击动画请求：idle 才允许开动画并推进代际 token
    func testIdleBeginsAnimationAndBumpsToken() {
        let state = ZoomTransactionSnapshot(phase: .idle, animationToken: 7)
        let d = ZoomTransformTransaction.decide(state: state, event: .animationRequested)
        XCTAssertEqual(d, .beginAnimation)
        let next = ZoomTransformTransaction.advanced(state, by: d)
        XCTAssertEqual(next.phase, .animating)
        XCTAssertEqual(next.animationToken, 8)
    }

    // MARK: - 决策表：动画窗口（docs/28 §4.2 R1——旧实现对 gesture.state 赋 .cancelled，新契约拒绝 = 直接 return）

    func testAnimatingRejectsPinchBeginWithoutStateWrite() {
        let state = ZoomTransactionSnapshot(phase: .animating, animationToken: 3)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureBegan(.pinch)), .ignoreGesture)
    }

    func testAnimatingRejectsPanBegin() {
        let state = ZoomTransactionSnapshot(phase: .animating, animationToken: 3)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureBegan(.pan)), .ignoreGesture)
    }

    func testAnimatingIgnoresGestureChangedAndEnded() {
        let state = ZoomTransactionSnapshot(phase: .animating, animationToken: 3)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureChanged), .ignoreGesture)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureEnded), .ignoreGesture)
    }

    // MARK: - 决策表：交互中

    func testInteractingContinuesOnChanged() {
        let state = ZoomTransactionSnapshot(phase: .interacting, animationToken: 0)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureChanged), .continueInteraction)
    }

    func testInteractingSettlesOnEnded() {
        let state = ZoomTransactionSnapshot(phase: .interacting, animationToken: 0)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureEnded), .settle)
        XCTAssertEqual(ZoomTransformTransaction.advanced(state, by: .settle).phase, .idle)
    }

    /// 第二手势在交互中开始：单事务原则，拒绝并行（旧实现允许 pinch 中 pan 隐式并行）
    func testInteractingRejectsSecondGestureBegin() {
        let state = ZoomTransactionSnapshot(phase: .interacting, animationToken: 0)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureBegan(.pan)), .ignoreGesture)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .gestureBegan(.pinch)), .ignoreGesture)
    }

    func testIdleIgnoresChangedAndEnded() {
        XCTAssertEqual(ZoomTransformTransaction.decide(state: .idle, event: .gestureChanged), .ignoreGesture)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: .idle, event: .gestureEnded), .ignoreGesture)
    }

    /// 幂等：连续两次 ended，第二次必须被忽略（不能重复 settle / 重复发 idle 回调语义）
    func testDoubleSettleIsIdempotent() {
        let settled = ZoomTransformTransaction.advanced(
            ZoomTransactionSnapshot(phase: .interacting), by: .settle)
        XCTAssertEqual(settled.phase, .idle)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: settled, event: .gestureEnded), .ignoreGesture)
    }

    // MARK: - 动画代际 token

    func testMatchingTokenFinishesAnimation() {
        let state = ZoomTransactionSnapshot(phase: .animating, animationToken: 12)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .animationCompleted(token: 12)), .finishAnimation)
        XCTAssertEqual(ZoomTransformTransaction.advanced(state, by: .finishAnimation).phase, .idle)
    }

    /// stale completion（复用/新动画已开启）：不得收敛事务、不得写几何
    func testStaleTokenCompletionIsIgnored() {
        let state = ZoomTransactionSnapshot(phase: .animating, animationToken: 13)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .animationCompleted(token: 12)), .ignoreCompletion)
        XCTAssertEqual(ZoomTransformTransaction.advanced(state, by: .ignoreCompletion), state)
    }

    func testCompletionOnIdleIsIgnored() {
        XCTAssertEqual(ZoomTransformTransaction.decide(state: .idle, event: .animationCompleted(token: 0)), .ignoreCompletion)
    }

    /// 新动画请求会刷新 token；旧 completion 在新 token 下失配
    func testNewAnimationInvalidatesOldCompletion() {
        let first = ZoomTransactionSnapshot(phase: .idle, animationToken: 0)
        let a = ZoomTransformTransaction.advanced(first, by: .beginAnimation)
        let b = ZoomTransformTransaction.advanced(ZoomTransformTransaction.advanced(a, by: .settle), by: .beginAnimation)
        XCTAssertEqual(b.animationToken, 2)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: b, event: .animationCompleted(token: 1)), .ignoreCompletion)
    }

    // MARK: - invalidated（复用 / 旋转 / 布局 / 手势总开关关闭）

    func testInvalidatedCancelsFromAnyPhase() {
        for phase in [ZoomTransactionSnapshot.Phase.idle, .interacting, .animating] {
            let state = ZoomTransactionSnapshot(phase: phase, animationToken: 5)
            XCTAssertEqual(ZoomTransformTransaction.decide(state: state, event: .invalidated), .invalidate)
            let next = ZoomTransformTransaction.advanced(state, by: .invalidate)
            XCTAssertEqual(next.phase, .idle)
            XCTAssertEqual(next.animationToken, 0)
        }
    }

    /// invalidated 后到达的 stale completion / 手势事件必须全部被忽略
    func testEventsAfterInvalidationAreIgnored() {
        let reset = ZoomTransformTransaction.advanced(
            ZoomTransactionSnapshot(phase: .animating, animationToken: 5), by: .invalidate)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: reset, event: .animationCompleted(token: 5)), .ignoreCompletion)
        XCTAssertEqual(ZoomTransformTransaction.decide(state: reset, event: .gestureBegan(.pinch)), .beginInteraction)
    }

    // MARK: - transform 消毒（NaN / Infinity / scale 0 / 有限值保留）

    func testSanitizeRejectsNaNScale() {
        XCTAssertNil(ZoomTransformTransaction.sanitizedTransform(scale: .nan, translationX: 0, translationY: 0))
    }

    func testSanitizeRejectsInfinityTranslation() {
        XCTAssertNil(ZoomTransformTransaction.sanitizedTransform(scale: 2, translationX: .infinity, translationY: 0))
        XCTAssertNil(ZoomTransformTransaction.sanitizedTransform(scale: 2, translationX: 0, translationY: -.infinity))
    }

    /// scale 0：几何上等于消失，属于非法写入（min/max 钳制是 Policy 职责，消毒层只挡非正数）
    func testSanitizeRejectsZeroAndNegativeScale() {
        XCTAssertNil(ZoomTransformTransaction.sanitizedTransform(scale: 0, translationX: 0, translationY: 0))
        XCTAssertNil(ZoomTransformTransaction.sanitizedTransform(scale: -1.5, translationX: 0, translationY: 0))
    }

    func testSanitizeAcceptsFiniteValues() {
        let t = ZoomTransformTransaction.sanitizedTransform(scale: 3.5, translationX: -120, translationY: 88)
        XCTAssertEqual(t, ZoomTransform(scale: 3.5, translationX: -120, translationY: 88))
    }

    /// min/max：消毒层不越权钳制——只验证 [1,5] 合法值原样通过（钳制在 ZoomTransformPolicy.sanitizedScale）
    func testSanitizeKeepsScaleWithinContractRange() {
        let minT = ZoomTransformTransaction.sanitizedTransform(scale: 1, translationX: 0, translationY: 0)
        let maxT = ZoomTransformTransaction.sanitizedTransform(scale: 5, translationX: 0, translationY: 0)
        XCTAssertEqual(minT?.scale, 1)
        XCTAssertEqual(maxT?.scale, 5)
    }

    // MARK: - 视口可用性（0 bounds / NaN bounds 拒绝写入）

    func testUsableViewportRejectsZeroAndNaN() {
        XCTAssertFalse(ZoomTransformTransaction.isUsableViewport(width: 0, height: 844))
        XCTAssertFalse(ZoomTransformTransaction.isUsableViewport(width: 390, height: 0))
        XCTAssertFalse(ZoomTransformTransaction.isUsableViewport(width: .nan, height: 844))
        XCTAssertFalse(ZoomTransformTransaction.isUsableViewport(width: 390, height: .infinity))
        XCTAssertFalse(ZoomTransformTransaction.isUsableViewport(width: -10, height: 844))
    }

    func testUsableViewportAcceptsPositiveFinite() {
        XCTAssertTrue(ZoomTransformTransaction.isUsableViewport(width: 390, height: 844))
    }

    // MARK: - 焦点缩放 / 边界平移：消毒层与 Policy 的协作契约

    /// 焦点缩放链路：Policy.pinch 输出必须通过消毒层（旧实现的写入路径无此关卡）
    func testPinchOutputPassesSanitization() {
        let t = ZoomTransformPolicy.pinch(current: .identity, pinchScale: 2.2,
                                          anchorX: 195, anchorY: 422,
                                          contentWidth: 390, contentHeight: 260,
                                          viewportWidth: 390, viewportHeight: 844)
        XCTAssertEqual(ZoomTransformTransaction.sanitizedTransform(scale: t.scale,
                                                                   translationX: t.translationX,
                                                                   translationY: t.translationY), t)
    }

    /// 边界平移链路：NaN 平移增量进 Policy.pan 仍输出有限值，且通过消毒
    func testPanWithNaNDeltaStaysFiniteAndPassesSanitization() {
        let start = ZoomTransform(scale: 2.5, translationX: 40, translationY: 40)
        let t = ZoomTransformPolicy.pan(current: start, deltaX: .nan, deltaY: .infinity,
                                        contentWidth: 390, contentHeight: 260,
                                        viewportWidth: 390, viewportHeight: 844)
        XCTAssertTrue(t.scale.isFinite && t.translationX.isFinite && t.translationY.isFinite)
        XCTAssertEqual(ZoomTransformTransaction.sanitizedTransform(scale: t.scale,
                                                                   translationX: t.translationX,
                                                                   translationY: t.translationY), t)
    }

    // MARK: - geometryState 派生（docs/28 §4.2 R2——旧实现硬编码 .idle）

    func testGeometryStateDerivedFromPhase() {
        XCTAssertEqual(ZoomTransformTransaction.geometryState(for: .idle), .idle)
        XCTAssertEqual(ZoomTransformTransaction.geometryState(for: .interacting), .active)
        XCTAssertEqual(ZoomTransformTransaction.geometryState(for: .animating), .settling)
    }
}
