// MARK: - MarqueeSelectionUITests：多选交互验收（M17 T05 重写，docs/32 §4.3，docs/31 §2.1/§2.3）——
// 新交互模型：长按 0.4s 进入多选并选中锚点；长按后任意方向拖 = 框选（含纵向到第 5 行 / 底缘
// 自动滚动）；无长按的横向按压拖 = 框选（pressing 横向占优，表第 3 行）；纵向单指拖 = 滚动让位
//（G2，多选模式下亦然）；锚点已选 → 取消模式。断言一律锚定真实 cell（3 列网格，cell 索引行优先）
// 并按 assetID（PhotoGridCell accessibilityValue = "<id> selected/none"）精确比对。

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

    /// 普通网格（不带 -uiTestingSelectMode：长按进入路径用，清位置 + 年份筛选清空）
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

    /// 长按 cell 后拖到另一 cell 中心（0.4s > 0.28s 长按阈值：armed 在按下期间成立，
    /// 起点终点都锚定真实 cell，几何不受像素估算影响）
    private func longPressDrag(in collection: XCUIElement, fromIndex: Int, toIndex: Int,
                               hold: TimeInterval? = nil) {
        let start = collection.cells.element(boundBy: fromIndex)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = collection.cells.element(boundBy: toIndex)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if let hold {
            start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: hold)
        } else {
            start.press(forDuration: 0.4, thenDragTo: end)
        }
    }

    /// PhotoGridCell accessibilityValue = "<assetID> selected/none" → assetID
    private func cellID(_ cell: XCUIElement) -> String {
        let raw = (cell.value as? String) ?? ""
        if raw.hasSuffix(" selected") { return String(raw.dropLast(" selected".count)) }
        if raw.hasSuffix(" none") { return String(raw.dropLast(" none".count)) }
        return raw
    }

    private func cellIsSelected(_ cell: XCUIElement) -> Bool {
        ((cell.value as? String) ?? "").hasSuffix(" selected")
    }

    private func selectedVisibleIDs(_ collection: XCUIElement) -> Set<String> {
        var ids = Set<String>()
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            if cellIsSelected(cell) { ids.insert(cellID(cell)) }
        }
        return ids
    }

    /// 等待选中集合稳定（触觉/帧重算异步收敛）
    @discardableResult
    private func waitForSelectedSet(_ collection: XCUIElement, equals expected: Set<String>,
                                    timeout: TimeInterval = 4) -> Set<String> {
        let deadline = Date().addingTimeInterval(timeout)
        var current = selectedVisibleIDs(collection)
        while Date() < deadline, current != expected {
            usleep(200_000)
            current = selectedVisibleIDs(collection)
        }
        return current
    }

    // MARK: - 长按进入（docs/31 §2.1 G13；T01 红锚点转绿）

    /// 不点工具栏、不走 -uiTestingSelectMode，长按首格 0.4s：必须进入多选、该格入选、
    /// 多选栏（Selection-Count）出现。验收：长按进入后未点工具栏也出现多选栏。
    func testLongPressEntersSelection() throws {
        let app = XCUIApplication()
        let collection = launchPlainGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.press(forDuration: 0.4)
        let count = waitForSelectionCountEqual(app, to: 1, timeout: 5)
        XCTAssertEqual(count, 1,
                       "长按首格必须进入多选且该格入选（docs/31 G13：长按路径）count=\(count)")
        XCTAssertTrue(anyElement(app, identifier: "Selection-Count").exists,
                      "长按进入后必须出现多选栏（Selection-Count 存在）")
        XCTAssertTrue(cellIsSelected(first), "锚点 cell 必须同步 selected 徽标")
        snap(app, "m17-longpress-enter")
    }

    // MARK: - 长按后拖动继续框选（docs/32 §4.3）

    /// 长按首格 0.4s → 拖到第 5 行（col-0 行 4）：命中集合精确 = col-0 行 0-4 的 assetID 列表，
    /// 同行右列不得被卷入（armed 任意方向拖框，docs/32 §2.2 表第 6 行）。
    func testLongPressDragContinuesSelection() throws {
        let app = XCUIApplication()
        let collection = launchPlainGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        let expected = Set([0, 3, 6, 9, 12].map { cellID(collection.cells.element(boundBy: $0)) })
        longPressDrag(in: collection, fromIndex: 0, toIndex: 12)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 5, timeout: 6), 5,
                       "长按后拖到第 5 行：col-0 行 0-4 共 5 格（计数不变性见单指滚动用例）")
        let selected = waitForSelectedSet(collection, equals: expected)
        XCTAssertEqual(selected, expected,
                       "命中集合必须精确等于 col-0 行 0-4 的 assetID 列表（got=\(selected.sorted())）")
        for mate in [1, 2, 4, 5] {
            XCTAssertFalse(cellIsSelected(collection.cells.element(boundBy: mate)),
                           "col-0 拖动不得卷入同行右列（idx \(mate)）")
        }
        snap(app, "m17-longpress-drag")
    }

    // MARK: - 单指滚动保留（docs/31 §2.1 G1；T01 红锚点转绿）

    /// -uiTestingSelectMode 进多选后单指上滑：contentOffset.y 增量 > 200 且计数不变
    ///（纵向让位，不得被框选/双指规则劫持）。
    func testSingleFingerScrollWorksInSelectionMode() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        guard let startY = waitForOffsetY(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off=\n\(hierarchy(app))")
        }
        let countBefore = selectionCount(app)
        // 终点 dy 0.25（≈211pt 距顶）避开 60pt 边缘自动滚动区（SlideSelectConfig.edgeBuffer）
        collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let endY = waitForOffsetIncrease(app, from: startY, atLeast: 200, timeout: 5)
        XCTContext.runActivity(named: "单指滚动取证") { activity in
            let attachment = XCTAttachment(string:
                "startOff=\(startY) endOff=\(endY) delta=\(endY - startY) count=\(selectionCount(app))")
            attachment.name = "m17-single-finger-scroll"
            activity.add(attachment)
        }
        XCTAssertGreaterThan(endY - startY, 200,
                             "多选模式单指上滑必须滚动（docs/31 G1）start=\(startY) end=\(endY)")
        XCTAssertEqual(selectionCount(app), countBefore,
                       "单指滚动是滚动不是框选：计数必须不变（before=\(countBefore)）")
        snap(app, "m17-selectmode-single-finger-scroll")
    }

    // MARK: - 边缘自动滚动选入屏外（docs/32 §4.3）

    /// 长按首格 → 拖到底缘停留 2s：自动滚动逐帧入集，选中集必须包含拖前不可见的 assetID。
    func testAutoScrollSelectsOffscreenExactly() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let preDragIDs = Set((0..<collection.cells.count).map { cellID(collection.cells.element(boundBy: $0)) })
        XCTAssertGreaterThan(preDragIDs.count, 5, "首屏必须有足够可见 cell")
        longPressDrag(in: collection, fromIndex: 0, toIndex: 0, hold: 2.0)
        let count = waitForSelectionCount(app, atLeast: 6, timeout: 10)
        XCTAssertGreaterThanOrEqual(count, 6,
                                    "底缘拖 2s 必须自动滚动并选入屏外 cell（count=\(count)）")
        let selected = selectedVisibleIDs(collection)
        let offscreen = selected.subtracting(preDragIDs)
        XCTAssertFalse(offscreen.isEmpty,
                       "屏外 assetID 必须精确入集（selected=\(selected.count) offscreen=\(offscreen.count)）")
        assertAlive(app, "自动滚动后")
        snap(app, "m17-autoscroll-exact")
    }

    // MARK: - 无长按横向按压拖（docs/32 §2.2 表第 3 行：必要时先进入多选）

    /// 普通网格横向按压拖过行 1：横向占优 ≥8pt → 先进多选再框选整行（3 格精确）。
    func testHorizontalDragFromPressSelectsRow() throws {
        let app = XCUIApplication()
        let collection = launchPlainGrid(app)
        let expected = Set([3, 4, 5].map { cellID(collection.cells.element(boundBy: $0)) })
        let start = collection.cells.element(boundBy: 3)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = collection.cells.element(boundBy: 5)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 3, timeout: 6), 3,
                       "横向按压拖必须框选行 1 的 3 格（未在多选时先进入多选）")
        let selected = waitForSelectedSet(collection, equals: expected)
        XCTAssertEqual(selected, expected,
                       "命中必须精确等于行 1 的 assetID（got=\(selected.sorted())）")
        snap(app, "m17-horizontal-press-drag")
    }

    // MARK: - 取消模式（锚点已选 → deselect，docs/25 §6.5）

    /// 点选 col-0 行 0-2 → 从锚点长按下拖覆盖同行三格 → 全部取消（计数归 0）。
    func testDragFromSelectedCellDeselects() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        for index in [0, 3, 6] {
            collection.cells.element(boundBy: index).tap()
        }
        XCTAssertEqual(waitForSelectionCount(app, atLeast: 3), 3, "预点选 col-0 行 0-2")
        longPressDrag(in: collection, fromIndex: 0, toIndex: 6)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 0, timeout: 6), 0,
                       "锚点已选 → 取消模式：矩形命中的 3 格全部取消（armed 帧 0 尺寸选框先取消锚点）")
        let selected = waitForSelectedSet(collection, equals: Set<String>())
        XCTAssertTrue(selected.isEmpty, "选中集必须精确清空（got=\(selected.sorted())）")
        snap(app, "m17-longpress-deselect")
    }

    /// 回拖收缩：第二次手势从已选锚点起拖（取消模式）→ 5 → 3（不得保留累积）。
    func testSecondGestureFromAnchorShrinks() throws {
        let app = XCUIApplication()
        let collection = launchPlainGrid(app)
        longPressDrag(in: collection, fromIndex: 0, toIndex: 12)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 5, timeout: 6), 5, "第一次手势选 col-0 行 0-4")
        longPressDrag(in: collection, fromIndex: 0, toIndex: 3)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 3, timeout: 6), 3,
                       "第二次手势 = 取消模式：col-0 行 0-1 取消后剩 3 格")
        snap(app, "m17-second-gesture-shrink")
    }

    // MARK: - 斜向矩形（armed 任意方向）

    /// 长按首格 → 斜向拖到 cell10（行 3 列 1）：精确覆盖 col-0/1 × 行 0-3 = 8 格。
    func testDiagonalMarqueeSelectsRectangle() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let expected = Set([0, 1, 3, 4, 6, 7, 9, 10].map { cellID(collection.cells.element(boundBy: $0)) })
        longPressDrag(in: collection, fromIndex: 0, toIndex: 10)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 8, timeout: 6), 8,
                       "斜向矩形必须覆盖 col-0/1 × 行 0-3 = 8 格")
        let selected = waitForSelectedSet(collection, equals: expected)
        XCTAssertEqual(selected, expected,
                       "命中必须精确等于 8 格 assetID（got=\(selected.sorted())）")
        snap(app, "m17-diagonal")
    }

    // MARK: - 轻点不被吞（docs/25 §6.5 ⑥）

    func testTapNotSwallowed() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.tap()
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 1), 1,
                                    "cancelsTouchesInView=false 时轻点不得被手势吞掉")
        XCTAssertTrue(cellIsSelected(first), "轻点后徽标与 AX 必须同步为 selected")
    }

    // MARK: - 全选后框选取消（docs/25 §6.5 ⑦）

    func testSelectAllThenMarqueeDeselects() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "多选操作行缺全选\n\(hierarchy(app))")
        selectAll.tap()
        let total = waitForSelectionCountEqual(app, to: selectionCount(app), timeout: 0.1)
        XCTAssertGreaterThan(total, 10, "全选后计数应 > 10")
        // 锚点已选 → 取消模式：长按下拖取消 col-0 行 0-2 三格 → total − 3
        longPressDrag(in: collection, fromIndex: 0, toIndex: 6)
        XCTAssertEqual(waitForSelectionCountEqual(app, to: total - 3, timeout: 6), total - 3,
                       "全选后长按框选必须恰好取消 col-0 行 0-2 三格（total=\(total)）")
        assertAlive(app, "全选+框选取消后")
        snap(app, "m17-selectall-deselect")
    }

    // MARK: - 取证通道（Library-DebugSummary → off=）

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

    private func waitForOffsetY(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Double? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = readOffsetY(app) { return value }
            usleep(100_000)
        }
        return readOffsetY(app)
    }

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
}
