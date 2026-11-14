// MARK: - MarqueeSelectionUITests：多选交互验收（M17 T05 重写，docs/32 §4.3，docs/31 §2.1/§2.3）——
// 新交互模型：长按 0.4s 进入多选并选中锚点；长按后任意方向拖 = 框选（含纵向到第 5 行 / 底缘
// 自动滚动）；无长按的横向按压拖 = 框选（pressing 横向占优，表第 3 行）；纵向单指拖 = 滚动让位
//（G2，多选模式下亦然）；锚点已选 → 取消模式。断言一律锚定真实 cell（3 列网格，cell 索引行优先）
// 并按 assetID（PhotoGridCell accessibilityValue = "<id> selected/none"）精确比对。

import XCTest
import UIKit

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
                                "-uiTestingFilterYear", "0", "-uiTestingLongPressMovement"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现\n\(hierarchy(app))")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
        usleep(1_500_000)  // 启动布局/inset 稳定：静止按压期间内容位移 >8pt 会使长按失效
        return collection
    }

    /// 普通网格（不带 -uiTestingSelectMode：长按进入路径用，清位置 + 年份筛选清空）
    private func launchPlainGrid(_ app: XCUIApplication) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingClearPosition",
                                "-uiTestingKeepChrome", "-uiTestingFilterYear", "0",
                                "-uiTestingLongPressMovement"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现\n\(hierarchy(app))")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
        usleep(1_500_000)  // 启动布局/inset 稳定，同 launchPlainGrid
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

    /// 长按 cell 后拖到另一 cell 中心（0.55s > 0.28s 长按阈值并留抖动余量：armed 在按下期间成立，
    /// 起点终点都锚定真实 cell，几何不受像素估算影响）
    private func longPressDrag(in collection: XCUIElement, fromIndex: Int, toIndex: Int,
                               hold: TimeInterval? = nil) {
        let start = collection.cells.element(boundBy: fromIndex)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = collection.cells.element(boundBy: toIndex)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if let hold {
            start.press(forDuration: 0.55, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: hold)
        } else {
            start.press(forDuration: 0.55, thenDragTo: end)
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

    /// 长按首格 → 拖到第 5 行（col-0 行 4）：命中集合精确 = col-0 行 0-4 的 assetID 列表，
    /// 同行右列不得被卷入（armed 任意方向拖框，docs/32 §2.2 表第 6 行）。
    /// XCUI 合成长按时序存在环境抖动（43555732806 单例失败：长按未触发→纵向滚动→无多选栏），
    /// 故整体最多重试 1 次（重新 launch 复位），断言本身保持精确、不放宽。
    func testLongPressDragContinuesSelection() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchPlainGrid(app)
            let first = collection.cells.firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
            let expected = Set([0, 3, 6, 9, 12].map { cellID(collection.cells.element(boundBy: $0)) })
            longPressDrag(in: collection, fromIndex: 0, toIndex: 12)
            let count = waitForSelectionCountEqual(app, to: 5, timeout: 6)
            guard count == 5 else {
                if attempt == 2 {
                    XCTFail("长按后拖到第 5 行：两次尝试均未进入框选（count=\(count)，长按未触发）")
                }
                continue
            }
            XCTAssertEqual(count, 5,
                           "长按后拖到第 5 行：col-0 行 0-4 共 5 格（计数不变性见单指滚动用例）")
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "命中集合必须精确等于 col-0 行 0-4 的 assetID 列表（got=\(selected.sorted())）")
            for mate in [1, 2, 4, 5] {
                XCTAssertFalse(cellIsSelected(collection.cells.element(boundBy: mate)),
                               "col-0 拖动不得卷入同行右列（idx \(mate)）")
            }
            snap(app, "m17-longpress-drag")
            return
        }
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
        // 触觉节流验收（docs/32 §2.7 ≤16 次/秒）：整手势窗口 delta ≤ 64（宽裕上界）
        let hapBefore = readHapticCount(app)
        // 长按首格 → 拖到底缘（dy 0.99，距底 25pt < 60pt 边缘区）停留 2s：自动滚动逐帧入集。
        // 合成触控偶发整手势未达 App（arm 不发生）——有界重试 2 次（同 LongPressDrag 用例）。
        let start = collection.cells.element(boundBy: 0)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let bottomEdge = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.99))
        var count = 0
        for attempt in 1...2 {
            start.press(forDuration: 0.4, thenDragTo: bottomEdge, withVelocity: .slow, thenHoldForDuration: 2.0)
            count = waitForSelectionCount(app, atLeast: 6, timeout: 10)
            if count >= 6 { break }
            if attempt == 1 { usleep(500_000) }
        }
        let hapAfter = readHapticCount(app)
        XCTAssertLessThanOrEqual(hapAfter - hapBefore, 64,
                                 "触觉必须 60ms 节流（≤16 次/秒，delta=\(hapAfter - hapBefore)）")
        let banner = (app.descendants(matching: .any)["Library-DebugSummary"].firstMatch.value as? String) ?? ""
        XCTAssertGreaterThanOrEqual(count, 6,
                                    "底缘拖 2s 必须自动滚动并选入屏外 cell（count=\(count) banner=\(banner)）")
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

    private func readHapticCount(_ app: XCUIApplication) -> Int {
        let banner = app.descendants(matching: .any)["Library-DebugSummary"].firstMatch
        guard banner.exists else { return 0 }
        let raw = ((banner.value as? String) ?? banner.label)
        return Int(Self.parseDoubleField(raw, "hap") ?? 0)
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

    // MARK: - 框选覆盖层取证（M17 T06，docs/32 §2.5）

    /// 手势阻塞主线程期间的后台连拍（XCUIScreen 采集）。
    private final class BurstShots {
        private let lock = NSLock()
        private var images: [UIImage] = []
        private var stopped = false
        private let queue = DispatchQueue(label: "m17-burst")

        func start(delay: TimeInterval = 0) {
            queue.async { [weak self] in
                guard let self else { return }
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
                while !self.isStopped {
                    let shot = XCUIScreen.main.screenshot()
                    self.lock.lock()
                    self.images.append(shot.image)
                    self.lock.unlock()
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }

        private var isStopped: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        func finish() -> [UIImage] {
            lock.lock()
            stopped = true
            let result = images
            lock.unlock()
            return result
        }
    }

    /// 区域内统计边框色像素：R 通道占优（danger 红）与 B 通道占优（tint 蓝）。
    /// 精确描边色匹配：覆盖层描边不透明，像素即纯色——danger 0xE53935=(229,57,53)、
    /// tint 0x007AFF=(0,122,255)，容差 25。底色（含黄格 r 主导噪声）不参与判定，对模式判别免疫。
    private func dominantStrokePixels(in image: UIImage, region: CGRect) -> (red: Int, blue: Int) {
        guard let cg = image.cgImage else { return (0, 0) }
        let scale = cg.width / Int(image.size.width.rounded())
        let rect = CGRect(x: max(0, region.minX * CGFloat(scale)),
                          y: max(0, region.minY * CGFloat(scale)),
                          width: region.width * CGFloat(scale),
                          height: region.height * CGFloat(scale))
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return (0, 0) }
        let bytesPerRow = cg.bytesPerRow
        let bpp = cg.bitsPerPixel / 8
        var red = 0
        var blue = 0
        let x0 = Int(rect.minX), x1 = min(Int(rect.maxX), cg.width - 1)
        let y0 = Int(rect.minY), y1 = min(Int(rect.maxY), cg.height - 1)
        for y in y0...max(y0, y1) where y >= 0 {
            let row = y * bytesPerRow
            for x in x0...max(x0, x1) where x >= 0 {
                let offset = row + x * bpp
                if offset + 3 >= CFDataGetLength(data) { continue }
                let r = Int(ptr[offset]), g = Int(ptr[offset + 1]), b = Int(ptr[offset + 2])
                if abs(r - 229) < 25, abs(g - 57) < 25, abs(b - 53) < 25 { red += 1 }
                if r < 25, abs(g - 122) < 25, b > 230 { blue += 1 }
            }
        }
        return (red, blue)
    }

    /// 整个网格带扫描区（顶部 190pt 以下避开横幅/导航）。
    private func gridScanRegion(_ collection: XCUIElement) -> CGRect {
        let f = collection.frame
        let top = max(190, f.minY - 60)
        return CGRect(x: f.minX, y: top, width: f.width, height: max(50, f.maxY - top))
    }

    /// 单列跨行条带：拖拽路径带弧线（指尖先上抬），矩形顶边描边可能高于按压点行；
    /// 覆盖按压格上下各 100pt，横向取整格宽。该列不含 danger 色系图块，红色计数即描边。
    private func strokeStrip(of cell: XCUIElement) -> CGRect {
        let frame = cell.frame
        let top = max(190, frame.minY - 100)
        let bottom = frame.maxY + 100
        return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
    }

    /// 框选拖动期间覆盖层必须可见：连拍帧内检测 tint 描边像素（无覆盖层 → 0 像素 → 断言红）。
    /// 锚 col-2 黄格（cell 8/11）：黄格自身 r/g 高、b 低，蓝描边不与底色混淆；
    /// 拖拽路径带弧线 → 改用跨行高条带扫描，并要求蓝压红（选择模式判别）。
    func testMarqueeOverlayVisible() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let anchorCell = collection.cells.element(boundBy: 8)
        XCTAssertTrue(anchorCell.waitForExistence(timeout: 10), "网格无 cell")
        let strip = gridScanRegion(collection)
        let burst = BurstShots()
        burst.start(delay: 0.8)
        longPressDrag(in: collection, fromIndex: 8, toIndex: 11, hold: 1.2)
        let shots = burst.finish()
        XCTAssertGreaterThanOrEqual(shots.count, 3, "连拍必须覆盖拖动窗口")
        var bestBlue = 0
        var redAtBest = 0
        for shot in shots {
            let counts = dominantStrokePixels(in: shot, region: strip)
            if counts.blue > bestBlue {
                bestBlue = counts.blue
                redAtBest = counts.red
            }
            if counts.blue >= 25 { break }
        }
        if let data = shots.first?.pngData() {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "m17-overlay-burst"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertGreaterThanOrEqual(bestBlue, 25,
                                    "拖动期间必须出现 tint 描边（精确色匹配 ≥ 25，got \(bestBlue)）")
    }

    /// 取消模式（锚点已选 → 拖）覆盖层必须 danger 红。
    /// 种子图块含 danger 色系（红/橙块），绝对红色计数不可用作判别——改为两阶段对照：
    /// 先未选锚点拖（选择模式，tint 描边）取 danger 基线，再点选拖（取消模式，danger 描边），
    /// 断言 danger 像素显著增加（≥500）。底色两阶段相同，差值即描边贡献，对图块色免疫。
    func testDeselectModeShowsDangerTint() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let anchorCell = collection.cells.element(boundBy: 8)
        XCTAssertTrue(anchorCell.waitForExistence(timeout: 10), "网格无 cell")
        // 两阶段共用 cell 8 列条带：该列无 danger 色系图块；阶段 A 描边在 col 0 不入带 → 基线≈0
        let strip = strokeStrip(of: anchorCell)

        // 阶段 A：选择模式拖（锚点 cell 0 未选）——tint 描边基线
        let burstA = BurstShots()
        burstA.start(delay: 0.8)
        longPressDrag(in: collection, fromIndex: 0, toIndex: 6, hold: 1.2)
        let shotsA = burstA.finish()
        XCTAssertGreaterThanOrEqual(shotsA.count, 3, "阶段 A 连拍必须覆盖拖动窗口")
        var bestRedA = 0
        var bestBlueA = 0
        for shot in shotsA {
            let counts = dominantStrokePixels(in: shot, region: strip)
            bestRedA = max(bestRedA, counts.red)
            bestBlueA = max(bestBlueA, counts.blue)
        }
        XCTAssertLessThanOrEqual(bestRedA, 300,
                                 "选择模式条带内不得出现 danger 描边（red ≤ 300，got \(bestRedA)）")

        // 阶段 B：点选锚点（8/11）→ 取消模式拖（8→14）——danger 描边
        collection.cells.element(boundBy: 8).tap()
        collection.cells.element(boundBy: 11).tap()
        // 阶段 A 已框选 0/3/6（count=3）→ 点选 8/11 后计数=5
        let preCount = waitForSelectionCountEqual(app, to: 5, timeout: 5)
        XCTAssertEqual(preCount, 5, "点选 8/11 后计数必须为 5（count=\(preCount)）")
        // 对角拖（col 2 行 0 → col 1 行 2）：矩形有实际宽度，描边面积可判；框选仍只覆盖 8/11（已选）。
        // 合成触控偶发整手势未达 App——有界重试 2 次，连拍与计数检查逐轮进行，取成功轮连拍。
        var shotsB: [UIImage] = []
        var postCount = -1
        for attempt in 1...2 {
            let burstB = BurstShots()
            burstB.start(delay: 0.8)
            longPressDrag(in: collection, fromIndex: 8, toIndex: 16, hold: 1.2)
            shotsB = burstB.finish()
            postCount = waitForSelectionCountEqual(app, to: 3, timeout: 8)
            if postCount == 3 { break }
            if attempt == 1 { usleep(500_000) }
        }
        XCTAssertGreaterThanOrEqual(shotsB.count, 3, "阶段 B 连拍必须覆盖拖动窗口")
        // 功能断言：框过 8/11/16 区域 → 已选 8/11 全部取消（0/3/6 不受影响）→ 计数 5→3（取消模式语义）
        XCTAssertEqual(postCount, 3, "取消模式框选必须清掉锚选且不误伤其余（count=\(postCount)）")
        // 取证：横幅（计数变化触发刷新，读到 armed 时刻模式与覆盖层描边色/位置）
        let bannerAfter = (app.descendants(matching: .any)["Library-DebugSummary"].firstMatch.value as? String) ?? ""
        var bestRedB = 0
        var perShot = ""
        var bestShot: UIImage? = shotsB.first
        for shot in shotsB {
            let counts = dominantStrokePixels(in: shot, region: strip)
            perShot += "(r=\(counts.red) b=\(counts.blue)) "
            if counts.red > bestRedB {
                bestRedB = counts.red
                bestShot = shot
            }
        }
        if let png = bestShot?.pngData() {
            let att = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            att.name = "m17-deselect-best"
            att.lifetime = .keepAlways
            add(att)
        }
        XCTAssertGreaterThanOrEqual(bestRedB - bestRedA, 500,
                                    "取消模式 danger 描边必须显著高于选择模式基线（delta=\(bestRedB - bestRedA)，" +
                                    "A=\(bestRedA) B=\(bestRedB)，shots: \(perShot)，banner: \(bannerAfter)）")
    }
}
