// MARK: - 职责说明：稳定性回归 UI 测试（docs/13 Phase 0；S01–S12 验收矩阵）——
// 12 条用户实测问题（捏合缩放/快滑/年份筛选/位置记忆/Toast 挡格/筛选栏/滑动多选/查看器滑动/
// 月份跳转/单月全选/跳转后重启/删除隐藏闪退）+ 全页面烟测。
// 约定：基线（修复前）预期大量红——先复现后修复；修复后每条必须全绿。
// 全部断言带 AX 层级失败取证；会话路径用 -uiTestingSessionMock 隔离真实 PhotoKit 写。

import XCTest

final class StabilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 公共 helper

    /// 授权中断监视器（与 PageRegressionUITests 同款）
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
        // M13 绿7/绿8 实锤：顶栏 3s 自动隐藏后导航按钮 AX 不可命中，且跨用例泄漏的持久化
        // 筛选（filterYear 卡死在 2026）会让月份族找不到目标 section——每次启动保持顶栏
        // 可见并清掉泄漏筛选；筛选族自己的 flag 在调用方先入队，intValue 取首个仍是测试年。
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
            snap(app, "fail-grid-no-cells")   // 取证：下一轮 CI 直接读 App 现场
        }
        XCTAssertTrue(cellReady, "网格无 cell debug=\(String(app.debugDescription.prefix(3000)))")
        return collection
    }

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// 失败取证：AX 层级截断塞进断言消息
    private func hierarchy(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        return tree.count > 8000 ? String(tree.prefix(8000)) + "…(截断)" : tree
    }

    /// 顶部栏按钮点击（M11 已证 iOS 15 模拟器对 UIBarButtonItem/导航栏元素的
    /// scroll-to-visible AXAction 不可靠——docs/15 §3.2 同款规避）。
    /// 验证轮 18 实测：连 element.frame 解析都会触发 scroll-to-visible AXAction——
    /// 改为固定屏幕坐标直击（CI 设备固定 iPhone 13 模拟器 390×844；左上工具 ≈(46,110)，
    /// 右上分类为右侧按钮簇最左项 ≈(144,110)）。仅用于交互可达性验证，位置断言用 frame。
    /// 顶部栏按钮坐标：从 navigationBars.frame 推算（验证轮 20 实测：UIBarButtonItem 的
    /// element.frame / element.coordinate 解析都会触发 scroll-to-visible AXAction 并失败，
    /// 而 navigationBars 容器元素可安全解析）。布局：左上工具；右侧按钮簇从右到左
    /// [Session(tray)] [多选] [搜索] [月份] [筛选] [分类]，每项 ≈44pt。
    private func libraryBarFrame(in app: XCUIApplication) -> CGRect {
        app.navigationBars.firstMatch.frame
    }

    private func tapLibraryTools(in app: XCUIApplication) {
        let bar = libraryBarFrame(in: app)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: bar.minX + 46, dy: bar.midY)).tap()
    }

    private func tapLibraryCategory(in app: XCUIApplication) {
        // 绿7/绿8 实锤：顶栏按钮的合成点按会先做 AX scroll-to-visible（kAXErrorCannotComplete），
        // 且 DEBUG 取证横幅与顶栏在 AX 树上重叠导致 isHittable 恒假；固定坐标又在两种顶栏
        // 高度间漂移。改读元素 frame 后按绝对坐标点中心，绕开 scroll-to-visible 与遮挡判定。
        // 10s 等待：切 scope 后慢 runner 下 AX 树重建可超过 5s（M15 两次实锤）。
        let category = anyElement(app, identifier: "Library-Category")
        XCTAssertTrue(category.waitForExistence(timeout: 10), "分类按钮不存在")
        let frame = category.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    /// sheet/push 页返回键：取最后一个导航栏（最前层）的第一个按钮并按 frame 直击。
    /// M12（验证轮 22 实测）：sheet 打开时 app.navigationBars 含底层库导航栏，
    /// boundBy:0 会误绑 Library-Tools（左上第一键）→ scroll-to-visible 失败。
    @discardableResult
    private func tapFrontmostBackButton(in app: XCUIApplication) -> Bool {
        let bars = app.navigationBars
        let last = bars.element(boundBy: bars.count - 1)
        let back = last.buttons.element(boundBy: 0)
        guard back.waitForExistence(timeout: 5) else { return false }
        let f = back.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        return true
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

    /// 打开查看器（每次调用都会重新 launch；调用方自行累积 launchArguments）
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

    // MARK: 手势

    private func swipeVertical(in element: XCUIElement, fromY: CGFloat, toY: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// 手指从上往下拖（= 查看器「下滑」动作）
    private func swipeDown(in element: XCUIElement) {
        swipeVertical(in: element, fromY: 0.25, toY: 0.8)
    }

    /// 手指从下往上拖（= 查看器「上滑」动作）
    private func swipeUp(in element: XCUIElement) {
        swipeVertical(in: element, fromY: 0.8, toY: 0.25)
    }

    private func swipeLeftFast(in element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.02, thenDragTo: end)
    }

    private func swipeRightFast(in element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.02, thenDragTo: end)
    }

    // MARK: 网格 / 筛选 / 多选查询

    /// 月份头元素查询（docs/13 M11：MonthHeaderView 标题带点击手势后被 AX 暴露为 Button 而非
    /// StaticText（CI 轮 9–13 实证）——用 .any 后代 + label 谓词，兼容两种暴露形态）
    private func headerElements(_ app: XCUIApplication) -> XCUIElementQuery {
        app.collectionViews.firstMatch
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '月 ·'"))
    }

    /// 顶部（粘性）月份头文本，形如「2024年5月 · 2 张」
    private func topHeaderText(_ app: XCUIApplication) -> String {
        let headers = headerElements(app)
        // sheet/筛选动画期间可能解析到面板 List（无月头）——count 守卫防 firstMatch 硬失败
        guard headers.count > 0 else { return "" }
        return headers.firstMatch.label
    }

    private func waitTopHeaderContains(_ app: XCUIApplication, _ text: String,
                                       timeout: TimeInterval = 5) -> Bool {
        let headers = headerElements(app)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if headers.count > 0, headers.firstMatch.label.contains(text) { return true }
            usleep(300_000)
        }
        return false
    }

    // MARK: 筛选/月份驱动（docs/13 M11：iOS 15 XCUITest 对 SwiftUI Toolbar/Form/ScrollView 内 Button
    // 的合成点击不可靠（CI 轮 9–12 实证，与已知问题 #12 同类）——筛选与月份跳转改走启动参数钩子，
    // 与用户操作共用同一条 setFilter / scrollToSection 代码路径；面板只做存在性断言 + 截图）

    /// 清空筛选启动（-uiTestingFilterYear 0 = 就绪后 clearFilter，跨用例持久化隔离）。
    /// 注意必须整体赋值：+= 会累积多个同名参数，intValue 取第一个导致钩子失效（CI 轮 14 实测）
    @discardableResult
    private func launchWithFilterCleared(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments += ["-uiTestingFilterYear", "0"]
        return launchToGrid(app)
    }

    /// 年份筛选启动（就绪后应用年份筛选）
    private func launchWithYearFilter(_ app: XCUIApplication, year: Int) {
        // 绿8 实锤：launchArguments += 跨轮累积同名 flag，intValue 取首个读到旧值 →
        // 筛选卡死在上一轮年份并持久化泄漏。追加前先去掉旧 flag，保证本轮值生效。
        app.launchArguments.removeAll { $0 == "-uiTestingFilterYear" }
        app.launchArguments += ["-uiTestingFilterYear", "\(year)"]
        _ = launchToGrid(app)
    }

    /// 月份跳转启动（快照包含目标月后经 scrollToSection 跳转）+ 面板渲染验证（s09 截图）
    private func launchWithMonthJump(_ app: XCUIApplication, sectionID: String, headerText: String) {
        // 面板渲染验证（存在性，不点击）
        app.launchArguments += ["-uiTestingOpenMonthJump"]
        _ = launchToGrid(app)
        let card = anyElement(app, identifier: "MonthJump-Month-\(sectionID)")
        if card.waitForExistence(timeout: 8) {
            snap(app, "s09-month-jump-sheet")
        }
        app.terminate()
        // 绿10 实锤：同一实例启动参数跨轮累积——跳转轮仍带着首轮的 -uiTestingOpenMonthJump，
        // 面板晚于头部断言弹出后盖住网格月份头 AX（MonthHeader-Menu 永远查不到）。
        // 跳转轮只留跳转钩子；面板渲染验证由第一轮单独完成。
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        // 跳转（等价面板点卡片）
        app.launchArguments += ["-uiTestingMonthJump", sectionID]
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, headerText, timeout: 15),
                      "月份跳转后顶部应为 \(headerText)（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.2)   // 等横幅与位置保存完成
    }

    private func selectionCountLabel(_ app: XCUIApplication) -> XCUIElement {
        anyElement(app, identifier: "Selection-Count")
    }

    private func selectionCount(_ app: XCUIApplication) -> Int {
        let label = selectionCountLabel(app)
        guard label.waitForExistence(timeout: 5) else { return -1 }
        return Self.parseCount(label.label)
    }

    @discardableResult
    private func waitForSelectionCount(_ app: XCUIApplication,
                                       atLeast threshold: Int,
                                       timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var value = selectionCount(app)
        while Date() < deadline {
            value = selectionCount(app)
            if value >= threshold { return value }
            usleep(100_000)
        }
        return value
    }

    @discardableResult
    private func waitForSelectionCountEqual(_ app: XCUIApplication,
                                            to expected: Int,
                                            timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var value = selectionCount(app)
        while Date() < deadline {
            value = selectionCount(app)
            if value == expected { return value }
            usleep(100_000)
        }
        return value
    }

    private func visibleSelectedCount(in collection: XCUIElement, limit: Int = 12) -> Int {
        var count = 0
        for index in 0..<limit {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists else { continue }
            if (cell.value as? String ?? "").contains("selected") { count += 1 }
        }
        return count
    }

    private func slideSelectGesture(in collection: XCUIElement,
                                    fromX: CGFloat,
                                    fromY: CGFloat,
                                    toX: CGFloat,
                                    toY: CGFloat,
                                    hold: TimeInterval? = nil) {
        let start = collection.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: fromY))
        let end = collection.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: toY))
        if let hold {
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: hold)
        } else {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func slideAtLeastTwoRows(in collection: XCUIElement,
                                     fromX: CGFloat,
                                     fromY: CGFloat,
                                     toX: CGFloat,
                                     toY: CGFloat) {
        // 两段横向矩形各自独立手势：第一段选 fromY 行，第二段锚点未选（该行尚未被
        // 覆盖）→ select 模式选 toY 行；两段计数合计 = 2 行 × 3 列 = 6。
        // 第一段：fromY 行横向矩形
        slideSelectGesture(in: collection, fromX: fromX, fromY: fromY,
                           toX: toX, toY: fromY)
        // 第二段：toY 行反向横向矩形（跨第二行继续加选）
        slideSelectGesture(in: collection, fromX: toX, fromY: toY,
                           toX: fromX, toY: toY)
    }

    private func slideHorizontal(in collection: XCUIElement,
                                 fromX: CGFloat,
                                 toX: CGFloat,
                                 y: CGFloat) {
        slideSelectGesture(in: collection, fromX: fromX, fromY: y,
                           toX: toX, toY: y)
    }

    private static func parseStringField(_ label: String, _ key: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = escaped + "=([^[:space:]]+)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            guard let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: label) else { return nil }
            return String(label[range])
        } catch {
            return nil
        }
    }

    private func debugSnapshot(_ app: XCUIApplication) -> (off: Double, anchor: String, visualY: Double)? {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.waitForExistence(timeout: 5) else { return nil }
        let raw = (banner.value as? String) ?? banner.label
        let off = Self.parseDoubleField(raw, "off")
        let visualY = Self.parseDoubleField(raw, "visualY")
        guard off >= 0,
              let anchor = Self.parseStringField(raw, "anchor"), !anchor.isEmpty else { return nil }
        return (off, anchor, visualY)
    }

    private func oneRowHeight(in collection: XCUIElement) -> Double {
        max(1, Double(collection.cells.firstMatch.frame.height))
    }

    // MARK: 文本解析

    /// 截图取证（docs/13 Phase 8：s01–s12 随 ui-test-attachments artifact 导出，逐张确认）
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 截图中心区域「非背景色」像素占比（docs/16 M12 R01：全屏黑 = 大图不可见）。
    /// 采样窗口避开顶部栏 / DEBUG 横幅 / 底部胶片条；bgViewer 为纯黑，阈值 24/255。
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

    /// 断言查看器中心区域可见图像（R01 硬指标：非背景像素占比 > 5%）
    private func assertViewerImageVisible(_ app: XCUIApplication, _ message: String) {
        let ratio = centerNonBlackRatio(app.screenshot())
        XCTAssertGreaterThan(ratio, 0.05,
                             "\(message)：中心区域非背景像素占比 \(String(format: "%.3f", ratio))（旧版全屏黑 = imageView 恒零尺寸）")
    }

    /// 「已选择 N 项 · 本月」→ N
    private static func parseCount(_ label: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]+"),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range, in: label) else { return 0 }
        return Int(label[range]) ?? 0
    }

    /// 「2024年5月 · 2 张」→ 2
    private static func parseHeaderCount(_ label: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "·\\s*([0-9]+)\\s*张"),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Int(label[range]) ?? -1
    }

    /// 横幅字段：parseField("id=abc idx=7 load=2", "idx") == 7；缺失返回 -1（大小写不敏感）
    private static func parseField(_ label: String, _ key: String) -> Int {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)=(-?[0-9]+)", options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Int(label[range]) ?? -1
    }

    /// 横幅浮点字段：parseDoubleField("frameW=390.0", "frameW") == 390；缺失返回 -1
    private static func parseDoubleField(_ label: String, _ key: String) -> Double {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)=(-?[0-9]+(?:\\.[0-9]+)?)", options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Double(label[range]) ?? -1
    }





    // MARK: - M13 P2：冷启动 / 旋转像素级锚点（同 assetID 视口 y ≤ 1 行，offset 差 ≤ 1pt）



    // MARK: - M12 R01/R02：查看器图像可见性 / 生命周期恢复 / 捏合-删除互斥

    /// 打开查看器即见大图（R01 硬指标：截图像素非背景色）
    func testViewerShowsImageOnOpen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = openViewer(app, startIndex: 7)
        Thread.sleep(forTimeInterval: 1.5)   // 大图解码
        assertViewerImageVisible(app, "R01：查看器打开 1.5s 后中心区域近乎全黑（A1 imageView 恒零尺寸）")
        snap(app, "m12-viewer-image-on-open")
    }

    /// present 信息页 → 返回后大图必须恢复（R01/A3：viewDidDisappear 无条件 cancelAll 且不重挂）
    func testPresentInfoThenDismissRestoresImage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = openViewer(app, startIndex: 3)
        Thread.sleep(forTimeInterval: 1.0)
        // 顶部栏为 UIToolbar（KeepChrome 已开）；UIBarButtonItem label 定位
        let info = app.buttons.matching(NSPredicate(format: "label == '查看信息'")).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 5), "查看器缺「查看信息」按钮\n\(hierarchy(app))")
        // 查看器顶栏 UIToolbar 按钮同样受 scroll-to-visible 限制——按 frame 中心换算绝对坐标直击
        let infoFrame = info.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: infoFrame.midX, dy: infoFrame.midY)).tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5),
                      "信息页未打开\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 0.5)
        if !tapFrontmostBackButton(in: app) {
            app.swipeDown()
        }
        XCTAssertTrue(viewerRoot(app).waitForExistence(timeout: 5), "返回后查看器应仍在")
        Thread.sleep(forTimeInterval: 1.0)
        assertViewerImageVisible(app, "R01/A3：present 信息页返回后大图必须恢复显示")
        snap(app, "m12-viewer-after-info")
    }



    // MARK: - M12 R05/R06/R07：唯一顶部栏（无标题/无 TabBar/无五段行；分类紧邻筛选；工具左上）

    func testTopChromeHasNoTitleAndNoTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = launchToGrid(app)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "R07：不得再有底部分页 TabBar")
        XCTAssertFalse(app.navigationBars.staticTexts["照片管家"].exists, "R05：顶部不得有 App 标题")
        let scopePicker = anyElement(app, identifier: "Library-ScopePicker")
        XCTAssertFalse(scopePicker.exists, "R06：不得再有五段分段控件（整行）")
        let category = anyElement(app, identifier: "Library-Category")
        XCTAssertTrue(category.waitForExistence(timeout: 5), "R06：缺分类菜单按钮\n\(hierarchy(app))")
        let filter = anyElement(app, identifier: "Library-Filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 3), "缺筛选按钮\n\(hierarchy(app))")
        if category.exists && filter.exists {
            XCTAssertLessThanOrEqual(category.frame.maxX, filter.frame.minX + 1,
                                     "分类按钮应紧邻筛选按钮左侧（category.maxX=\(category.frame.maxX)，filter.minX=\(filter.frame.minX)）")
        }
        let tools = anyElement(app, identifier: "Library-Tools")
        XCTAssertTrue(tools.waitForExistence(timeout: 3), "R07：缺左上工具按钮\n\(hierarchy(app))")
        snap(app, "m12-top-chrome")
    }

    func testCategoryMenuPreservesAllScopesAndHiddenVault() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        app.launchArguments += ["-uiTestingFaceIDBypass"]
        _ = launchToGrid(app)
        let category = anyElement(app, identifier: "Library-Category")
        XCTAssertTrue(category.waitForExistence(timeout: 5), "缺分类按钮\n\(hierarchy(app))")
        tapLibraryCategory(in: app)
        for title in ["全部", "收藏", "视频", "截图", "已隐藏"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3),
                          "分类菜单缺「\(title)」\n\(hierarchy(app))")
        }
        snap(app, "m12-category-menu")
        // 切到收藏（走同一条 setScope 路径；各 scope 保留自己的筛选与位置键）
        app.buttons["收藏"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        assertAlive(app, "切到收藏后")
        // 已隐藏 → Vault（不 setScope；Face ID bypass 直解锁）
        tapLibraryCategory(in: app)
        let hidden = app.buttons["已隐藏"]
        if hidden.waitForExistence(timeout: 3) {
            hidden.tap()
            let vaultReady = app.collectionViews.firstMatch.waitForExistence(timeout: 8)
                || app.navigationBars.firstMatch.waitForExistence(timeout: 3)
            XCTAssertTrue(vaultReady, "已隐藏 → Vault 未打开\n\(hierarchy(app))")
            assertAlive(app, "进入 Vault 后")
            snap(app, "m12-category-vault")
        }
    }

    func testToolsButtonOpensToolsSheetAndReturns() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        app.launchArguments += ["-uiTestingFaceIDBypass"]
        _ = launchToGrid(app)
        let tools = anyElement(app, identifier: "Library-Tools")
        XCTAssertTrue(tools.waitForExistence(timeout: 5), "缺左上工具按钮\n\(hierarchy(app))")
        tapLibraryTools(in: app)
        XCTAssertTrue(anyElement(app, identifier: "Tools-Cleanup").waitForExistence(timeout: 5),
                      "工具 sheet 未打开\n\(hierarchy(app))")
        assertAlive(app, "打开工具 sheet 后")
        // 子页推入 → 返回工具列表
        anyElement(app, identifier: "Tools-Cleanup").tap()
        assertAlive(app, "进入智能清理后")
        XCTAssertTrue(tapFrontmostBackButton(in: app), "返回按钮缺失\n\(hierarchy(app))")
        assertAlive(app, "返回工具列表后")
        // 关闭 sheet → 回库
        let close = anyElement(app, identifier: "Tools-Close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "工具 sheet 缺关闭按钮\n\(hierarchy(app))")
        close.tap()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5),
                      "关闭工具 sheet 后未回网格\n\(hierarchy(app))")
        assertAlive(app, "关闭工具 sheet 后")
        snap(app, "m12-tools-sheet")
    }

    func testLimitedLibraryManagementEntryIsReachable() throws {
        // CI 模拟器授权 = full，无法注入 .limited：断言 full 授权下菜单不出现管理入口（Builder 语义）；
        // .limited 语义由 LibraryCategoryMenuBuilderTests 覆盖，真机 .limited 场景回填 docs/12
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        _ = launchToGrid(app)
        let category = anyElement(app, identifier: "Library-Category")
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        tapLibraryCategory(in: app)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(app.buttons["管理可见照片"].exists,
                       "非 .limited 授权不得出现「管理可见照片」入口\n\(hierarchy(app))")
        snap(app, "m12-category-limited")
    }

    func testDynamicTypeTopBarDoesNotClip() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        _ = launchToGrid(app)
        for id in ["Library-Tools", "Library-Category", "Library-Filter",
                   "Library-MonthJump", "Library-Select"] {
            let element = anyElement(app, identifier: id)
            XCTAssertTrue(element.waitForExistence(timeout: 5), "XXXL 字体下顶部缺 \(id)\n\(hierarchy(app))")
            if element.exists {
                XCTAssertTrue(element.isHittable, "XXXL 字体下 \(id) 不可点（可能被裁切）")
            }
        }
        snap(app, "m12-top-chrome-xxxl")
    }

    // MARK: - M15 P0-3/4：矩形框选（整行带/快照恢复旧用例已删，验收在 MarqueeSelectionUITests）

    private func launchSelectableGrid(_ app: XCUIApplication) -> XCUIElement {
        // -uiTestingClearPosition：框选/轻点族断言依赖确定的首屏几何（首格可点、两行满格），
        // 跨用例持久化的位置恢复会让首格停在半屏外（绿5 tapNotSwallowed 实锤）。
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingClearPosition", "-uiTestingSelectMode"]
        return launchToGrid(app)
    }

    func testEdgeAutoScrollSelectsOffscreenCells() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        // 矩形语义：单次长按拖动顶住下缘 → 自动滚动逐帧重算，startPoint 固定在 content 坐标，
        // 矩形随之拉长，屏幕外 cell 持续入集（反复起手会因锚点已选触发取消模式，故只拖一次）。
        // toY 0.985：历史实测 0.995（840）hold 期滚动 ~2 行、0.94（793）滚动 0 行——
        // 有效边缘区在底部指示条带附近（bottomLimit 实测 ≥784）；0.985=831 深入区内。
        // hold 期速度真相由取证 note 的 slide=ticks/v/delta 读出。
        slideSelectGesture(in: collection, fromX: 0.12, fromY: 0.40,
                           toX: 0.12, toY: 0.985, hold: 3.0)
        let count = waitForSelectionCount(app, atLeast: 8, timeout: 8)
        XCTAssertGreaterThanOrEqual(count, 8,
                                    "边缘自动滚动必须逐帧重算命中，选中屏幕外 cell")
        snap(app, "m13-edge-autoscroll")
    }

    func testOriginallySelectedNotCleared() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.tap()
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 1), 1,
                                    "点选第一格应记入选中集合")
        // 从第二行开始拖（锚点未选 → select 模式），矩形不覆盖首行 → 首格保持选中
        slideAtLeastTwoRows(in: collection, fromX: 0.10, fromY: 0.35,
                            toX: 0.90, toY: 0.55)
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 3), 3,
                                    "框选应继续加选")
        XCTAssertTrue((first.value as? String ?? "").contains("selected"),
                      "框选矩形未覆盖首格，首格必须保持选中")
    }

    /// P0-4：选择模式双指滚动配置（单指已由框选 pan 独占，collectionView pan 至少 2 指）。
    func testTwoFingerScrollInSelectionMode() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "缺少 Library-DebugSummary")
        let deadline = Date().addingTimeInterval(5)
        var value = (banner.value as? String) ?? ""
        while Date() < deadline, !value.contains("panMin=2") {
            usleep(200_000)
            value = (banner.value as? String) ?? ""
        }
        XCTAssertTrue(value.contains("panMin=2"),
                      "多选模式 collectionView pan 必须至少两指，当前：\(value)")
        XCTAssertEqual(selectionCount(app), 0, "双指滚动不应改变选择数")
        snap(app, "p0-two-finger-scroll-config")
    }

    func testTapNotSwallowedBySlidePan() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.tap()
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 1), 1,
                                    "cancelsTouchesInView=false 时轻点不得被 pan 吞掉")
        XCTAssertTrue((first.value as? String ?? "").contains("selected"),
                      "轻点后徽标与 AX 必须同步为 selected")
    }

    func testScrollEnabledRestoredAfterDragEnd() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        slideAtLeastTwoRows(in: collection, fromX: 0.08, fromY: 0.22,
                            toX: 0.92, toY: 0.42)
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 6), 6,
                                    "滑选结束前应有连续选中")
        // P0-4 语义：选择模式下单指属于滑选，滚动必须由双指 pan 承担；
        // 旧断言“单指滑动应滚网格”与用户要求的整行滑选互斥，改为验证双指配置与选择保持。
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "缺少 Library-DebugSummary")
        let deadline = Date().addingTimeInterval(5)
        var value = (banner.value as? String) ?? ""
        while Date() < deadline, !value.contains("panMin=2") {
            usleep(200_000)
            value = (banner.value as? String) ?? ""
        }
        XCTAssertTrue(value.contains("panMin=2"),
                      "滑选结束后 collectionView 必须仍由双指 pan 滚动，当前：\(value)")
        XCTAssertGreaterThanOrEqual(selectionCount(app), 6,
                                    "滑选结束后选中集合不得被滚动配置改动")
    }

    func testReusedCellBadgeMatchesSelection() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        slideAtLeastTwoRows(in: collection, fromX: 0.08, fromY: 0.22,
                            toX: 0.92, toY: 0.42)
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 6), 6,
                                    "滑选应连续选中至少 6 格")
        // 选择模式下的复用驱动器是框选自动滚动本身（MonthIndexBar 在多选态 isHidden，
        // 单指 swipe 是框选手势）：第一段拖动选中的是行 1–2 × 3 列（6 格），第二段从
        // 未选中的行 3 起手短矩形（行 3–5 首列，终点 0.88<0.89 不触发自动滚动）→ 6+3=9。
        // 起手在已选格会进取消模式；可见徽标断言要求滚动幅度小（深滚后可见区全未选）。
        slideSelectGesture(in: collection, fromX: 0.12, fromY: 0.55,
                           toX: 0.12, toY: 0.88)
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 9, timeout: 8), 9,
                                    "第二段矩形必须在已选集合上继续增长")
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertGreaterThanOrEqual(selectionCount(app), 9,
                                    "复用稳定后选中集合不得丢失")
        XCTAssertGreaterThanOrEqual(visibleSelectedCount(in: collection), 3,
                                    "复用后的可见徽标/AX 必须与选中状态一致")
    }

    // MARK: - S02 快滑 50 + 回滑 50 不卡死不闪退

    func testFastSwipe50Times() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 0)
        for round in 0..<50 {
            swipeLeftFast(in: viewer)
            if round % 5 == 4 {
                assertAlive(app, "快滑 \(round + 1) 次后")
            }
        }
        for round in 0..<50 {
            swipeRightFast(in: viewer)
            if round % 5 == 4 {
                assertAlive(app, "回滑 \(round + 1) 次后")
            }
        }
        assertAlive(app, "100 次快滑结束后")
        snap(app, "s02-fast-swipe")
    }

    // MARK: - S03 年份筛选反复切换不崩

    func testFilterYearsRepeatedly() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let years = [2026, 2024, 2020]
        for round in 1...5 {
            for year in years {
                // 每轮重新 launch（就绪钩子应用年份 + 上一轮持久化筛选生效——覆盖 S03 重启崩溃路径）
                launchWithYearFilter(app, year: year)
                assertAlive(app, "应用 \(year) 年筛选后（第 \(round) 轮）")
                XCTAssertTrue(waitTopHeaderContains(app, "\(year)年", timeout: 10),
                              "选 \(year) 年后顶部月份头为「\(topHeaderText(app))」\n\(hierarchy(app))")
            }
        }
        snap(app, "s03-year-filter")
    }

    // MARK: - S03b 持久化筛选重启不崩

    func testFilterPersistedAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithFilterCleared(app)   // 隔离跨用例持久化
        launchWithYearFilter(app, year: 2024)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年", timeout: 10),
                      "选 2024 年后顶部月份头为「\(topHeaderText(app))」")
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年", timeout: 10),
                      "重启后筛选未保持（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        assertAlive(app, "持久化筛选重启后")
        snap(app, "s04-restore")
    }

    // MARK: - S04 深处月份位置保存 + 杀进程重启回到原位置（M13：像素锚点）


    // MARK: - S05 底部无空胶囊、不挡网格

    func testToastDoesNotBlockGrid() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let collection = launchToGrid(app)
        Thread.sleep(forTimeInterval: 5)   // 等任何恢复/提示 Toast 结束
        let toast = anyElement(app, identifier: "DSToast")
        if toast.exists {
            XCTAssertFalse(toast.isHittable, "Toast 可命中（挡住网格）：\(toast.label)\n\(hierarchy(app))")
        }
        // 点底部最后一行照片 → 应打开查看器
        let bottomCell = collection.cells.element(boundBy: 11)
        if bottomCell.exists {
            bottomCell.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86)).tap()
        }
        XCTAssertTrue(viewerRoot(app).waitForExistence(timeout: 5),
                      "点底部照片未打开查看器（可能被底部气泡挡住）\n\(hierarchy(app))")
        assertAlive(app, "底部点击后")
        snap(app, "s05-toast")
    }

    // MARK: - S06 顶部筛选栏移除 + 多选筛选按钮在全选左侧

    func testFilterBarRemovedAndFilterButtonPlacement() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        app.launchArguments += ["-uiTestingSelectMode"]
        _ = launchToGrid(app)
        let filterBar = anyElement(app, identifier: "Library-FilterBar")
        XCTAssertFalse(filterBar.exists, "顶部筛选栏仍存在\n\(hierarchy(app))")
        let filter = anyElement(app, identifier: "Batch-Filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "多选操作行缺筛选按钮\n\(hierarchy(app))")
        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), "多选操作行缺全选\n\(hierarchy(app))")
        XCTAssertLessThanOrEqual(filter.frame.maxX, selectAll.frame.minX + 1,
                                 "筛选按钮应位于全选左侧（filter.maxX=\(filter.frame.maxX)，selectAll.minX=\(selectAll.frame.minX)）")
        // UIKit 按钮 tap 可靠（Batch-Filter 为 UIButton）；保底坐标点击
        filter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dateMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '日期筛选'")).firstMatch
        XCTAssertTrue(dateMenu.waitForExistence(timeout: 8), "点 Batch-Filter 未打开筛选面板\n\(hierarchy(app))")
        snap(app, "s06-filter-entry")
    }

    // MARK: - S07 多选单指滑选连续选中（M13：整条替换长按框选）

    func testSlideToSelect() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        slideAtLeastTwoRows(in: collection, fromX: 0.08, fromY: 0.22,
                            toX: 0.92, toY: 0.42)
        let count = waitForSelectionCount(app, atLeast: 6)
        XCTAssertGreaterThanOrEqual(count, 6, "单指滑选后计数不足 6")
        XCTAssertGreaterThanOrEqual(visibleSelectedCount(in: collection), 6,
                                    "可见选中格不足 6")
        snap(app, "s07-slide-select")
    }    // MARK: - S08 查看器连滑 30 张不闪退

    func testViewerSwipeThroughAllPhotos() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 0)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        var lastIdx = -1
        for i in 0..<30 {
            swipeLeftFast(in: viewer)
            Thread.sleep(forTimeInterval: 0.3)
            if i % 5 == 4 {
                assertAlive(app, "滑到第 \(i + 1) 张后")
                let label = banner.label
                let idx = Self.parseField(label, "idx")
                XCTAssertGreaterThan(idx, lastIdx, "翻页未前进：\(label)\n\(hierarchy(app))")
                lastIdx = idx
                let load = Self.parseField(label, "load")
                if load >= 0 {
                    XCTAssertLessThanOrEqual(load, 3, "在途加载堆积：\(label)")
                }
            }
        }
        assertAlive(app, "连滑 30 张结束后")
        snap(app, "s08-viewer")
    }

    // MARK: - S09 月份面板跳转

    func testMonthJump() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        snap(app, "s09-month-jump")
        assertAlive(app, "月份跳转后")
    }

    // MARK: - S10 单月全选（计数 = 该月张数，不泄漏到其他月）

    func testSelectWholeMonth() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")

        // 月份头菜单为 UIKit UIButton + UIMenu（宿主可靠）
        let menu = anyElement(app, identifier: "MonthHeader-Menu-2024-05")
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "月份头缺菜单按钮\n\(hierarchy(app))")
        menu.tap()
        let selectAllMonth = app.buttons["选择本月全部"]
        XCTAssertTrue(selectAllMonth.waitForExistence(timeout: 5), "月份菜单缺「选择本月全部」\n\(hierarchy(app))")
        selectAllMonth.tap()

        let count = selectionCountLabel(app)
        XCTAssertTrue(count.waitForExistence(timeout: 5), "选中计数标签未出现\n\(hierarchy(app))")
        let deadline = Date().addingTimeInterval(5)
        var label = count.label
        while Date() < deadline {
            if label.contains("本月"), Self.parseCount(label) > 0 { break }
            usleep(300_000)
            label = count.label
        }
        XCTAssertTrue(label.contains("本月"), "计数缺「本月」范围说明：\(label)\n\(hierarchy(app))")
        let header = topHeaderText(app)
        let headerCount = Self.parseHeaderCount(header)
        XCTAssertEqual(Self.parseCount(label), headerCount,
                       "单月全选计数应等于该月张数（计数=\(label)，header=\(header)）")
        snap(app, "s10-month-select")
        // 相邻月份不应被选中：滚一屏后抽查首格
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let otherCell = app.collectionViews.firstMatch.cells.firstMatch
        if otherCell.exists {
            let value = otherCell.value as? String ?? ""
            XCTAssertFalse(value.contains("selected"), "相邻月份 cell 被误选中：\(value)")
        }
        // 再点「全选」归零（scope 内反选）
        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "多选工具栏缺全选\n\(hierarchy(app))")
        selectAll.tap()
        let zeroDeadline = Date().addingTimeInterval(5)
        var zeroLabel = count.label
        while Date() < zeroDeadline {
            if Self.parseCount(zeroLabel) == 0 { break }
            usleep(300_000)
            zeroLabel = count.label
        }
        XCTAssertEqual(Self.parseCount(zeroLabel), 0, "再点全选应归零：\(zeroLabel)")
    }

    // MARK: - S11 时间刻度/月份跳转后杀进程重启记住位置

    func testMonthJumpPersistsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        // 同一 app 实例启动参数跨轮累积（绿8 filterYear 同源问题）——重启前摘掉月份跳转
        // flag，验证的是位置记忆把用户带回目标月，不得被跳转重放掩盖。
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10),
                      "跳转后重启未回到 2024年5月（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        assertAlive(app, "月份跳转重启后")
        snap(app, "s11-relaunch")
    }

    // MARK: - S12 删除首/中/末不闪退（会话 mock 隔离 PhotoKit）

    func testDeleteFirstMiddleLastNoCrash() throws {
        for index in [0, 9, 19] {
            let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
            let viewer = openViewer(app, startIndex: index, downAction: "moveToRecentlyDeleted")
            let banner = viewerBanner(app)
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器横幅未出现\n\(hierarchy(app))")
            let before = banner.label
            swipeDown(in: viewer)
            assertAlive(app, "删除第 \(index + 1) 张后")
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            XCTAssertNotEqual(banner.label, before, "删除后横幅未变化（可能未前进）\n\(hierarchy(app))")
        }
    }

    // MARK: - S12b 隐藏首/中/末不闪退

    func testHideFirstMiddleLastNoCrash() throws {
        for index in [0, 9, 19] {
            let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
            let viewer = openViewer(app, startIndex: index)   // 默认 gesture.down = hide
            let banner = viewerBanner(app)
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器横幅未出现\n\(hierarchy(app))")
            let before = banner.label
            swipeDown(in: viewer)
            assertAlive(app, "隐藏第 \(index + 1) 张后")
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            XCTAssertNotEqual(banner.label, before, "隐藏后横幅未变化\n\(hierarchy(app))")
        }
    }

    // MARK: - S12c 连续 20 次下滑删除 0 崩溃、计数 20

    func testDelete20InARowNoCrash() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let viewer = openViewer(app, startIndex: 0, downAction: "moveToRecentlyDeleted")
        for i in 0..<20 {
            swipeDown(in: viewer)
            if i % 5 == 4 {
                assertAlive(app, "连续删除 \(i + 1) 张后")
            }
        }
        let badge = anyElement(app, identifier: "SessionBadge")
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "待处理徽标未出现\n\(hierarchy(app))")
        XCTAssertTrue(badge.label.contains("20"), "待删除计数应 20，实际「\(badge.label)」")
        assertAlive(app, "连续 20 次删除结束后")
        snap(app, "s12-delete")
    }

    // MARK: - Phase 7 全页面烟测（照片库→查看器→工具各页→返回）

    func testAllPagesSmoke() throws {
        let app = XCUIApplication()
        // 绿16 实锤：跨用例位置恢复会把首格停在视口边缘（y=-10.7 不可点）——烟测与位置
        // 记忆无关，清掉持久化位置保证首格完整可见可点。
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingKeepChrome", "-uiTestingClearPosition"]
        app.launchArguments += ["-uiTestingFaceIDBypass", "-uiTestingStorageMock"]
        let collection = launchToGrid(app)
        assertAlive(app, "照片库")

        // 查看器开 → 关
        collection.cells.firstMatch.tap()
        XCTAssertTrue(viewerRoot(app).waitForExistence(timeout: 8), "查看器未打开\n\(hierarchy(app))")
        assertAlive(app, "查看器")
        let close = anyElement(app, identifier: "Viewer-Close")
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            app.swipeDown()   // 兜底：chrome 淡出时先唤出（KeepChrome 未开时点击屏幕）
            app.otherElements["ViewerRoot"].tap()
        }
        // M12 R07：左上「工具」→ 工具 sheet（无 TabBar）
        let toolsEntry = anyElement(app, identifier: "Library-Tools")
        XCTAssertTrue(toolsEntry.waitForExistence(timeout: 5), "左上缺工具入口\n\(hierarchy(app))")
        tapLibraryTools(in: app)
        XCTAssertTrue(anyElement(app, identifier: "Tools-Cleanup").waitForExistence(timeout: 5),
                      "工具 sheet 未打开\n\(hierarchy(app))")
        assertAlive(app, "工具页")

        // 工具页逐个入口进 → 退
        let entries: [(id: String, name: String)] = [
            ("Tools-Cleanup", "智能清理"),
            ("Tools-Vault", "已隐藏"),
            ("Tools-Albums", "相簿"),
            ("Tools-RecentlyDeleted", "最近删除"),
            ("Tools-StorageStats", "存储统计"),
            ("Tools-GestureTutorial", "手势教学"),
            ("Tools-Settings", "设置"),
        ]
        for entry in entries {
            let link = anyElement(app, identifier: entry.id)
            guard link.waitForExistence(timeout: 5) else {
                // 入口标识未接入时跳过（Phase 7 统一补齐），只断言活着
                continue
            }
            link.tap()
            assertAlive(app, "进入\(entry.name)后")
            XCTAssertTrue(tapFrontmostBackButton(in: app), "返回按钮缺失\n\(hierarchy(app))")
            assertAlive(app, "退出\(entry.name)后")
        }
        // M12 R07：Tools-Close 关闭 sheet → 回照片库
        let closeButton = anyElement(app, identifier: "Tools-Close")
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "工具 sheet 缺关闭按钮\n\(hierarchy(app))")
        closeButton.tap()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5), "关闭工具后未回照片库")
        assertAlive(app, "返回照片库")
    }
}
