// MARK: - ZoomStabilityUITests：自管变换缩放稳定性矩阵（docs/25 §4.8 / M15 P0-1）——
// 断言口径：500 轮捏合 0 崩溃、翻页/复用/旋转/双击后存活、放大平移不翻页、1× 平移翻页、
// 捏合零删除事务。全部用 Viewer-ZoomScrollView 真捏合，横幅字段（zoom/frameW/idx/pendingDeleteCount）
// 做取证；旧 UIScrollView 缩放时代的实现细节断言已一并废止。

import XCTest

final class ZoomStabilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - helper（与 StabilityUITests 同款，按文件私有复制）

    private func installPermissionMonitor() {
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for index in 0..<alert.buttons.count {
                let button = alert.buttons.element(boundBy: index)
                let label = button.label
                let isAllow = label.contains("Allow") || label.contains("允许")
                let isDeny = label.contains("Don't") || label.contains("不允许")
                if isAllow && !isDeny {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    @discardableResult
    private func launchToGrid(_ app: XCUIApplication) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += ["-uiTestingKeepChrome", "-uiTestingFilterYear", "0"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现\n\(hierarchy(app))")
        let cellReady = collection.cells.firstMatch.waitForExistence(timeout: 15)
        if !cellReady {
            snap(app, "fail-grid-no-cells")
        }
        XCTAssertTrue(cellReady, "网格无 cell debug=\(String(app.debugDescription.prefix(3000)))")
        return collection
    }

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func hierarchy(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        return tree.count > 8000 ? String(tree.prefix(8000)) + "…(截断)" : tree
    }

    private func assertAlive(_ app: XCUIApplication, _ message: String) {
        XCTAssertEqual(app.state, .runningForeground,
                       "\(message)（app.state=\(app.state.rawValue)）\n\(hierarchy(app))")
    }

    private func viewerRoot(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["ViewerRoot"]
    }

    private func viewerBanner(_ app: XCUIApplication) -> XCUIElement {
        anyElement(app, identifier: "Viewer-Debug")
    }

    @discardableResult
    private func openViewer(_ app: XCUIApplication, startIndex: Int, downAction: String? = nil) -> XCUIElement {
        app.launchArguments += ["-uiTestingSessionMock", "-uiTestingKeepChrome"]
        if let downAction {
            app.launchArguments += ["-gesture.down", downAction]
        }
        app.launchArguments += ["-uiTestingViewerStartIndex", "\(startIndex)"]
        _ = launchToGrid(app)
        let viewer = viewerRoot(app)
        XCTAssertTrue(viewer.waitForExistence(timeout: 10),
                      "-uiTestingViewerStartIndex \(startIndex) 未打开查看器\n\(hierarchy(app))")
        return viewer
    }

    private func swipeLeftFast(in element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.02, thenDragTo: end)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func parseField(_ label: String, _ key: String) -> Int {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)=(-?[0-9]+)", options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Int(label[range]) ?? -1
    }

    private static func parseDoubleField(_ label: String, _ key: String) -> Double {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)=(-?[0-9]+(?:\\.[0-9]+)?)", options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Double(label[range]) ?? -1
    }

    private func centerNonBlackRatio(_ screenshot: XCUIScreenshot) -> Double {
        guard let cg = screenshot.image.cgImage else { return 0 }
        let width = cg.width
        let height = cg.height
        let x0 = Int(Double(width) * 0.15)
        let x1 = Int(Double(width) * 0.85)
        let y0 = Int(Double(height) * 0.20)
        let y1 = Int(Double(height) * 0.72)
        guard x1 > x0, y1 > y0 else { return 0 }
        let regionWidth = x1 - x0
        let regionHeight = y1 - y0
        let region = CGRect(x: x0, y: y0, width: regionWidth, height: regionHeight)
        guard let context = CGContext(data: nil,
                                      width: regionWidth,
                                      height: regionHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: regionWidth * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return 0 }
        context.draw(cg, in: CGRect(origin: .zero, size: region.size))
        let total = regionWidth * regionHeight
        let buffer = data.bindMemory(to: UInt8.self, capacity: total * 4)
        var nonBlack = 0
        for index in 0..<total {
            let r = buffer[index * 4]
            let g = buffer[index * 4 + 1]
            let b = buffer[index * 4 + 2]
            if r > 24 || g > 24 || b > 24 { nonBlack += 1 }
        }
        return Double(nonBlack) / Double(max(1, total))
    }

    private func assertViewerImageVisible(_ app: XCUIApplication, _ message: String) {
        let ratio = centerNonBlackRatio(app.screenshot())
        XCTAssertGreaterThan(ratio, 0.05,
                             "\(message)：中心区域非背景像素占比 \(String(format: "%.3f", ratio))")
    }

    // MARK: - 主 soak：500 轮捏合

    /// docs/26 §5.6：100 轮 × 5 组（pinch 0.45 / 2.2 交替），每 10 轮 assertAlive；
    /// 结束后 viewport 存在、frameW > 0、img=ok、像素非背景、0 删除事务。
    func testPinch500Cycles() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        let inner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 8),
                      "cell 内 UIScrollView 未以 Viewer-ZoomScrollView 暴露\n\(hierarchy(app))")
        XCTAssertGreaterThan(inner.frame.width, 0)
        for group in 0..<5 {
            for round in 0..<100 {
                inner.pinch(withScale: 0.45, velocity: -1.4)
                inner.pinch(withScale: 2.2, velocity: 1.4)
                if round % 10 == 9 {
                    assertAlive(app, "捏合组 \(group + 1) 第 \(round + 1) 轮后")
                }
            }
        }
        for _ in 0..<10 {
            inner.doubleTap()
        }
        assertAlive(app, "500 轮捏合 + 10 次双击后")
        let label = banner.label.lowercased()
        let rawLabel = banner.label
        XCTAssertFalse(label.contains("nan"), "横幅出现 NaN：\(banner.label)")
        XCTAssertTrue(label.contains("img=ok"), "大图未成功加载：\(banner.label)")
        XCTAssertGreaterThan(Self.parseDoubleField(rawLabel, "frameW"), 0,
                             "imageView 显示宽度必须 > 0：\(banner.label)")
        XCTAssertEqual(Self.parseField(label, "pendingDeleteCount"), 0,
                       "捏合全过程 pendingDeleteCount 必须为 0：\(banner.label)")
        XCTAssertEqual(Self.parseField(label, "traceNonFinite"), 0,
                       "viewer-trace 不得出现 non-finite / NaN：\(banner.label)")
        assertViewerImageVisible(app, "500 轮捏合后大图像素必须非背景色")
        let close = anyElement(app, identifier: "Viewer-Close")
        XCTAssertTrue(close.exists, "查看器顶部关闭按钮仍应可达\n\(hierarchy(app))")
        snap(app, "m15-pinch-500-cycles")
    }

    /// 旧 testPinchHitsInnerScrollView 语义收窄版：viewport 存在、frameW>0、100 轮存活、img=ok。
    func testPinchHitsInnerScrollView() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        let inner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 8),
                      "cell 内 UIScrollView 未以 Viewer-ZoomScrollView 暴露\n\(hierarchy(app))")
        XCTAssertGreaterThan(inner.frame.width, 0)
        for round in 0..<100 {
            inner.pinch(withScale: 0.45, velocity: -1.4)
            inner.pinch(withScale: 2.2, velocity: 1.4)
            if round % 10 == 9 {
                assertAlive(app, "内层 scrollView 捏合第 \(round + 1) 轮后")
            }
        }
        assertAlive(app, "100 轮捏合后")
        let label = banner.label.lowercased()
        XCTAssertTrue(label.contains("img=ok"), "大图未成功加载：\(banner.label)")
        XCTAssertGreaterThan(Self.parseDoubleField(banner.label, "frameW"), 0,
                             "imageView 显示宽度必须 > 0：\(banner.label)")
        assertViewerImageVisible(app, "真捏合后大图像素必须非背景色")
        snap(app, "m15-inner-scrollview-pinch")
    }

    /// 放大 → 翻页 → 再捏合 → 返回 → 再捏合
    func testPinchAfterPageChange() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        let inner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 8), "内层 scrollView 未出现\n\(hierarchy(app))")
        inner.pinch(withScale: 2.2, velocity: 1.4)
        swipeLeftFast(in: viewer)
        Thread.sleep(forTimeInterval: 0.5)
        let nextInner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(nextInner.waitForExistence(timeout: 5), "翻页后内层 scrollView 未出现\n\(hierarchy(app))")
        nextInner.pinch(withScale: 0.45, velocity: -1.4)
        nextInner.pinch(withScale: 2.2, velocity: 1.4)
        viewer.swipeRight()
        Thread.sleep(forTimeInterval: 0.5)
        let backInner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(backInner.waitForExistence(timeout: 5), "返回上一张后内层 scrollView 未出现\n\(hierarchy(app))")
        backInner.pinch(withScale: 0.45, velocity: -1.4)
        backInner.pinch(withScale: 2.2, velocity: 1.4)
        assertAlive(app, "翻页往返 + 四次捏合后")
        XCTAssertTrue(banner.label.contains("img=ok"), "翻页后当前图未加载：\(banner.label)")
        XCTAssertEqual(Self.parseField(banner.label.lowercased(), "pendingDeleteCount"), 0,
                       "翻页捏合不得进入待删除事务：\(banner.label)")
        snap(app, "m15-pinch-after-page-change")
    }

    /// 快速翻 10 页后立即捏合（cell 复用竞态）
    func testPinchAfterReuse() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        for _ in 0..<10 {
            swipeLeftFast(in: viewer)
            Thread.sleep(forTimeInterval: 0.15)
        }
        let inner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 5), "复用后内层 scrollView 未出现\n\(hierarchy(app))")
        inner.pinch(withScale: 2.2, velocity: 1.4)
        inner.pinch(withScale: 0.45, velocity: -1.4)
        assertAlive(app, "快速翻 10 页后捏合")
        XCTAssertTrue(banner.label.contains("img=ok"), "复用后当前图未加载：\(banner.label)")
        snap(app, "m15-pinch-after-reuse")
    }

    /// 旋转后捏合（自管变换 relayout 路径）
    func testPinchAfterRotation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        let inner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 8), "内层 scrollView 未出现\n\(hierarchy(app))")
        inner.pinch(withScale: 2.2, velocity: 1.4)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.0)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.0)
        let rotated = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(rotated.waitForExistence(timeout: 5), "旋转后内层 scrollView 未出现\n\(hierarchy(app))")
        rotated.pinch(withScale: 0.45, velocity: -1.4)
        rotated.pinch(withScale: 2.2, velocity: 1.4)
        assertAlive(app, "旋转 + 捏合后")
        XCTAssertTrue(banner.label.contains("img=ok"), "旋转后当前图未加载：\(banner.label)")
        XCTAssertGreaterThan(Self.parseDoubleField(banner.label, "frameW"), 0,
                             "旋转后 imageView 必须重新布局：\(banner.label)")
        snap(app, "m15-pinch-after-rotation")
    }

    /// 双击 50 次：1× ↔ 2.5× 循环，0 崩溃
    func testDoubleTap50() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.0)
        for index in 0..<50 {
            viewer.doubleTap()
            if index % 10 == 9 {
                assertAlive(app, "双击第 \(index + 1) 次后")
            }
        }
        assertAlive(app, "50 次双击后")
        XCTAssertTrue(banner.label.contains("img=ok"), "双击循环后当前图未加载：\(banner.label)")
        snap(app, "m15-double-tap-50")
    }

    /// 捏合全程零删除事务（配 moveToRecentlyDeleted 下滑动作）
    func testPinchDoesNotTriggerRemoval() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 5, downAction: "moveToRecentlyDeleted")
        Thread.sleep(forTimeInterval: 1.0)
        let target: XCUIElement = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : viewer
        for _ in 0..<10 {
            target.pinch(withScale: 2.5, velocity: 2)
            target.pinch(withScale: 0.4, velocity: -2)
        }
        assertAlive(app, "10 轮捏合后")
        let badge = anyElement(app, identifier: "SessionBadge")
        let badgeLabel = badge.exists ? badge.label : ""
        XCTAssertFalse(badgeLabel.contains("待删除"),
                       "捏合过程不得触发删除事务（badge=\(badgeLabel)）")
        var zoomSeen = -1
        let inner = app.scrollViews["Viewer-ZoomScrollView"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 5), "内层 viewport 未出现\n\(hierarchy(app))")
        let zoomDeadline = Date().addingTimeInterval(3)
        while Date() < zoomDeadline {
            // 双击必须打在内层 viewport（真实 UIView，center 即图心）；
            // ViewerRoot 是 otherElement，其 center 不可靠（双击从未命中的实锤根因）
            inner.doubleTap()
            Thread.sleep(forTimeInterval: 0.5)
            let bannerNow = viewerBanner(app)
            if bannerNow.exists {
                zoomSeen = Self.parseField(bannerNow.label, "zoom")
                if zoomSeen > 1 { break }
            }
        }
        XCTAssertGreaterThan(zoomSeen, 1,
                             "双击后 zoom 应 > 1（手势链路核验，3s 轮询）：\(viewerBanner(app).label)")
        snap(app, "m15-pinch-no-removal")
    }

    /// 放大后横向拖动只平移不翻页；复位后横向拖动翻页
    func testZoomedPanDoesNotPage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 2)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.0)
        let startIdx = Self.parseField(banner.label, "idx")
        XCTAssertGreaterThanOrEqual(startIdx, 0, "横幅必须暴露 idx：\(banner.label)")
        viewer.doubleTap()
        Thread.sleep(forTimeInterval: 0.8)
        // 放大态横向拖动：cell 内平移，不得翻页
        let start = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.5)
        let zoomedIdx = Self.parseField(viewerBanner(app).label, "idx")
        XCTAssertEqual(zoomedIdx, startIdx, "放大态横向拖动不得翻页")
        // 双击复位后横向拖动翻页
        viewer.doubleTap()
        Thread.sleep(forTimeInterval: 0.8)
        swipeLeftFast(in: viewer)
        Thread.sleep(forTimeInterval: 0.5)
        let pagedIdx = Self.parseField(viewerBanner(app).label, "idx")
        XCTAssertEqual(pagedIdx, startIdx + 1, "1× 横向拖动必须翻页")
        assertAlive(app, "放大平移/复位翻页后")
        snap(app, "m15-zoomed-pan")
    }

    /// 1× 时横向拖动翻页（护栏不误关翻页）
    func testOneXPanPages() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 0)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.0)
        swipeLeftFast(in: viewer)
        Thread.sleep(forTimeInterval: 0.4)
        let idx = Self.parseField(viewerBanner(app).label, "idx")
        XCTAssertGreaterThanOrEqual(idx, 1, "1× 横向拖动必须翻页：\(viewerBanner(app).label)")
        assertAlive(app, "1× 翻页后")
        snap(app, "m15-one-x-pan")
    }
}
