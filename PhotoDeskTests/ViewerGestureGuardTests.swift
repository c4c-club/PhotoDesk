// MARK: - 职责说明：查看器手势互斥纯策略单元测试（docs/16 M12 R02/B1）——
// 基线红：策略不存在（shouldBegin 只判一次 isZoomed、simultaneous 无条件 true、
// 缩放事务中执行删除事务）。VC 接线由 UI 测试与真机覆盖；本文件锁定决策语义。

import XCTest
import UIKit
@testable import PhotoDesk

final class ViewerGestureGuardTests: XCTestCase {
    private func state(isZooming: Bool,
                       zoomScale: CGFloat,
                       sinceActivity: TimeInterval,
                       geometryState: ZoomTransactionState = .idle) -> ViewerGesturePolicy.CellState {
        .init(isZooming: isZooming,
              zoomScale: zoomScale,
              secondsSinceZoomActivity: sinceActivity,
              geometryState: geometryState)
    }

    // MARK: - pan 是否允许开始

    func testPanDisabledWhileCellZoomed() {
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: true, numberOfTouches: 1,
            cell: state(isZooming: false, zoomScale: 1.5, sinceActivity: 10)),
            "zoomScale > 1.01 时 pan 不得开始（放大后拖动应属于 cell 内部滚动）")
    }

    func testPanDisabledWhileZooming() {
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: true, numberOfTouches: 1,
            cell: state(isZooming: true, zoomScale: 1.0, sinceActivity: 0)),
            "捏合进行中 pan 不得开始")
    }

    func testPanDisabledWithinZoomActivityGrace() {
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: true, numberOfTouches: 1,
            cell: state(isZooming: false, zoomScale: 1.0, sinceActivity: 0.2)),
            "缩放刚结束的回弹窗口内 pan 不得开始")
    }

    func testPanAllowedAtRestSingleTouch() {
        XCTAssertTrue(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: true, numberOfTouches: 1,
            cell: state(isZooming: false, zoomScale: 1.0, sinceActivity: 10)),
            "静止 1× 单指：pan 正常开始")
        XCTAssertTrue(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: true, numberOfTouches: 1, cell: nil),
            "无 cell（空态）：pan 正常开始")
    }

    func testPanDisabledWhenGesturesOff() {
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: false, numberOfTouches: 1, cell: nil),
            "无障碍手势总开关关闭：pan 一律不开始")
    }

    func testPanDisabledWithTwoTouches() {
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: true, numberOfTouches: 2,
            cell: state(isZooming: false, zoomScale: 1.0, sinceActivity: 10)),
            "双指属于捏合：pan 不得开始（旧版 maximumNumberOfTouches=1 使该分支成死代码）")
    }

    // MARK: - 删除/隐藏事务与缩放事务互斥

    func testRemovalBlockedDuringZoomTransaction() {
        XCTAssertFalse(ViewerGesturePolicy.allowsRemovalTransaction(
            cell: state(isZooming: true, zoomScale: 1.3, sinceActivity: 0)),
            "捏合进行中禁止删除事务（B1：performBatchUpdates 在缩放事务中执行 → 崩溃）")
        XCTAssertFalse(ViewerGesturePolicy.allowsRemovalTransaction(
            cell: state(isZooming: false, zoomScale: 1.3, sinceActivity: 0.3)),
            "回弹窗口内禁止删除事务")
        XCTAssertTrue(ViewerGesturePolicy.allowsRemovalTransaction(
            cell: state(isZooming: false, zoomScale: 1.0, sinceActivity: 10)))
        XCTAssertTrue(ViewerGesturePolicy.allowsRemovalTransaction(cell: nil),
                      "无 cell（空态）：事务正常执行")
    }

    // MARK: - M13 P1：缩放几何事务与删除队列

    func testQueuedRemovalDrainRequiresGeometryIdle() {
        XCTAssertTrue(ViewerGesturePolicy.allowsQueuedRemovalDrain(
            cell: state(isZooming: false, zoomScale: 1.8, sinceActivity: 0.1, geometryState: .idle)),
            "几何已 idle、未捏合：放大静止态的排队动作可以 drain，不能永久挂起")
        XCTAssertTrue(ViewerGesturePolicy.allowsQueuedRemovalDrain(cell: nil),
                      "无 cell：队列可 drain")
        XCTAssertFalse(ViewerGesturePolicy.allowsQueuedRemovalDrain(
            cell: state(isZooming: false, zoomScale: 1, sinceActivity: 10, geometryState: .active)),
            "active 几何事务期禁止 drain（不得与 CATransaction 提交同帧）")
        XCTAssertFalse(ViewerGesturePolicy.allowsQueuedRemovalDrain(
            cell: state(isZooming: false, zoomScale: 1, sinceActivity: 10, geometryState: .settling)),
            "settling 批量提交期禁止 drain")
        XCTAssertFalse(ViewerGesturePolicy.allowsQueuedRemovalDrain(
            cell: state(isZooming: true, zoomScale: 1, sinceActivity: 0, geometryState: .idle)),
            "捏合进行中禁止 drain")
    }

    func testShouldQueueRemovalDuringZoomTransaction() {
        XCTAssertTrue(ViewerGesturePolicy.shouldQueueRemoval(
            cell: state(isZooming: true, zoomScale: 1.3, sinceActivity: 0)),
            "捏合中删除动作必须入队而不是丢弃")
        XCTAssertTrue(ViewerGesturePolicy.shouldQueueRemoval(
            cell: state(isZooming: false, zoomScale: 1, sinceActivity: 0.2)),
            "回弹宽限窗口内删除动作必须入队")
        XCTAssertTrue(ViewerGesturePolicy.shouldQueueRemoval(
            cell: state(isZooming: false, zoomScale: 1, sinceActivity: 10, geometryState: .active)),
            "active 几何事务期删除动作必须入队")
        XCTAssertFalse(ViewerGesturePolicy.shouldQueueRemoval(
            cell: state(isZooming: false, zoomScale: 1, sinceActivity: 10)),
            "静止 idle 时删除动作立即执行")
        XCTAssertFalse(ViewerGesturePolicy.shouldQueueRemoval(cell: nil),
                       "无 cell：删除动作立即执行")
    }

    func testGeometryStateAloneBlocksPanAndImmediateRemoval() {
        let active = state(isZooming: false, zoomScale: 1, sinceActivity: 10, geometryState: .active)
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(gesturesEnabled: true, numberOfTouches: 1, cell: active))
        XCTAssertFalse(ViewerGesturePolicy.allowsRemovalTransaction(cell: active))
        let settling = state(isZooming: false, zoomScale: 1, sinceActivity: 10, geometryState: .settling)
        XCTAssertFalse(ViewerGesturePolicy.allowsRemovalTransaction(cell: settling))
    }
}
