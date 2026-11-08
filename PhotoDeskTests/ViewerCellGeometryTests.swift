// MARK: - 职责说明：ZoomableImageCell 几何与交互护栏单元测试（docs/25 §4.8 / M15 P0-1 自管变换）——
// 不变量：① imageView.bounds = aspectFit 尺寸、center = viewport 中心 + translation；
// ② viewportScrollView 是纯容器（delegate=nil、min=max zoom=1、isScrollEnabled=false）；
// ③ reset/复用后回 1× 居中无残留；④ 旋转 relayout 后仍满足钳制；⑤ 占位态禁手势。

import XCTest
import UIKit
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
final class ViewerCellGeometryTests: XCTestCase {
    // MARK: - 夹具

    private func makeItem(isCloudOnly: Bool = false) -> PhotoItem {
        PhotoItem(id: "cell-\(UUID().uuidString)",
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
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 离屏 cell 挂到真实 UIWindow 强制完整布局链（cell.layoutIfNeeded 对孤儿视图不触发布局——CI 实测）
    private func layoutInWindow(_ cell: UICollectionViewCell, frame: CGRect) {
        let window = UIWindow(frame: frame)
        window.addSubview(cell)
        cell.frame = window.bounds
        window.layoutIfNeeded()
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
    }

    // MARK: - 布局

    /// 500x200 图 aspectFit 进 390x844 → imageView 尺寸 390x156；容器 contentSize 保持 .zero
    func testImageViewFitSizeAfterImageApplied() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let frame = cell.test_imageViewFrame
        XCTAssertGreaterThan(frame.width, 0, "imageView 必须有尺寸")
        XCTAssertEqual(frame.size.height, 156, accuracy: 1.0, "aspectFit 基准高度应为 156")
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.5, "1× 时 imageView 水平铺满")
        XCTAssertEqual(cell.test_scrollView.contentSize, .zero,
                       "纯容器：contentSize 不得被缩放写入")
    }

    /// 零 bounds 配置 → 正常 bounds 布局后必须自恢复
    func testZeroBoundsThenLayoutRecovers() {
        let cell = ZoomableImageCell(frame: .zero)
        cell.configure(item: makeItem(), image: makeImage())
        XCTAssertFalse(cell.test_zoomController.test_areGesturesEnabled,
                       "零 bounds 时禁止捏合交互")
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertGreaterThan(cell.test_imageViewFrame.width, 0, "布局恢复后 imageView 必须拿到尺寸")
        XCTAssertTrue(cell.test_zoomController.test_areGesturesEnabled,
                      "布局恢复 + 有图后才允许交互")
    }

    // MARK: - 纯容器（docs/25 §4.2）

    /// viewportScrollView 永不承担缩放：delegate 为 nil、min=max zoom=1、isScrollEnabled=false
    func testViewportScrollViewIsPureContainer() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertNil(cell.test_scrollView.delegate, "容器 delegate 必须为 nil（无缩放代理路径）")
        XCTAssertEqual(cell.test_scrollView.minimumZoomScale, 1)
        XCTAssertEqual(cell.test_scrollView.maximumZoomScale, 1)
        XCTAssertFalse(cell.test_scrollView.isScrollEnabled)
        XCTAssertFalse(cell.test_scrollView.isZooming)
    }

    // MARK: - 自管变换

    /// scale 2 + translation：frame.size = fit×2，center = viewport 中心 + translation
    func testApplyTransformPositionsImageView() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 60, translationY: -40)
        let frame = cell.test_imageViewFrame
        XCTAssertEqual(frame.size.height, 312, accuracy: 1.0, "2× 时显示高 = 156×2")
        XCTAssertEqual(frame.midX, 390 / 2 + 60, accuracy: 1.0)
        XCTAssertEqual(frame.midY, 844 / 2 - 40, accuracy: 1.0)
        XCTAssertEqual(cell.test_zoomController.test_transform.scale, 2, accuracy: 1e-9)
    }

    /// resetZoom 回 1× 居中，transform 无残留
    func testResetReturnsToIdentity() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 3, translationX: 100, translationY: 0)
        XCTAssertEqual(cell.zoomScale, 3, accuracy: 1e-9)
        cell.resetZoom()
        XCTAssertEqual(cell.test_zoomController.test_transform, .identity)
        XCTAssertEqual(cell.test_imageViewFrame.midX, 390 / 2, accuracy: 1.0)
        XCTAssertEqual(cell.test_imageViewFrame.size.height, 156, accuracy: 1.0)
        XCTAssertFalse(cell.isZoomed)
    }

    /// prepareForReuse 后无缩放残留、无交互
    func testPrepareForReuseClearsTransformState() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 4, translationX: 200, translationY: 200)
        cell.prepareForReuse()
        XCTAssertEqual(cell.test_zoomController.test_transform, .identity, "复用后必须回 1×")
        XCTAssertEqual(cell.zoomScale, 1, accuracy: 1e-9)
        XCTAssertFalse(cell.test_zoomController.isInteracting)
        XCTAssertNil(cell.itemID)
    }

    /// 旋转：viewport 390x844 → 844x390，relayout 后仍满足钳制（内容小于新视口的轴归零）
    func testRelayoutOnRotationClamps() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // 竖图 500x1200：fit 351.7x844；scale 2 显示 703x1688，两轴均可平移
        cell.configure(item: makeItem(), image: makeImage(500, 1200))
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.test_applyTransform(scale: 2, translationX: 100, translationY: -100)
        // 旋转到横屏：新 viewport 844x390 → 显示宽 703 < 844 → tx 归零；ty 重新钳制
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        let t = cell.test_zoomController.test_transform
        XCTAssertEqual(t.scale, 2, accuracy: 1e-9, "旋转保持缩放倍率")
        XCTAssertEqual(t.translationX, 0, accuracy: 1e-9, "新视口下内容宽 703 < 844 → 水平居中")
        XCTAssertLessThanOrEqual(abs(t.translationY), (1688 - 390) / 2 + 1e-9, "垂直不露白")
        let frame = cell.test_imageViewFrame
        XCTAssertEqual(frame.midX, 844 / 2, accuracy: 1.0, "旋转后水平居中")
    }

    // MARK: - 交互护栏

    /// 无图必须禁手势（有效 bounds 也一样）
    func testInteractionRequiresImage() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: nil)
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertFalse(cell.test_zoomController.test_areGesturesEnabled, "无图必须禁交互")
    }

    // MARK: - 云占位

    /// 上游 isCloudOnly=false 时，VC 收到 inCloud 回传后 showCloudPlaceholder() 必须显示占位 + 下载入口
    func testShowCloudPlaceholderWorksEvenWhenItemNotMarkedCloudOnly() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(isCloudOnly: false), image: nil)
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertTrue(cell.test_cloudBox.isHidden, "非云图回传前不主动占位")
        cell.showCloudPlaceholder()
        XCTAssertFalse(cell.test_cloudBox.isHidden,
                       "inCloud 回传后必须显示占位（自救路径）")
        XCTAssertFalse(cell.test_zoomController.test_areGesturesEnabled, "占位态禁用捏合")
    }

    /// item.isCloudOnly=true（正常路径）配置即占位，且不启用交互
    func testCloudOnlyItemConfiguresPlaceholder() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(isCloudOnly: true), image: nil)
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertFalse(cell.test_cloudBox.isHidden, "云图配置即应显示占位")
        XCTAssertFalse(cell.test_zoomController.test_areGesturesEnabled, "占位态禁用捏合")
    }

    /// hasImage 锚点（VC appear 重挂判断 + 横幅 img 字段）
    func testHasImageReflectsState() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: nil)
        XCTAssertFalse(cell.hasImage)
        cell.applyDownloadedImage(makeImage())
        XCTAssertTrue(cell.hasImage)
    }
}
