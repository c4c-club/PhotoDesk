// MARK: - 职责说明：ZoomableImageCell 几何与交互护栏单元测试（docs/16 M12 R01/R02）——
// 基线红：A1 imageView 恒零尺寸（无约束）；B2 零 bounds 仍启用交互；B3 inset 双倍缩放。
// 通过 #if DEBUG test_ 访问器断言 I5′ 不变量（Release 不编译访问器）。

import XCTest
import UIKit
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
        cell.frame = window.bounds.insetBy(dx: 0, dy: 0)
        window.layoutIfNeeded()
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
    }

    // MARK: - R01/A1：imageView 尺寸

    /// 赋图并布局后：imageView.frame == zoomContentView.frame > 0，contentSize 与之一致（I5′）
    func testImageViewFrameMatchesZoomContentViewAfterImageApplied() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage())
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let zoom = cell.test_zoomContentView.frame
        XCTAssertGreaterThan(zoom.width, 0, "zoomContentView 必须有尺寸")
        XCTAssertGreaterThan(zoom.height, 0)
        XCTAssertEqual(cell.test_imageView.frame.size, zoom.size,
                       "A1：imageView 必须与 zoomContentView 同尺寸（旧版无约束恒 .zero → 全屏黑屏）")
        XCTAssertEqual(cell.test_scrollView.contentSize, zoom.size,
                       "contentSize 必须等于 zoomContentView 尺寸（I5′）")
    }

    /// 零 bounds 配置 → 正常 bounds 布局后必须自恢复（A1/A4 恢复路径）
    func testZeroBoundsThenLayoutRecovers() {
        let cell = ZoomableImageCell(frame: .zero)
        cell.configure(item: makeItem(), image: makeImage())
        // B2 护栏：零 bounds 无图可显示 → 交互必须关闭（旧版 configure 直接置 true → 红点）
        XCTAssertFalse(cell.test_scrollView.isUserInteractionEnabled,
                       "B2：零 bounds 时禁止捏合交互")
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(cell.test_imageView.frame.size, cell.test_zoomContentView.frame.size,
                       "布局恢复后 imageView 必须拿到尺寸")
        XCTAssertGreaterThan(cell.test_imageView.frame.width, 0)
        XCTAssertTrue(cell.test_scrollView.isUserInteractionEnabled,
                      "布局恢复 + 有图后才允许交互")
    }

    // MARK: - R02/B2：交互护栏

    /// 无图必须禁交互（有效 bounds 也一样）
    func testInteractionRequiresImage() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: nil)
        cell.layoutIfNeeded()
        XCTAssertFalse(cell.test_scrollView.isUserInteractionEnabled, "无图必须禁交互")
    }

    /// 零 contentSize 时 viewForZooming 必须返回 nil（旧版返回零尺寸 view → UIScrollView 内部除零 → NaN）
    func testViewForZoomingNilOnZeroContentSize() {
        let cell = ZoomableImageCell(frame: .zero)
        cell.configure(item: makeItem(), image: makeImage())
        XCTAssertNil(cell.viewForZooming(in: cell.test_scrollView),
                     "B2：零 contentSize 时 viewForZooming 返回 nil，杜绝 CALayer position NaN")
    }

    // MARK: - R02/B3：居中 inset 不受 transform 污染

    /// 放大到 2× 后：inset 必须按「未变换 bounds × zoomScale」计算。
    /// 500×200 图 aspectFit 进 390×844 → 390×156；正确 inset.top = (844-156×2)/2 = 266；
    /// 旧版读变换后 frame（390×312）再乘 2 → (844-312×2)/2 = 110（双倍缩放 inset）。
    func testCenteringInsetUsesUntransformedBounds() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(), image: makeImage(500, 200))
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let baseHeight = cell.test_zoomContentView.bounds.height
        XCTAssertEqual(baseHeight, 156, accuracy: 1.0, "aspectFit 基准高度应为 156")
        cell.test_scrollView.setZoomScale(2, animated: false)
        // M13 状态机：setZoomScale 触发 didZoom → 事务 active，inset 推迟到 settling 批量提交
        //（生产由 0.4s 宽限定时器触发；单测无 runloop，显式驱动同一条 commitPendingGeometry 路径）。
        cell.test_flushPendingGeometry()
        let inset = cell.test_scrollView.contentInset
        let expected = (844 - baseHeight * 2) / 2
        XCTAssertEqual(inset.top, expected, accuracy: 1.0,
                       "B3：inset.top 应为 \(expected)（旧版双倍缩放会算出 110）")
        XCTAssertEqual(inset.bottom, inset.top, accuracy: 1.0)
    }

    // MARK: - R01/A2：云占位

    /// 上游 isCloudOnly=false（旧上游恒 false）时，VC 收到 inCloud 回传后调用
    /// showCloudPlaceholder() 必须显示占位 + 下载入口
    func testShowCloudPlaceholderWorksEvenWhenItemNotMarkedCloudOnly() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(isCloudOnly: false), image: nil)
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertTrue(cell.test_cloudBox.isHidden, "非云图回传前不主动占位")
        cell.showCloudPlaceholder()
        XCTAssertFalse(cell.test_cloudBox.isHidden,
                       "A2：inCloud 回传后必须显示占位（旧版 isCloudOnly 恒 false → 恒隐藏 → 纯黑无自救）")
    }

    /// item.isCloudOnly=true（正常路径）配置即占位，且不启用交互
    func testCloudOnlyItemConfiguresPlaceholder() {
        let cell = ZoomableImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.configure(item: makeItem(isCloudOnly: true), image: nil)
        layoutInWindow(cell, frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertFalse(cell.test_cloudBox.isHidden, "云图配置即应显示占位")
        XCTAssertTrue(cell.test_scrollView.isUserInteractionEnabled == false,
                      "占位态禁用捏合")
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
