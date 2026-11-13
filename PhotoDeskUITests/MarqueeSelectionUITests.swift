// MARK: - MarqueeSelectionUITests：矩形框选验收（docs/25 §6.5 / M15 P0-3/4，≥8 条）——
// 核心语义：① 左/右列竖直下拉只选本列（旧「整行带」断言废止：4 行 ≥12 格视为失败）；
// ② 从已选 cell 起拖 → 取消模式；③ 回拖收缩（无 insert-only 累积）；④ 斜向矩形；
// ⑤ 边缘自动滚动逐帧入集；⑥ 轻点不被 pan 吞掉；⑦ 全选后框选取消。

import XCTest

final class MarqueeSelectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - helper

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

    /// 多选模式网格（清位置 + 直入多选，首屏几何确定）
    private func launchSelectableGrid(_ app: XCUIApplication) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingClearPosition",
                                "-uiTestingSelectMode", "-uiTestingKeepChrome",
                                "-uiTestingFilterYear", "0"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现\n\(hierarchy(app))")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
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

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func parseCount(_ label: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]+"),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range, in: label) else { return 0 }
        return Int(label[range]) ?? 0
    }

    private func selectionCount(_ app: XCUIApplication) -> Int {
        let label = anyElement(app, identifier: "Selection-Count")
        guard label.exists else { return -1 }
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

    /// 单指拖动（选择模式下 pan 独占；可选 hold 模拟边缘停留）
    private func marqueeDrag(in collection: XCUIElement,
                             fromX: CGFloat, fromY: CGFloat,
                             toX: CGFloat, toY: CGFloat,
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

    private func cellIsSelected(_ cell: XCUIElement) -> Bool {
        (cell.value as? String ?? "").contains("selected")
    }

    // MARK: - 左列 / 右列竖直下拉

    /// 3 列左列竖直下拉：只选左列；右侧两列同屏首行不得被选中；计数必须远小于整行语义（≥12）
    func testVerticalDragOnLeftColumnSelectsOnlyLeftColumn() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        marqueeDrag(in: collection, fromX: 0.12, fromY: 0.22, toX: 0.12, toY: 0.80)
        let count = waitForSelectionCount(app, atLeast: 3, timeout: 6)
        XCTAssertGreaterThanOrEqual(count, 3, "左列下拉至少命中 3 格")
        XCTAssertLessThanOrEqual(count, 8,
                                 "左列下拉命中 \(count) 格——若 ≥12 说明整行带语义复活（P0-3 回归）")
        let firstRow = collection.cells
        XCTAssertFalse(cellIsSelected(firstRow.element(boundBy: 1)),
                       "同行第 2 列不得被左列下拉选中：\(firstRow.element(boundBy: 1).value ?? "nil")")
        XCTAssertFalse(cellIsSelected(firstRow.element(boundBy: 2)),
                       "同行第 3 列不得被左列下拉选中：\(firstRow.element(boundBy: 2).value ?? "nil")")
        snap(app, "m15-marquee-left-column")
    }

    func testVerticalDragOnRightColumnSelectsOnlyRightColumn() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        marqueeDrag(in: collection, fromX: 0.86, fromY: 0.22, toX: 0.86, toY: 0.80)
        let count = waitForSelectionCount(app, atLeast: 3, timeout: 6)
        XCTAssertGreaterThanOrEqual(count, 3)
        XCTAssertLessThanOrEqual(count, 8, "右列下拉不得触发整行语义")
        let firstRow = collection.cells
        XCTAssertFalse(cellIsSelected(firstRow.element(boundBy: 0)),
                       "同行第 1 列不得被右列下拉选中")
        XCTAssertFalse(cellIsSelected(firstRow.element(boundBy: 1)),
                       "同行第 2 列不得被右列下拉选中")
    }

    // MARK: - 取消模式（起手已选 → deselect）

    /// 先选满首列 6 格（行 0–5），从已选首格下拉覆盖行 0–2 → 恰好取消 3 格（docs/26 §7.6）
    func testDragFromSelectedCellDeselects() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        // 轻点首列 6 格（idx 0,3,6,9,12,15 = 行 0–5 的第 0 列）
        for index in [0, 3, 6, 9, 12, 15] {
            collection.cells.element(boundBy: index).tap()
        }
        let selected = waitForSelectionCount(app, atLeast: 6)
        XCTAssertEqual(selected, 6, "预点选首列 6 格")
        // 从已选的首列首格下拉覆盖行 0–2（矩形命中首列 3 格，全部已选 → 取消 3）
        marqueeDrag(in: collection, fromX: 0.12, fromY: 0.13, toX: 0.12, toY: 0.50)
        // 激活帧会先命中锚点 1 格（中间态），拖动结束后必须等目标集合稳定再断言
        Thread.sleep(forTimeInterval: 1.0)
        let deadline = Date().addingTimeInterval(6)
        var after = selectionCount(app)
        while Date() < deadline {
            usleep(300_000)
            let next = selectionCount(app)
            if next == after { break }
            after = next
        }
        XCTAssertEqual(after, selected - 3,
                       "从已选格起拖必须进入取消模式且只取消矩形命中（before=\(selected) after=\(after)）")
        snap(app, "m15-marquee-deselect")
    }

    // MARK: - 回拖收缩

    /// 同一起点两次手势：第二次从已选锚点起拖 → 目标集合收缩，不得保留 insert-only 累积
    func testDragBackShrinksWithinSameGesture() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        // 第一次：左列下拉 0.25 → 0.75
        marqueeDrag(in: collection, fromX: 0.12, fromY: 0.25, toX: 0.12, toY: 0.75)
        let peak = waitForSelectionCount(app, atLeast: 3, timeout: 6)
        XCTAssertGreaterThanOrEqual(peak, 3)
        // 第二次：同一列更短的矩形（0.25 → 0.45）——锚点已选 → deselect → 集合收缩
        marqueeDrag(in: collection, fromX: 0.12, fromY: 0.25, toX: 0.12, toY: 0.45)
        Thread.sleep(forTimeInterval: 1.0)
        let deadline = Date().addingTimeInterval(6)
        var shrunk = selectionCount(app)
        while Date() < deadline {
            usleep(300_000)
            let next = selectionCount(app)
            if next == shrunk { break }
            shrunk = next
        }
        XCTAssertLessThan(shrunk, peak,
                          "回拖必须收缩（peak=\(peak) after=\(shrunk)），不得保留 insert-only 累积")
        snap(app, "m15-marquee-shrink")
    }

    // MARK: - 斜向矩形

    func testDiagonalMarqueeSelectsRectangle() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        marqueeDrag(in: collection, fromX: 0.08, fromY: 0.22, toX: 0.92, toY: 0.60)
        let count = waitForSelectionCount(app, atLeast: 5, timeout: 6)
        XCTAssertGreaterThanOrEqual(count, 5, "斜向矩形应覆盖 ≥2 行 × 3 列")
        XCTAssertLessThanOrEqual(count, 12, "斜向矩形不应失控放大")
        snap(app, "m15-marquee-diagonal")
    }

    // MARK: - 边缘自动滚动

    /// 左列长按拖到底缘 → 自动滚动逐帧重算，屏幕外 cell 持续入集
    func testAutoScrollMarquee() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        marqueeDrag(in: collection, fromX: 0.12, fromY: 0.40, toX: 0.12, toY: 0.995, hold: 2.0)
        let count = waitForSelectionCount(app, atLeast: 6, timeout: 8)
        // 屏内跨度上限实测 = 5（count=5 纯屏内，见上方竖直用例）；count > 5 即证明
        // 边缘自动滚动把屏幕外 cell 持续选入（Stability 的 testEdgeAutoScrollSelectsOffscreenCells
        // 同参数断言 ≥8，两处共同覆盖该机制）。
        XCTAssertGreaterThanOrEqual(count, 6,
                                    "边缘自动滚动必须让屏幕外 cell 入集（屏内上限 5，count=\(count)）")
        assertAlive(app, "边缘自动滚动后")
        snap(app, "m15-marquee-autoscroll")
    }

    // MARK: - 轻点不被吞

    func testTapNotSwallowed() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.tap()
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 1), 1,
                                    "cancelsTouchesInView=false 时轻点不得被框选 pan 吞掉")
        XCTAssertTrue(cellIsSelected(first), "轻点后徽标与 AX 必须同步为 selected")
    }

    // MARK: - 全选后框选取消

    func testSelectAllThenMarqueeDeselects() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "多选操作行缺全选\n\(hierarchy(app))")
        selectAll.tap()
        let total = waitForSelectionCountEqual(app, to: selectionCount(app), timeout: 0.1)
        XCTAssertGreaterThan(total, 10, "全选后计数应 > 10")
        // 从已选首列下拉 → 取消模式，计数必须下降
        marqueeDrag(in: collection, fromX: 0.12, fromY: 0.25, toX: 0.12, toY: 0.60)
        let deadline = Date().addingTimeInterval(6)
        var after = selectionCount(app)
        while Date() < deadline, after >= total {
            usleep(150_000)
            after = selectionCount(app)
        }
        XCTAssertLessThan(after, total, "全选后框选必须取消命中格")
        assertAlive(app, "全选+框选取消后")
        snap(app, "m15-marquee-selectall-deselect")
    }

    // MARK: - 跨月（section 头跨越）

    /// 矩形跨越月份头：按各 section 真实几何求交，计数持续增长且不崩
    func testCrossSectionMarqueeStaysAlive() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        // 长距斜向拖动跨越多个月份 section（每 section 仅 2 张，头高 48）
        marqueeDrag(in: collection, fromX: 0.08, fromY: 0.15, toX: 0.92, toY: 0.95, hold: 0.5)
        let count = waitForSelectionCount(app, atLeast: 8, timeout: 8)
        XCTAssertGreaterThanOrEqual(count, 8, "跨 section 矩形应持续命中")
        assertAlive(app, "跨 section 框选后")
        snap(app, "m15-marquee-cross-section")
    }

    // MARK: - M17 T01 红测试（docs/31 §2.3 G13/G16、§2.1 G1；验收锚点，先红后绿）

    /// 不带 -uiTestingSelectMode 的普通网格（清位置 + 年份筛选清空，首屏几何确定）
    private func launchPlainGrid(_ app: XCUIApplication) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingClearPosition",
                                "-uiTestingKeepChrome", "-uiTestingFilterYear", "0"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现\n\(hierarchy(app))")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
        return collection
    }

    /// Library-DebugSummary → off=（contentOffset.y 整数 pt；DEBUG 横幅，didScroll 逐次刷新）
    private static func parseDoubleField(_ label: String, _ key: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = escaped + "=(-?[0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return Double(label[range])
    }

    private func readOffsetY(_ app: XCUIApplication) -> Double? {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.exists else { return nil }
        let raw = ((banner.value as? String) ?? banner.label)
        return Self.parseDoubleField(raw, "off")
    }

    /// 轮询直到取证横幅出现并给出 off（DEBUG 横幅常驻，正常秒回）
    private func waitForOffsetY(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Double? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = readOffsetY(app) { return value }
            usleep(100_000)
        }
        return readOffsetY(app)
    }

    /// 轮询 off 增量达标（滚动是连续事件，松手后还有减速余量）
    private func waitForOffsetIncrease(_ app: XCUIApplication, from baseline: Double,
                                       atLeast threshold: Double, timeout: TimeInterval = 5) -> Double {
        let deadline = Date().addingTimeInterval(timeout)
        var value = readOffsetY(app) ?? baseline
        while Date() < deadline {
            value = readOffsetY(app) ?? baseline
            if value - baseline >= threshold { return value }
            usleep(100_000)
        }
        return value
    }

    /// 红锚点（docs/31 G13/G16）：不点工具栏、不走 -uiTestingSelectMode，直接长按首格
    /// 必须进入多选且该格入选（Selection-Count == 1）。当前全仓无长按识别器
    /// （audit-m17 A04/A14 FAIL）→ 必失败；长按进入接线后转绿。
    func testLongPressEntersSelection() throws {
        let app = XCUIApplication()
        let collection = launchPlainGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.press(forDuration: 0.4)
        let count = waitForSelectionCountEqual(app, to: 1, timeout: 5)
        XCTAssertEqual(count, 1,
                       "长按首格必须进入多选且该格入选（docs/31 G13：无长按路径，count=\(count)）")
        snap(app, "m17-longpress-enter")
    }

    /// 红锚点（docs/31 G1）：-uiTestingSelectMode 进多选后单指上滑必须正常滚动
    /// （contentOffset.y 增量 > 200pt）。当前多选把 pan 改成双指专属
    /// （LibraryViewController.swift:802/:832，audit-m17 A05 FAIL）→ 单指滑动被框选
    /// 接管、offset 不变 → 必失败；单指滚动规则接线后转绿。
    func testSingleFingerScrollInSelectionMode() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        guard let startY = waitForOffsetY(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off=\n\(hierarchy(app))")
        }
        // 终点 dy 0.25（≈211pt 距顶）避开 60pt 边缘自动滚动区（SlideSelectConfig.edgeBuffer）
        collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let endY = waitForOffsetIncrease(app, from: startY, atLeast: 200, timeout: 5)
        XCTContext.runActivity(named: "单指滚动取证") { activity in
            let attachment = XCTAttachment(string:
                "startOff=\(startY) endOff=\(endY) delta=\(endY - startY)")
            attachment.name = "m17-single-finger-scroll"
            activity.add(attachment)
        }
        XCTAssertGreaterThan(endY - startY, 200,
                             "多选模式单指上滑必须滚动（docs/31 G1：双指规则劫持单指）start=\(startY) end=\(endY)")
        snap(app, "m17-selectmode-single-finger-scroll")
    }
}
