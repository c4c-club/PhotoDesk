// MARK: - 职责说明：缩放事务几何提交单测——活跃期合并为一次、非有限/零尺寸丢弃、居中 inset 不双倍；纯 Linux swift test 可跑。

import XCTest
@testable import PhotoDeskCore

final class ZoomGeometryTransactionTests: XCTestCase {
    private func commit(
        width: Double = 300,
        height: Double = 200,
        insets: DoubleInsets = .zero,
        scale: Double = 1
    ) -> ZoomGeometryCommit {
        ZoomGeometryCommit(
            contentSize: DoubleSize(width: width, height: height),
            insets: insets,
            zoomScale: scale
        )
    }

    func testActivePendingGeometryCoalescesIntoSingleCommit() {
        let pending = [commit(width: 300), commit(width: 310), commit(width: 320)]
        let result = ZoomGeometryTransaction.coalesced(pending)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.contentSize.width, 320)
    }

    func testLastValidCommitWins() {
        let merged = ZoomGeometryTransaction.merged([commit(width: 300), commit(width: 310), commit(width: 320)])
        XCTAssertEqual(merged?.contentSize.width, 320)
    }

    func testNonFinitePendingIsDiscarded() {
        let pending = [commit(width: .nan), commit(height: .infinity), commit(scale: .nan)]
        XCTAssertTrue(ZoomGeometryTransaction.coalesced(pending).isEmpty)
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(width: .nan)))
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(scale: .infinity)))
    }

    func testZeroOrNegativeSizePendingIsDiscarded() {
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(width: 0)))
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(height: -1)))
        XCTAssertTrue(ZoomGeometryTransaction.coalesced([commit(width: 0), commit(height: -1)]).isEmpty)
    }

    func testInvalidPendingDoesNotHideEarlierValidCommit() {
        let result = ZoomGeometryTransaction.coalesced([commit(width: 300), commit(width: .nan)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.contentSize.width, 300)
    }

    func testSanitizedRejectsNegativeOrNonFiniteInsets() {
        let negative = DoubleInsets(top: -1, left: 0, bottom: 0, right: 0)
        let nan = DoubleInsets(top: .nan, left: 0, bottom: 0, right: 0)
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(insets: negative)))
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(insets: nan)))
    }

    func testSanitizedRejectsZeroOrNegativeScale() {
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(scale: 0)))
        XCTAssertNil(ZoomGeometryTransaction.sanitized(commit(scale: -2)))
    }

    func testEmptyPendingReturnsEmpty() {
        XCTAssertTrue(ZoomGeometryTransaction.coalesced([]).isEmpty)
        XCTAssertNil(ZoomGeometryTransaction.merged([]))
    }

    func testCenteringInsetUsesUntransformedBoundsOnly() {
        let content = DoubleSize(width: 200, height: 100)
        let viewport = DoubleSize(width: 400, height: 800)
        let insets = ZoomGeometryTransaction.centeringInsets(content: content, viewport: viewport, zoomScale: 1)
        XCTAssertEqual(insets.left, 100)
        XCTAssertEqual(insets.right, 100)
        XCTAssertEqual(insets.top, 350)
        XCTAssertEqual(insets.bottom, 350)
        XCTAssertEqual(insets, ZoomGeometry.centeredInset(
            contentWidth: 200, contentHeight: 100,
            viewportWidth: 400, viewportHeight: 800,
            zoomScale: 1
        ))
    }

    func testCenteringInsetIsNotDoubledByZoomScale() {
        let content = DoubleSize(width: 200, height: 100)
        let viewport = DoubleSize(width: 400, height: 800)
        let insets = ZoomGeometryTransaction.centeringInsets(content: content, viewport: viewport, zoomScale: 2)
        let scale = ZoomGeometry.sanitizedScale(2)
        XCTAssertEqual(insets.left, Swift.max(0, (400 - 200 * scale) / 2))
        XCTAssertEqual(insets.top, Swift.max(0, (800 - 100 * scale) / 2))
    }

    func testSanitizedKeepsFullyValidCommit() {
        let valid = commit(width: 375, height: 500, scale: 2.5)
        XCTAssertEqual(ZoomGeometryTransaction.sanitized(valid), valid)
    }
}
