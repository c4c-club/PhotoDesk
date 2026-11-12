// MARK: - ZoomableImageCellTests：自管变换交互语义（docs/26 §5.6 / M15 P0-1，≥8 条）——
// 覆盖 zoomState 纯值语义、诊断同步、idle 回调、手势门禁、加载 token；几何细节见 ViewerCellGeometryTests。

import XCTest
import UIKit
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
final class ZoomableImageCellTests: XCTestCase {
    private func makeItem(isCloudOnly: Bool = false) -> PhotoItem {
        PhotoItem(id: "zc-\(UUID().uuidString)",
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: Date(),
                  modificationDate: nil,
                  pixelWidth: 500,
                  pixelHeight: 200,
                  duration: 0,
                  isFavorite: false,
                  isHidden: false,
                  location: nil,
                  burstIdentifier: nil,
                  isCloudOnly: isCloudOnly)
    }

    private func makeImage(_ width: CGFloat = 500, _ height: CGFloat = 200) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func layoutInWindow(_ cell: UICollectionViewCell, frame: CGRect) {
        let window = UIWindow(frame: frame)
        window.addSubview(cell)
        cell.frame = window.bounds
        window.layoutIfNeeded()
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
    }

    /// zoomState 是纯值：scale 来自控制器，isZooming 只在手势/动画期为 true
    func testZoomStateReflectsScaleAndInteraction() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(cell.zoomState.zoomScale, 1, accuracy: 1e-9)
        XCTAssertFalse(cell.zoomState.isZooming)
        cell.test_applyTransform(scale: 2.5, translationX: 10, translationY: 10)
        XCTAssertEqual(cell.zoomState.zoomScale, 2.5, accuracy: 1e-9)
        XCTAssertTrue(cell.zoomState.zoomScale > 1.01)
        XCTAssertEqual(cell.zoomState.geometryState, .idle)
    }

    /// 诊断与变换同步（DEBUG 横幅 zoom= 字段来源）
    func testDiagnosticsSyncWithTransform() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 3, translationX: 0, translationY: 0)
        XCTAssertEqual(cell.diagnostics.currentScale, 3, accuracy: 1e-9)
        XCTAssertEqual(cell.zoomScale, 3, accuracy: 1e-9)
        XCTAssertTrue(cell.isZoomed)
    }

    /// 缩放态 reset 后触发 idle 回调（VC 串行 drain 删除队列的信号源）
    func testIdleCallbackFiresAfterResetFromZoomed() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let exp = expectation(description: "idle")
        cell.onZoomTransactionDidBecomeIdle = { exp.fulfill() }
        cell.test_applyTransform(scale: 2, translationX: 50, translationY: 50)
        cell.resetZoom()
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(cell.zoomScale, 1, accuracy: 1e-9)
    }

    /// 手势门禁：无图/占位禁用；有图 + 视口有效启用
    func testGestureEnableGating() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: nil)
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertFalse(cell.test_zoomController.test_areGesturesEnabled)
        cell.applyDownloadedImage(makeImage())
        XCTAssertTrue(cell.test_zoomController.test_areGesturesEnabled)
        cell.showCloudPlaceholder()
        XCTAssertFalse(cell.test_zoomController.test_areGesturesEnabled)
    }

    /// 放大态禁止外层 pan 开始（shouldPanBegin → false）；回 1× 恢复
    func testPanGateRejectsWhileZoomed() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 0, translationY: 0)
        XCTAssertFalse(ViewerGesturePolicy.shouldPanBegin(gesturesEnabled: true,
                                                          numberOfTouches: 1,
                                                          cell: cell.zoomState),
                       "放大态外层上下滑必须让位")
        cell.resetZoom()
        XCTAssertTrue(ViewerGesturePolicy.shouldPanBegin(gesturesEnabled: true,
                                                         numberOfTouches: 1,
                                                         cell: cell.zoomState))
    }

    /// 放大静止态仍禁翻页滚动（zoomScale > 1.01 → isZoomTransactionActive）
    func testZoomedIdleStateStillBlocksPaging() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 0, translationY: 0)
        XCTAssertTrue(ViewerGesturePolicy.isZoomTransactionActive(cell.zoomState))
        cell.resetZoom()
        XCTAssertFalse(ViewerGesturePolicy.isZoomTransactionActive(cell.zoomState))
    }

    /// 加载 token：beginLoad 递增，matches 校验，cancelLoad 失配旧回填
    func testLoadTokensGuardStaleFill() {
        let cell = ZoomableImageCell()
        let token = cell.beginLoad()
        XCTAssertTrue(cell.matches(token: token))
        let newToken = cell.beginLoad()
        XCTAssertFalse(cell.matches(token: token), "旧 token 必须失配")
        XCTAssertTrue(cell.matches(token: newToken))
        cell.cancelLoad()
        XCTAssertFalse(cell.matches(token: newToken), "cancelLoad 后 token 必须失配")
    }

    /// 容器永不参与缩放：min=max=1、isScrollEnabled=false、delegate=nil
    func testViewportContainerNeverZooms() {
        let cell = ZoomableImageCell()
        cell.configure(item: makeItem(), image: makeImage())
        XCTAssertEqual(cell.test_scrollView.minimumZoomScale, 1)
        XCTAssertEqual(cell.test_scrollView.maximumZoomScale, 1)
        XCTAssertFalse(cell.test_scrollView.isScrollEnabled)
        XCTAssertNil(cell.test_scrollView.delegate)
        XCTAssertEqual(cell.test_scrollView.accessibilityIdentifier, "Viewer-ZoomScrollView")
    }

    /// configure 重置 itemID / token / 重试回调（复用语义）
    func testConfigureResetsSessionState() {
        let cell = ZoomableImageCell()
        let oldToken = cell.beginLoad()
        cell.configure(item: makeItem(), image: nil)
        XCTAssertFalse(cell.matches(token: oldToken))
        XCTAssertNotNil(cell.itemID)
        cell.prepareForReuse()
        XCTAssertNil(cell.itemID)
    }

    // MARK: - M16 T01 P0-1A：事务边界（docs/28 §4.2/§4.4.2）

    /// 非有限 transform 必须被写入层消毒拒绝并复位 identity（旧实现直接写 CALayer → 行为红）
    func testNonFiniteTransformResetsToIdentity() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2.5, translationX: 30, translationY: 30)
        cell.test_zoomController.applyRelayout(ZoomTransform(scale: .nan, translationX: .infinity, translationY: 0))
        XCTAssertEqual(cell.test_imageView.transform.a, 1, accuracy: 1e-9,
                       "NaN scale 写入必须被拒绝并复位 identity")
        XCTAssertEqual(cell.test_imageView.transform.d, 1, accuracy: 1e-9)
        XCTAssertEqual(cell.zoomScale, 1, accuracy: 1e-9, "消毒后诊断 scale 必须回 1")
    }

    /// 零 bounds（未布局）：写入被拒绝，诊断不更新（锁定契约）
    func testZeroBoundsTransformIsRejected() {
        let cell = ZoomableImageCell(frame: .zero)
        cell.configure(item: makeItem(), image: makeImage())
        cell.test_applyTransform(scale: 2.5, translationX: 0, translationY: 0)
        XCTAssertEqual(cell.zoomScale, ZoomableImageCell.minZoomScale,
                       "零 bounds 视口不得写入 transform")
    }

    /// 几何事务态由实际 phase 派生：动画期 settling、结束回 idle（旧实现硬编码 .idle → 行为红）
    func testGeometryStateDerivedFromControllerPhase() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 0, translationY: 0)
        cell.test_zoomController.reset(animated: true)
        XCTAssertEqual(cell.zoomState.geometryState, .settling,
                       "动画中的 geometryState 必须是 settling")
        let exp = expectation(description: "animation settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(cell.zoomState.geometryState, .idle, "动画完成后 geometryState 回 idle")
    }

    /// 动画代际 token：复用（invalidated）后 token 归零（旧实现无 token → 编译红）
    func testReuseClearsTransactionToken() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 0, translationY: 0)
        cell.test_zoomController.reset(animated: true)
        XCTAssertGreaterThan(cell.test_zoomController.test_transactionToken, 0,
                             "开启动画后 token 必须大于 0")
        cell.prepareForReuse()
        XCTAssertEqual(cell.test_zoomController.test_transactionToken, 0,
                       "复用必须清零事务 token（旧 completion 一律失效）")
        XCTAssertEqual(cell.test_imageView.transform, .identity)
    }

    /// 复位动画期间复用：等动画 completion 窗口后 transform 不得被旧动画改写
    func testStaleCompletionDoesNotRewriteTransformAfterReuse() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2.5, translationX: 10, translationY: 10)
        cell.test_zoomController.reset(animated: true)
        cell.prepareForReuse()
        let exp = expectation(description: "completion window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(cell.test_imageView.transform.a, 1, accuracy: 1e-9,
                       "复用后旧动画 completion 不得改写几何")
    }

    /// 批量更新前的 settle 入口：缩放中调用后几何事务立即 settled（VC reload/dismiss 门禁依赖）
    func testSettleForBatchUpdateResetsTransaction() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 0, translationY: 0)
        cell.test_zoomController.reset(animated: true)
        cell.settleForBatchUpdate()
        XCTAssertEqual(cell.zoomState.geometryState, .idle)
        XCTAssertEqual(cell.test_imageView.transform, .identity)
        XCTAssertFalse(ViewerGesturePolicy.isZoomTransactionActive(cell.zoomState),
                       "settle 后删除/批量更新事务必须放行")
    }
}
