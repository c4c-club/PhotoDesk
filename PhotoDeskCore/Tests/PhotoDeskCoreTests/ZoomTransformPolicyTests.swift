// MARK: - ZoomTransformPolicyTests：自管变换缩放纯几何（docs/25 §4.3 / M15 P0-1）
// 契约：① 钳制优先——内容小于视口的轴强制居中；② 锚点不变性只在钳制不触发时成立（用例避开钳制区
// 或显式断言钳制结果）；③ scale 钳制 1...5；④ 双击 1↔2.5；⑤ relayout = 平移不变 + 重新钳制；
// ⑥ 全部输入 0/负/NaN/∞ 安全。

import XCTest
@testable import PhotoDeskCore

final class ZoomTransformPolicyTests: XCTestCase {
    // 视口 390x844；内容 aspectFit 尺寸 390x260（横图竖屏视口的典型形态）
    private let vw = 390.0
    private let vh = 844.0
    private let cw = 390.0
    private let ch = 260.0

    private func assertFinite(_ t: ZoomTransform, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(t.scale.isFinite, message, file: file, line: line)
        XCTAssertTrue(t.translationX.isFinite, message, file: file, line: line)
        XCTAssertTrue(t.translationY.isFinite, message, file: file, line: line)
    }

    /// 锚点不变性：内容点 q = (A - V/2 - t)/s + C/2，pinch 前后映射到同一 A。
    private func assertAnchorInvariance(current: ZoomTransform, after: ZoomTransform,
                                        anchorX: Double, anchorY: Double,
                                        viewportWidth: Double? = nil, viewportHeight: Double? = nil,
                                        contentWidth: Double? = nil, contentHeight: Double? = nil,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let vW = viewportWidth ?? vw
        let vH = viewportHeight ?? vh
        let cW = contentWidth ?? cw
        let cH = contentHeight ?? ch
        func contentPoint(_ t: ZoomTransform) -> (Double, Double) {
            let qx = (anchorX - vW / 2 - t.translationX) / t.scale + cW / 2
            let qy = (anchorY - vH / 2 - t.translationY) / t.scale + cH / 2
            return (qx, qy)
        }
        let before = contentPoint(current)
        let afterPoint = contentPoint(after)
        XCTAssertLessThan(abs(before.0 - afterPoint.0), 1e-9, "anchor x moved", file: file, line: line)
        XCTAssertLessThan(abs(before.1 - afterPoint.1), 1e-9, "anchor y moved", file: file, line: line)
    }

    // MARK: - pinch 锚点不变（用例避开钳制区：竖轴锚点需在显示内容覆盖带内）

    func testPinchAnchorInvarianceCenter() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 2, anchorX: vw / 2, anchorY: vh / 2,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(after.scale, 2, accuracy: 1e-12)
        assertAnchorInvariance(current: current, after: after, anchorX: vw / 2, anchorY: vh / 2)
    }

    func testPinchAnchorInvarianceHorizontalOffCenter() {
        // 锚点 x=40 偏左、y 居中；scale 5 显示 1950x1300，两轴均可平移
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 5, anchorX: 40, anchorY: vh / 2,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        assertAnchorInvariance(current: current, after: after, anchorX: 40, anchorY: vh / 2)
    }

    func testPinchAnchorInvarianceVerticalOffCenter() {
        // 锚点 y=460 在 scale 5 的显示覆盖带（365...479）内；x 居中
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 5, anchorX: vw / 2, anchorY: 460,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        assertAnchorInvariance(current: current, after: after, anchorX: vw / 2, anchorY: 460)
    }

    func testPinchAnchorInvarianceBottomRightAtMaxScale() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 5, anchorX: 350, anchorY: 460,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        assertAnchorInvariance(current: current, after: after, anchorX: 350, anchorY: 460)
    }

    func testPinchAnchorInvarianceFromAlreadyZoomed() {
        // 竖图内容 390x900（scale 2.4 时显示 936x2160，两轴均可平移）→ 低倍率捏合仍满足锚点不变
        let current = ZoomTransform(scale: 2.4, translationX: 60, translationY: -120)
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 0.7, anchorX: 200, anchorY: 420,
                                              contentWidth: 390, contentHeight: 900,
                                              viewportWidth: vw, viewportHeight: vh)
        assertAnchorInvariance(current: current, after: after, anchorX: 200, anchorY: 420,
                               contentWidth: 390, contentHeight: 900)
    }

    func testPinchAnchorAtViewportOriginClampsSafely() {
        // 锚点 (0,0)：x 轴钳制边界恰好等于未钳制值（不变性在边界成立）；y 轴显示高 650<844 → 强制居中
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 2.5, anchorX: 0, anchorY: 0,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "origin anchor")
        XCTAssertEqual(after.scale, 2.5, accuracy: 1e-12)
        XCTAssertEqual(after.translationX, (cw * 2.5 - vw) / 2, accuracy: 1e-9)
        XCTAssertEqual(after.translationY, 0, accuracy: 1e-12)
    }

    func testPinchAnchorOutsideViewportStaysFinite() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 2, anchorX: 1200, anchorY: -300,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "anchor outside viewport must stay finite")
        XCTAssertEqual(after.scale, 2, accuracy: 1e-12)
    }

    // MARK: - pinch scale 钳制

    func testPinchScaleClampedToMin() {
        let current = ZoomTransform(scale: 3, translationX: 80, translationY: 80)
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 0.1, anchorX: vw / 2, anchorY: vh / 2,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(after.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(after.translationX, 0, accuracy: 1e-12, "content == viewport at 1x → centered")
        XCTAssertEqual(after.translationY, 0, accuracy: 1e-12)
    }

    func testPinchScaleClampedToMax() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 50, anchorX: vw / 2, anchorY: vh / 2,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(after.scale, 5, accuracy: 1e-12)
    }

    func testPinchNaNScaleIsSafe() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: .nan, anchorX: 100, anchorY: 100,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "NaN pinch scale")
        XCTAssertEqual(after.scale, 1, accuracy: 1e-12)
    }

    func testPinchInfiniteScaleIsSafe() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: .infinity, anchorX: 100, anchorY: 100,
                                              contentWidth: cw, contentHeight: ch,
                                              viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(after.scale, 5, accuracy: 1e-12)
        assertFinite(after, "infinite pinch scale")
    }

    func testPinchNonFiniteContentIsSafe() {
        let current = ZoomTransform(scale: 2, translationX: 30, translationY: 40)
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 2, anchorX: 100, anchorY: 100,
                                              contentWidth: .nan, contentHeight: .infinity,
                                              viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "non-finite content size")
    }

    // MARK: - pan 平移钳制

    func testPanSmallerThanViewportAxisIsCentered() {
        // 内容 390x260，视口 390x844：x 轴内容==视口宽（不可平移），y 轴内容小于视口 → 0
        var current = ZoomTransform.identity
        current = ZoomTransformPolicy.pan(current: current, deltaX: 120, deltaY: 500,
                                          contentWidth: cw, contentHeight: ch,
                                          viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(current.translationX, 0, accuracy: 1e-12)
        XCTAssertEqual(current.translationY, 0, accuracy: 1e-12)
    }

    func testPanNeverExposesWhiteEdges() {
        // scale 3 → 显示 1170x780；x 可平移 ±390，y 780 < 844 → 0
        let current = ZoomTransform(scale: 3, translationX: 0, translationY: 0)
        let panned = ZoomTransformPolicy.pan(current: current, deltaX: 5000, deltaY: 5000,
                                             contentWidth: cw, contentHeight: ch,
                                             viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(panned.translationX, 390, accuracy: 1e-9)
        XCTAssertEqual(panned.translationY, 0, accuracy: 1e-9)

        let pannedOtherWay = ZoomTransformPolicy.pan(current: current, deltaX: -5000, deltaY: -5000,
                                                     contentWidth: cw, contentHeight: ch,
                                                     viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(pannedOtherWay.translationX, -390, accuracy: 1e-9)
        XCTAssertEqual(pannedOtherWay.translationY, 0, accuracy: 1e-9)
    }

    func testPanNaNDeltaIsNoOp() {
        // 内容 390x900 @ scale 2 → 显示 780x1800，两轴钳制带 ±195 / ±478，(50,-50) 合法
        let current = ZoomTransform(scale: 2, translationX: 50, translationY: -50)
        let after = ZoomTransformPolicy.pan(current: current, deltaX: .nan, deltaY: .infinity,
                                            contentWidth: 390, contentHeight: 900,
                                            viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "NaN pan delta")
        XCTAssertEqual(after.translationX, 50, accuracy: 1e-12)
        XCTAssertEqual(after.translationY, -50, accuracy: 1e-12)
    }

    // MARK: - doubleTap

    func testDoubleTapZoomsInAtTapPoint() {
        // tap (120,500)：x 轴内容覆盖 → 锚点保持（tx=112.5）；y 轴显示高 650<844 → 钳制优先居中
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.doubleTap(current: current, tapX: 120, tapY: 500,
                                                  contentWidth: cw, contentHeight: ch,
                                                  viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(after.scale, 2.5, accuracy: 1e-12)
        XCTAssertEqual(after.translationX, 120 - vw / 2 - 2.5 * (120 - cw / 2), accuracy: 1e-9)
        XCTAssertEqual(after.translationY, 0, accuracy: 1e-12)
        // x 轴锚点不变：tap 点下的内容点前后一致
        let beforeQ = (120 - vw / 2 - 0) / 1 + cw / 2
        let afterQ = (120 - vw / 2 - after.translationX) / 2.5 + cw / 2
        XCTAssertEqual(beforeQ, afterQ, accuracy: 1e-9)
    }

    func testDoubleTapZoomsOutToOne() {
        let current = ZoomTransform(scale: 2.5, translationX: 100, translationY: -80)
        let after = ZoomTransformPolicy.doubleTap(current: current, tapX: 120, tapY: 500,
                                                  contentWidth: cw, contentHeight: ch,
                                                  viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(after, .identity)
    }

    func testDoubleTapNaNPointIsSafe() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.doubleTap(current: current, tapX: .nan, tapY: .nan,
                                                  contentWidth: cw, contentHeight: ch,
                                                  viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "NaN double-tap point")
    }

    // MARK: - relayout（旋转/尺寸变化 = 平移不变 + 重新钳制）

    func testRelayoutKeepsCenterContentCentered() {
        // current 在旧视口合法（显示 1560x1040，旧钳制带 x±585 / y±98）；新视口钳制带 x±358 / y±325
        // → 平移保持不变（中心内容点=中心，与视口尺寸无关）
        let current = ZoomTransform(scale: 4, translationX: 100, translationY: 97.5)
        let after = ZoomTransformPolicy.relayout(current: current,
                                                 oldViewport: (vw, vh),
                                                 newViewport: (vh, vw),
                                                 contentWidth: cw, contentHeight: ch)
        XCTAssertEqual(after.scale, 4, accuracy: 1e-12)
        XCTAssertEqual(after.translationX, 100, accuracy: 1e-12)
        XCTAssertEqual(after.translationY, 97.5, accuracy: 1e-12)
        // 中心内容点：q = -t/s + C/2，新旧一致
        let oldQx = -current.translationX / current.scale + cw / 2
        let newQx = -after.translationX / after.scale + cw / 2
        let oldQy = -current.translationY / current.scale + ch / 2
        let newQy = -after.translationY / after.scale + ch / 2
        XCTAssertEqual(oldQx, newQx, accuracy: 1e-9)
        XCTAssertEqual(oldQy, newQy, accuracy: 1e-9)
    }

    func testRelayoutClampsToNewViewport() {
        let current = ZoomTransform(scale: 4, translationX: 3000, translationY: -3000)
        let after = ZoomTransformPolicy.relayout(current: current,
                                                 oldViewport: (vw, vh),
                                                 newViewport: (vh, vw),
                                                 contentWidth: cw, contentHeight: ch)
        assertFinite(after, "clamped relayout")
        // 显示 1560x1040；新视口 844x390 → |tx| ≤ 358，|ty| ≤ 325
        XCTAssertLessThanOrEqual(abs(after.translationX), (cw * after.scale - vh) / 2 + 1e-9)
        XCTAssertLessThanOrEqual(abs(after.translationY), (ch * after.scale - vw) / 2 + 1e-9)
        XCTAssertGreaterThan(after.translationX, 0)
        XCTAssertLessThan(after.translationY, 0)
    }

    func testRelayoutZeroOldViewportIsSafe() {
        let current = ZoomTransform(scale: 2, translationX: 40, translationY: 40)
        let after = ZoomTransformPolicy.relayout(current: current,
                                                 oldViewport: (0, 0),
                                                 newViewport: (vw, vh),
                                                 contentWidth: cw, contentHeight: ch)
        assertFinite(after, "zero old viewport")
        XCTAssertEqual(after.translationX, 0, accuracy: 1e-12)
        XCTAssertEqual(after.translationY, 0, accuracy: 1e-12)
    }

    // MARK: - 退化输入

    func testZeroOrNegativeContentIsSafe() {
        let current = ZoomTransform.identity
        let after = ZoomTransformPolicy.pinch(current: current, pinchScale: 2, anchorX: 10, anchorY: 10,
                                              contentWidth: 0, contentHeight: -5,
                                              viewportWidth: vw, viewportHeight: vh)
        assertFinite(after, "zero/negative content")
    }

    func testZeroViewportIsSafe() {
        let current = ZoomTransform(scale: 2, translationX: 50, translationY: 50)
        let after = ZoomTransformPolicy.pan(current: current, deltaX: 10, deltaY: 10,
                                            contentWidth: cw, contentHeight: ch,
                                            viewportWidth: 0, viewportHeight: -1)
        assertFinite(after, "zero viewport")
        XCTAssertEqual(after.translationX, 0, accuracy: 1e-12)
        XCTAssertEqual(after.translationY, 0, accuracy: 1e-12)
    }

    // MARK: - 序列一致性

    func testPinchPanPinchSequenceStaysConsistent() {
        var t = ZoomTransform.identity
        t = ZoomTransformPolicy.pinch(current: t, pinchScale: 2, anchorX: 150, anchorY: 400,
                                      contentWidth: cw, contentHeight: ch,
                                      viewportWidth: vw, viewportHeight: vh)
        t = ZoomTransformPolicy.pan(current: t, deltaX: 300, deltaY: 300,
                                    contentWidth: cw, contentHeight: ch,
                                    viewportWidth: vw, viewportHeight: vh)
        t = ZoomTransformPolicy.pinch(current: t, pinchScale: 0.4, anchorX: 300, anchorY: 500,
                                      contentWidth: cw, contentHeight: ch,
                                      viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(t.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(t.translationX, 0, accuracy: 1e-12)
        XCTAssertEqual(t.translationY, 0, accuracy: 1e-12)
    }

    func testDoubleTapCycleReturnsToIdentity() {
        var t = ZoomTransform.identity
        t = ZoomTransformPolicy.doubleTap(current: t, tapX: 190, tapY: 422,
                                          contentWidth: cw, contentHeight: ch,
                                          viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(t.scale, 2.5, accuracy: 1e-12)
        t = ZoomTransformPolicy.doubleTap(current: t, tapX: 190, tapY: 422,
                                          contentWidth: cw, contentHeight: ch,
                                          viewportWidth: vw, viewportHeight: vh)
        XCTAssertEqual(t, .identity)
    }
}
