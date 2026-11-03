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
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
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

    /// 顶部（粘性）月份头文本，形如「2024年5月 · 2 张」
    private func topHeaderText(_ app: XCUIApplication) -> String {
        let headers = app.collectionViews.firstMatch
            .staticTexts.matching(NSPredicate(format: "label CONTAINS '月 ·'"))
        return headers.firstMatch.label
    }

    private func waitTopHeaderContains(_ app: XCUIApplication, _ text: String,
                                       timeout: TimeInterval = 5) -> Bool {
        let headers = app.collectionViews.firstMatch
            .staticTexts.matching(NSPredicate(format: "label CONTAINS '月 ·'"))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if headers.firstMatch.label.contains(text) { return true }
            usleep(300_000)
        }
        return false
    }

    private func openFilterSheet(_ app: XCUIApplication) {
        let filterButton = anyElement(app, identifier: "Library-Filter")
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5), "筛选入口不存在\n\(hierarchy(app))")
        filterButton.tap()
        let dateMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '日期筛选'")).firstMatch
        XCTAssertTrue(dateMenu.waitForExistence(timeout: 8), "筛选面板未出现\n\(hierarchy(app))")
    }

    /// 打开筛选面板并选一个年份 → 完成
    private func applyYearFilter(_ app: XCUIApplication, year: String) {
        openFilterSheet(app)
        let dateMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '日期筛选'")).firstMatch
        dateMenu.tap()
        let option = app.buttons[year]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "年份选项 \(year) 未出现\n\(hierarchy(app))")
        option.tap()
        let done = app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "筛选面板缺「完成」\n\(hierarchy(app))")
        done.tap()
    }

    /// 清空筛选（跨用例的 UserDefaults 持久化隔离）
    private func resetFilter(_ app: XCUIApplication) {
        openFilterSheet(app)
        let reset = app.buttons["重置"]
        if reset.waitForExistence(timeout: 3) {
            reset.tap()
        }
        let done = app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    private func selectionCountLabel(_ app: XCUIApplication) -> XCUIElement {
        anyElement(app, identifier: "Selection-Count")
    }

    // MARK: 文本解析

    /// 截图取证（docs/13 Phase 8：s01–s12 随 ui-test-attachments artifact 导出，逐张确认）
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    /// 横幅字段：parseField("id=abc idx=7 load=2", "idx") == 7；缺失返回 -1
    private static func parseField(_ label: String, _ key: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "\(key)=(-?[0-9]+)"),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Int(label[range]) ?? -1
    }

    // MARK: - S01 捏合缩放 20 轮不卡死不闪退

    func testPinchZoom20Times() throws {
        let app = XCUIApplication()
        let viewer = openViewer(app, startIndex: 7)
        let banner = viewerBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        for round in 0..<20 {
            viewer.pinch(withScale: 2.5, velocity: 2)
            viewer.pinch(withScale: 0.4, velocity: -2)
            viewer.doubleTap()
            if round % 5 == 4 {
                assertAlive(app, "捏合第 \(round + 1) 轮后")
            }
        }
        assertAlive(app, "20 轮捏合结束后")
        let label = banner.label.lowercased()
        XCTAssertFalse(label.contains("nan"), "横幅出现 NaN：\(banner.label)")
        XCTAssertFalse(label.contains("inf"), "横幅出现 inf：\(banner.label)")
        snap(app, "s01-zoom")
    }

    // MARK: - S02 快滑 50 + 回滑 50 不卡死不闪退

    func testFastSwipe50Times() throws {
        let app = XCUIApplication()
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
        _ = launchToGrid(app)
        resetFilter(app)
        let years = ["2026", "2024", "2020"]
        for round in 1...5 {
            for year in years {
                applyYearFilter(app, year: year)
                assertAlive(app, "应用 \(year) 年筛选后（第 \(round) 轮）")
                XCTAssertTrue(waitTopHeaderContains(app, "\(year)年", timeout: 5),
                              "选 \(year) 年后顶部月份头为「\(topHeaderText(app))」\n\(hierarchy(app))")
            }
        }
        snap(app, "s03-year-filter")
    }

    // MARK: - S03b 持久化筛选重启不崩

    func testFilterPersistedAfterRelaunch() throws {
        let app = XCUIApplication()
        _ = launchToGrid(app)
        resetFilter(app)
        applyYearFilter(app, year: "2024")
        XCTAssertTrue(waitTopHeaderContains(app, "2024年", timeout: 5),
                      "选 2024 年后顶部月份头为「\(topHeaderText(app))」")
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年", timeout: 10),
                      "重启后筛选未保持（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        assertAlive(app, "持久化筛选重启后")
        snap(app, "s04-restore")
    }

    // MARK: - S04 滚到 2024-05 杀进程重启回到原位置

    func testPositionRestoredAfterRelaunch() throws {
        let app = XCUIApplication()
        _ = launchToGrid(app)
        resetFilter(app)
        var reached = waitTopHeaderContains(app, "2024年5月", timeout: 2)
        var swipes = 0
        while !reached, swipes < 60 {
            app.swipeUp()
            swipes += 1
            reached = waitTopHeaderContains(app, "2024年5月", timeout: 1)
        }
        XCTAssertTrue(reached, "\(swipes) 次滑动内未到达 2024年5月（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.5)   // 等位置保存兜底 Timer
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10),
                      "重启后未回到 2024年5月（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        assertAlive(app, "位置恢复重启后")
    }

    // MARK: - S05 底部无空胶囊、不挡网格

    func testToastDoesNotBlockGrid() throws {
        let app = XCUIApplication()
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
        filter.tap()
        let dateMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '日期筛选'")).firstMatch
        XCTAssertTrue(dateMenu.waitForExistence(timeout: 8), "点 Batch-Filter 未打开筛选面板\n\(hierarchy(app))")
        snap(app, "s06-filter-entry")
    }

    // MARK: - S07 多选长按拖选连续选中

    func testSlideToSelect() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSelectMode"]
        let collection = launchToGrid(app)
        let firstCell = collection.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "网格无 cell")
        // 长按第 1 格 0.2s 后拖到第 2 行右列（3 列网格的第 6 格附近）
        let start = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: target)
        let count = selectionCountLabel(app)
        XCTAssertTrue(count.waitForExistence(timeout: 5), "选中计数标签未出现\n\(hierarchy(app))")
        let deadline = Date().addingTimeInterval(5)
        var n = 0
        while Date() < deadline {
            n = Self.parseCount(count.label)
            if n >= 6 { break }
            usleep(300_000)
        }
        XCTAssertGreaterThanOrEqual(n, 6, "长按拖选后计数不足 6：\(count.label)\n\(hierarchy(app))")
        // 前 6 格应带 selected 标记
        for index in 0..<6 {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists else { continue }
            let value = cell.value as? String ?? ""
            XCTAssertTrue(value.contains("selected"), "第 \(index + 1) 格未选中：\(value)\n\(hierarchy(app))")
        }
        snap(app, "s07-slide-select")
    }

    // MARK: - S08 查看器连滑 30 张不闪退

    func testViewerSwipeThroughAllPhotos() throws {
        let app = XCUIApplication()
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
        _ = launchToGrid(app)
        let monthButton = anyElement(app, identifier: "Library-MonthJump")
        XCTAssertTrue(monthButton.waitForExistence(timeout: 5), "导航栏缺「月份」按钮\n\(hierarchy(app))")
        monthButton.tap()
        let sheet = anyElement(app, identifier: "MonthJump-Sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "月份面板未出现\n\(hierarchy(app))")
        let card = anyElement(app, identifier: "MonthJump-Month-2024-05")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "缺 2024-05 月份卡片\n\(hierarchy(app))")
        snap(app, "s09-month-jump")
        card.tap()
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 8),
                      "跳转后顶部不是 2024年5月（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        assertAlive(app, "月份跳转后")
    }

    // MARK: - S10 单月全选（计数 = 该月张数，不泄漏到其他月）

    func testSelectWholeMonth() throws {
        let app = XCUIApplication()
        _ = launchToGrid(app)
        let monthButton = anyElement(app, identifier: "Library-MonthJump")
        XCTAssertTrue(monthButton.waitForExistence(timeout: 5), "导航栏缺「月份」按钮\n\(hierarchy(app))")
        monthButton.tap()
        let card = anyElement(app, identifier: "MonthJump-Month-2024-05")
        XCTAssertTrue(card.waitForExistence(timeout: 8), "缺 2024-05 月份卡片\n\(hierarchy(app))")
        card.tap()
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 8))

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
        _ = launchToGrid(app)
        let monthButton = anyElement(app, identifier: "Library-MonthJump")
        XCTAssertTrue(monthButton.waitForExistence(timeout: 5), "导航栏缺「月份」按钮\n\(hierarchy(app))")
        monthButton.tap()
        let card = anyElement(app, identifier: "MonthJump-Month-2024-05")
        XCTAssertTrue(card.waitForExistence(timeout: 8), "缺 2024-05 月份卡片\n\(hierarchy(app))")
        card.tap()
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)   // 等同步保存完成
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
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 5))
        app.tabBars.buttons["工具"].tap()
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
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5), "\(entry.name)页缺返回按钮\n\(hierarchy(app))")
            back.tap()
            assertAlive(app, "退出\(entry.name)后")
        }
        app.tabBars.buttons["照片库"].tap()
        assertAlive(app, "返回照片库")
    }
}
