// MARK: - 职责说明：SlideSelectPolicy 边缘速度 / offset 钳制单测。
// 旧方向锁 / 往返奇偶选择死代码测试已随函数删除（M17 T02，docs/31 X10）；
// 方向锁 / 长按 / 边缘配对判定改由 SelectionGestureMachineTests 覆盖。

import XCTest
@testable import PhotoDeskCore

final class SlideSelectPolicyTests: XCTestCase {

    func testTopEdgeVelocityIsNegativeAndProportional() {
        let atEdge = SlideSelectPolicy.edgeVelocity(fingerY: 0, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        let nearEdge = SlideSelectPolicy.edgeVelocity(fingerY: 30, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        XCTAssertLessThan(atEdge, 0)
        XCTAssertLessThan(nearEdge, 0)
        XCTAssertGreaterThan(atEdge.magnitude, nearEdge.magnitude)
        XCTAssertGreaterThanOrEqual(atEdge.magnitude, 1)
        XCTAssertLessThanOrEqual(atEdge.magnitude, 18)
    }

    func testBottomEdgeVelocityIsPositiveAndProportional() {
        let atEdge = SlideSelectPolicy.edgeVelocity(fingerY: 800, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        let nearEdge = SlideSelectPolicy.edgeVelocity(fingerY: 780, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        XCTAssertGreaterThan(atEdge, 0)
        XCTAssertGreaterThan(nearEdge, 0)
        XCTAssertGreaterThan(atEdge, nearEdge)
        XCTAssertLessThanOrEqual(atEdge, 18)
    }

    func testOutsideBufferHasZeroVelocity() {
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 61, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 739, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 400, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
    }

    func testInvalidBufferOrStepsReturnZero() {
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 10, top: 0, bottom: 800, buffer: 0, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: .nan, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 10, top: 0, bottom: 800, buffer: 60, minStep: 18, maxStep: 1), 0)
    }

    func testClampedOffsetKeepsBounds() {
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: 5, min: -44, max: 900), 105)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: -1000, min: -44, max: 900), -44)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: 1000, min: -44, max: 900), 900)
    }

    func testClampedOffsetHandlesReversedAndNonFiniteInputs() {
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: 5, min: 900, max: -44), 105)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: .nan, delta: 5, min: -44, max: 900), -44)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: .infinity, min: -44, max: 900), 900)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: -.infinity, min: -44, max: 900), -44)
    }
}
