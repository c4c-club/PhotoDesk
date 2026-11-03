// MARK: - ZoomGeometryTests：aspectFit / centeredInset / clampedZoomRect / sanitizedScale
// 对 0/负/NaN/∞ 的安全值守卫（docs/13 S01：≥12 条）

import XCTest
@testable import PhotoDeskCore

final class ZoomGeometryTests: XCTestCase {
    // MARK: - aspectFitSize

    func testAspectFitSquareInSquare() {
        let size = ZoomGeometry.aspectFitSize(imageWidth: 100, imageHeight: 100,
                                              viewportWidth: 200, viewportHeight: 200)
        XCTAssertEqual(size, DoubleSize(width: 200, height: 200))
    }

    func testAspectFitWideImageInTallViewportFitsWidth() {
        let size = ZoomGeometry.aspectFitSize(imageWidth: 300, imageHeight: 100,
                                              viewportWidth: 150, viewportHeight: 300)
        XCTAssertEqual(size.width, 150, accuracy: 0.0001)
        XCTAssertEqual(size.height, 50, accuracy: 0.0001)
    }

    func testAspectFitTallImageInWideViewportFitsHeight() {
        let size = ZoomGeometry.aspectFitSize(imageWidth: 100, imageHeight: 300,
                                              viewportWidth: 300, viewportHeight: 150)
        XCTAssertEqual(size.width, 50, accuracy: 0.0001)
        XCTAssertEqual(size.height, 150, accuracy: 0.0001)
    }

    func testAspectFitZeroImageReturnsZero() {
        XCTAssertEqual(ZoomGeometry.aspectFitSize(imageWidth: 0, imageHeight: 100,
                                                  viewportWidth: 100, viewportHeight: 100), .zero)
    }

    func testAspectFitNegativeViewportReturnsZero() {
        XCTAssertEqual(ZoomGeometry.aspectFitSize(imageWidth: 100, imageHeight: 100,
                                                  viewportWidth: -5, viewportHeight: 100), .zero)
    }

    func testAspectFitNaNReturnsZero() {
        XCTAssertEqual(ZoomGeometry.aspectFitSize(imageWidth: .nan, imageHeight: 100,
                                                  viewportWidth: 100, viewportHeight: 100), .zero)
    }

    func testAspectFitInfiniteReturnsZero() {
        XCTAssertEqual(ZoomGeometry.aspectFitSize(imageWidth: 100, imageHeight: .infinity,
                                                  viewportWidth: 100, viewportHeight: 100), .zero)
    }

    // MARK: - centeredInset

    func testCenteredInsetSmallerThanViewport() {
        let inset = ZoomGeometry.centeredInset(contentWidth: 100, contentHeight: 50,
                                               viewportWidth: 200, viewportHeight: 200,
                                               zoomScale: 1)
        XCTAssertEqual(inset, DoubleInsets(top: 75, left: 50, bottom: 75, right: 50))
    }

    func testCenteredInsetZoomedLargerThanViewportIsZero() {
        let inset = ZoomGeometry.centeredInset(contentWidth: 200, contentHeight: 200,
                                               viewportWidth: 200, viewportHeight: 200,
                                               zoomScale: 2)
        XCTAssertEqual(inset, .zero)
    }

    func testCenteredInsetNaNZoomFallsBackToMinScale() {
        // NaN → sanitizedScale → 1 → 与 zoomScale=1 相同
        let inset = ZoomGeometry.centeredInset(contentWidth: 100, contentHeight: 100,
                                               viewportWidth: 200, viewportHeight: 200,
                                               zoomScale: .nan)
        XCTAssertEqual(inset, DoubleInsets(top: 50, left: 50, bottom: 50, right: 50))
    }

    func testCenteredInsetNegativeContentIsZero() {
        XCTAssertEqual(ZoomGeometry.centeredInset(contentWidth: -10, contentHeight: 100,
                                                  viewportWidth: 200, viewportHeight: 200,
                                                  zoomScale: 1), .zero)
    }

    // MARK: - clampedZoomRect

    func testClampedZoomRectCentersOnFocus() {
        // 1000×1000 图，视口 500×500，2×：rect = 250×250，focus(500,500) 居中 → (375,375)
        let rect = ZoomGeometry.clampedZoomRect(zoomScale: 2, focusX: 500, focusY: 500,
                                                viewportWidth: 500, viewportHeight: 500,
                                                imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(rect, DoubleRect(x: 375, y: 375, width: 250, height: 250))
    }

    func testClampedZoomRectClampsAtEdges() {
        // focus 靠近左上角：origin 钳制到 (0,0)
        let rect = ZoomGeometry.clampedZoomRect(zoomScale: 2, focusX: 10, focusY: 10,
                                                viewportWidth: 500, viewportHeight: 500,
                                                imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(rect, DoubleRect(x: 0, y: 0, width: 250, height: 250))
    }

    func testClampedZoomRectRectCannotExceedImage() {
        // zoomScale = 1 时 rect 尺寸 = 视口（可能大于图片）→ 钳制到图片尺寸
        let rect = ZoomGeometry.clampedZoomRect(zoomScale: 1, focusX: 50, focusY: 50,
                                                viewportWidth: 800, viewportHeight: 800,
                                                imageWidth: 500, imageHeight: 500)
        XCTAssertEqual(rect, DoubleRect(x: 0, y: 0, width: 500, height: 500))
    }

    func testClampedZoomRectZeroViewportReturnsNil() {
        XCTAssertNil(ZoomGeometry.clampedZoomRect(zoomScale: 2, focusX: 10, focusY: 10,
                                                  viewportWidth: 0, viewportHeight: 500,
                                                  imageWidth: 1000, imageHeight: 1000))
    }

    func testClampedZoomRectNaNFocusReturnsNil() {
        XCTAssertNil(ZoomGeometry.clampedZoomRect(zoomScale: 2, focusX: .nan, focusY: 10,
                                                  viewportWidth: 500, viewportHeight: 500,
                                                  imageWidth: 1000, imageHeight: 1000))
    }

    func testClampedZoomRectInfiniteZoomClampedToMax() {
        // ∞ → sanitizedScale → 5 → rect = 100×100
        let rect = ZoomGeometry.clampedZoomRect(zoomScale: .infinity, focusX: 500, focusY: 500,
                                                viewportWidth: 500, viewportHeight: 500,
                                                imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(rect, DoubleRect(x: 450, y: 450, width: 100, height: 100))
    }

    // MARK: - sanitizedScale

    func testSanitizedScalePassThrough() {
        XCTAssertEqual(ZoomGeometry.sanitizedScale(2.5), 2.5)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(1), 1)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(5), 5)
    }

    func testSanitizedScaleClamps() {
        XCTAssertEqual(ZoomGeometry.sanitizedScale(0.2), 1)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(10), 5)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(-1), 1)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(0), 1)
    }

    func testSanitizedScaleNaNAndInfinity() {
        XCTAssertEqual(ZoomGeometry.sanitizedScale(.nan), 1)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(.infinity), 5)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(-.infinity), 1)
    }

    func testSanitizedScaleCustomBounds() {
        XCTAssertEqual(ZoomGeometry.sanitizedScale(0.5, minScale: 0.5, maxScale: 3), 0.5)
        XCTAssertEqual(ZoomGeometry.sanitizedScale(4, minScale: 0.5, maxScale: 3), 3)
    }
}
