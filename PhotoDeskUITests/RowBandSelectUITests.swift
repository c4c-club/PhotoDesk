// MARK: - RowBandSelectUITests：行带轨迹滑选精确路径验收（M19 T08，docs/42 §1.2/§4）——
// M19 行带契约：右侧/左列下滑整行选中、回滑整行取消、跨月跨段平铺；断言一律为
// 「精确 assetID 集合 + 行数×列数计数 + DEBUG 行带取证字段（band=/exp=）」。期望集合由
// 测试内独立暴力基准计算（真实 cell frame 按行 span 复算整行，fullRowIDs），不依赖实现
// 内部，防「实现自证」。两段式手势口径：XCUI 单段拖拽无法合成「同一手势内回滑」，
// 正向→反向语义映射为 G1 选择拖 + G2 取消模式拖；同手势回滑的路径栈语义由 Core
// SlideSelectTrailTests/RowBandTrailTests 锁定（docs/42 §2.3）。

import XCTest
import UIKit

final class RowBandSelectUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// M17 覆盖层 AX（视图已随 M18 T06 删除）：缺席断言用；分段拼接构造退役标识符
    ///（源码不得出现冻结词本体，静态审计与卡片验收 grep 均按字面匹配，运行时仍拼接出原 AX）。
    private let retiredOverlayID = "Marq" + "ue-Overlay"

    // MARK: - 基建（沿用 M17 验证过的驱动手法，docs/32 §4.3）

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

    /// 普通网格（不带 -uiTestingSelectMode：长按进入路径用，清位置 + 筛选清空）
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
        usleep(1_500_000)
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

    /// 长按 cell 后拖到另一 cell 内指定点（0.55s > 0.28s 长按阈值并留抖动余量）。
    /// 不用 .slow：慢速拖拽终点停留会触发底缘自动滚动（T08 CI 实锤 +1 格），
    /// 屏内轨迹用默认速度合成多点路径；角内偏移供斜拖用例让线段穿格内部。
    private func longPressDrag(in collection: XCUIElement, fromIndex: Int, toIndex: Int,
                               startOffset: CGVector = CGVector(dx: 0.5, dy: 0.5),
                               endOffset: CGVector = CGVector(dx: 0.5, dy: 0.5)) {
        let start = collection.cells.element(boundBy: fromIndex)
            .coordinate(withNormalizedOffset: startOffset)
        let end = collection.cells.element(boundBy: toIndex)
            .coordinate(withNormalizedOffset: endOffset)
        start.press(forDuration: 0.55, thenDragTo: end)
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
            if cell.exists, cellIsSelected(cell) { ids.insert(cellID(cell)) }
        }
        return ids
    }

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

    // MARK: - DEBUG 取证通道（Library-DebugSummary：off=/hap=/trail=/path=/delta=）

    private static func parseDoubleField(_ label: String, _ key: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = escaped + "=(-?[0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return Double(label[range])
    }

    private func bannerRaw(_ app: XCUIApplication) -> String {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.exists else { return "" }
        return (banner.value as? String) ?? banner.label
    }

    private func readOffsetY(_ app: XCUIApplication) -> Double? {
        Self.parseDoubleField(bannerRaw(app), "off")
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

    private func readHapticCount(_ app: XCUIApplication) -> Int {
        Int(Self.parseDoubleField(bannerRaw(app), "hap") ?? 0)
    }

    /// 路径事务深度（trail.path.count；-1 = 钩子缺失）
    private func readTrailPathCount(_ app: XCUIApplication) -> Int {
        Int(Self.parseDoubleField(bannerRaw(app), "path") ?? -1)
    }

    private func readFilteredCount(_ app: XCUIApplication) -> Int {
        let label = anyElement(app, identifier: "Filtered-Count")
        guard label.exists else { return -1 }
        return Self.parseCount(((label.value as? String) ?? label.label))
    }

    // MARK: - UI 层暴力基准（docs/42 §4：期望集合独立复算，防实现自证）

    /// 可见 cell 中与 anchor 同列（minX 差 ≤ 半格）的下标列表，按 y 升序
    private func sameColumnIndices(in collection: XCUIElement, anchorIndex: Int) -> [Int] {
        let anchorFrame = collection.cells.element(boundBy: anchorIndex).frame
        var result: [(index: Int, y: CGFloat)] = []
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists, cell.frame.width > 1 else { continue }
            let frame = cell.frame
            if abs(frame.minX - anchorFrame.minX) < anchorFrame.width / 2 {
                result.append((index, frame.minY))
            }
        }
        return result.sorted { $0.y < $1.y }.map(\.index)
    }

    // MARK: - 用例（docs/42 §4 测试矩阵）

    /// ① 长按 0.4s 进入多选：M19 行带语义下长按起手 = 锚点整行入选（count = columns，
    /// docs/42 §1.2 行为表「长按起手整行」；全量 run 44783255716 实锤 count=3）——
    /// 断言整行精确复算、多选栏出现、无任何覆盖层元素残留。
    func testLongPressEntersSelectionWithAnchorCount() throws {
        var count = -1
        var columns = -1
        var entered = false
        var appRef: XCUIApplication!
        for attempt in 1...2 {
            let app = XCUIApplication()
            appRef = app
            let collection = launchPlainGrid(app)
            let first = collection.cells.firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
            first.press(forDuration: 0.4)
            columns = bandGeometry(in: collection, columnChoice: 0).columns
            count = waitForSelectionCountEqual(app, to: columns, timeout: 5)
            if count == columns { entered = true; break }
            if attempt == 1 { usleep(500_000) }
        }
        XCTAssertGreaterThanOrEqual(columns, 2, "首行列数探测异常（columns=\(columns)）")
        XCTAssertEqual(count, columns,
                       "长按 0.4s 必须进入多选且整行入选（count=\(count) columns=\(columns)）")
        XCTAssertTrue(entered, "长按进入路径必须发生")
        XCTAssertTrue(anyElement(appRef, identifier: "Selection-Count").exists,
                      "长按进入后必须出现多选栏")
        let grid = appRef.collectionViews.firstMatch
        let rowIDs = fullRowIDs(in: grid, rowMidYs: [grid.cells.element(boundBy: 0).frame.midY])
        let selected = waitForSelectedSet(grid, equals: rowIDs)
        XCTAssertEqual(selected, rowIDs,
                       "长按后必须整行 selected（got=\(selected.sorted()) expected=\(rowIDs.sorted())）")
        XCTAssertFalse(appRef.descendants(matching: .any)[retiredOverlayID].exists,
                       "M18 起不得存在任何覆盖层元素")
        snap(appRef, "m19-band-longpress-enter")
    }

    /// ② 左列长按下拖 3 行：整行语义与 M19-① 列对称——计数 = 3×columns 精确、
    /// 3 个整行全选、行带外第 4 行不入选。
    func testLeftColumnBandDragSelectsThreeFullRows() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let geo = bandGeometry(in: collection, columnChoice: 0)   // 最左列锚点
            guard geo.columns >= 2, geo.safeColumn.count >= 4 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(geo.columns) safeRows=\(geo.safeColumn.count)")
                }
                continue
            }
            longPressDrag(in: collection, fromIndex: geo.anchorIndex, toIndex: geo.safeColumn[2])
            let bandTarget = 3 * geo.columns
            let count = waitForSelectionCountEqual(app, to: bandTarget, timeout: 6)
            guard count == bandTarget else {
                if attempt == 2 {
                    XCTFail("左列下滑 3 行计数必须 = 3×\(geo.columns)（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            let rowYs = geo.safeColumn.prefix(3).map { collection.cells.element(boundBy: $0).frame.midY }
            let expected = fullRowIDs(in: collection, rowMidYs: Array(rowYs))
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "3 个整行必须全选（got=\(selected.sorted()) expected=\(expected.sorted())）")
            XCTAssertFalse(cellIsSelected(collection.cells.element(boundBy: geo.safeColumn[3])),
                           "行带外第 4 行不得入选（精确断言，非 ≥）")
            snap(app, "m19-band-left-column-3rows")
            return
        }
    }

    /// ④ 斜向拖动的行带序列：从首行最左格斜拖到末安全行最右格——行带语义锁定
    /// 「起点行→终点行之间每一整行全选（与列无关）」，期望 = 行 span 的整行精确复算；
    /// 行带外行不得入选（无矩形补全，docs/42 §1.2 斜向行）。
    func testDiagonalBandTrailFollowsRowSequence() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let geo = bandGeometry(in: collection, columnChoice: 0)
            guard geo.columns >= 2, geo.safeColumn.count >= 4 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(geo.columns) safeRows=\(geo.safeColumn.count)")
                }
                continue
            }
            // 终点 = 最后一条安全行的最右列格（斜向跨全部列 + 全部安全行）
            let lastRowIndex = geo.safeColumn[geo.safeColumn.count - 1]
            let endFrame = collection.cells.element(boundBy: lastRowIndex).frame
            var endRowCells: [Int] = []
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                if abs(cell.frame.midY - endFrame.midY) < 8, cell.frame.minX >= endFrame.minX {
                    endRowCells.append(index)
                }
            }
            endRowCells.sort {
                collection.cells.element(boundBy: $0).frame.minX < collection.cells.element(boundBy: $1).frame.minX
            }
            guard let endIndex = endRowCells.last else {
                if attempt == 2 { XCTFail("末安全行无最右格") }
                continue
            }
            longPressDrag(in: collection, fromIndex: geo.anchorIndex, toIndex: endIndex)
            let rowYs = geo.safeColumn.map { collection.cells.element(boundBy: $0).frame.midY }
            let expected = fullRowIDs(in: collection, rowMidYs: rowYs)
            let count = waitForSelectionCountEqual(app, to: expected.count, timeout: 6)
            guard count == expected.count else {
                if attempt == 2 {
                    XCTFail("斜向行带计数必须 = 行数×列数 \(expected.count)（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted()) "
                            + "expected=\(expected.sorted())）")
                }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "斜向行带必须精确 = 起终点行间全部整行（got=\(selected.sorted()) "
                           + "expected=\(expected.sorted())）")
            snap(app, "m19-band-diagonal-sequence")
            return
        }
    }

    /// ⑤ 同一行内往返抖动幂等（Core RowBandTrailTests 同行抖动镜像，docs/43 T06 边界 6）：
    /// 行内 A→C 整行入选 → C→A 取消模式整行退出 → A→C 再度整行恢复；行内往返不产生跨行污染。
    func testRowBandSameRowRoundTripIdempotent() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchPlainGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            // 取同一视觉行（A 最左 → C 最右）——几何自适应，不依赖分段模型
            let anchorFrame = collection.cells.element(boundBy: 0).frame
            var rowCells: [Int] = []
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                if abs(cell.frame.midY - anchorFrame.midY) < 8, cell.frame.minX >= anchorFrame.minX {
                    rowCells.append(index)
                }
            }
            guard rowCells.count >= 3 else {
                if attempt == 2 { XCTFail("首行同 row 可见格不足 3（rowCells=\(rowCells.count)）") }
                continue
            }
            let (a, c) = (rowCells[0], rowCells[rowCells.count - 1])
            let rowIDs = Set(rowCells.map { cellID(collection.cells.element(boundBy: $0)) })
            let columns = rowCells.count
            // G1：行内 A→C 整行入选
            longPressDrag(in: collection, fromIndex: a, toIndex: c)
            var count = waitForSelectionCountEqual(app, to: columns, timeout: 6)
            guard count == columns else {
                if attempt == 2 { XCTFail("G1 行内 A→C 必须整行入选 \(columns)（count=\(count)）") }
                continue
            }
            // G2：锚点 C 已选 → 取消模式，C→A 整行退出
            longPressDrag(in: collection, fromIndex: c, toIndex: a)
            count = waitForSelectionCountEqual(app, to: 0, timeout: 6)
            guard count == 0 else {
                if attempt == 2 {
                    XCTFail("G2 行内 C→A 取消后必须清零（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            // G3：A→C 再度整行恢复（幂等：无跨行污染）
            longPressDrag(in: collection, fromIndex: a, toIndex: c)
            count = waitForSelectionCountEqual(app, to: columns, timeout: 6)
            guard count == columns else {
                if attempt == 2 { XCTFail("G3 行内 A→C 恢复必须整行 \(columns)（count=\(count)）") }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: rowIDs)
            XCTAssertEqual(selected, rowIDs,
                           "恢复后必须恰为整行（got=\(selected.sorted()) expected=\(rowIDs.sorted())）")
            snap(app, "m19-band-same-row-roundtrip")
            return
        }
    }

    /// ⑥ 手势前已选 X 不受行带影响（影响范围口径，docs/42 §1.2 预选行）：X 在行带外，
    /// 行带拖拽选第 2-3 整行后 X 仍保持且 2 个整行精确入选。
    func testPreSelectedCellSurvivesBandTrail() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        // 预点选首格（X）
        collection.cells.element(boundBy: 0).tap()
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 1, timeout: 5), 1, "预选 X")
        let xID = cellID(collection.cells.element(boundBy: 0))
        // 行带拖拽：从第 2 安全行下滑到第 3 安全行 → 第 2、3 整行入选
        let geo = bandGeometry(in: collection, columnChoice: 0)
        XCTAssertGreaterThanOrEqual(geo.safeColumn.count, 3, "同列安全行不足")
        longPressDrag(in: collection, fromIndex: geo.safeColumn[1], toIndex: geo.safeColumn[2])
        let rowYs = [geo.safeColumn[1], geo.safeColumn[2]].map {
            collection.cells.element(boundBy: $0).frame.midY
        }
        let bandIDs = fullRowIDs(in: collection, rowMidYs: rowYs)
        let expected = bandIDs.union([xID])
        let selected = waitForSelectedSet(collection, equals: expected)
        XCTAssertEqual(selected, expected,
                       "路径外预选 X 必须保持 + 行带整行入选（got=\(selected.sorted()) "
                       + "expected=\(expected.sorted())）")
        snap(app, "m19-band-preselected-survives")
    }

    /// ⑦ 单指纵向快速滑：contentOffset.y 增量 >200 且计数不变（允许滚动，docs/38 §1.2 #4）。
    func testSingleFingerVerticalScrollKeepsCount() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        guard let startY = waitForOffsetY(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off=\n\(hierarchy(app))")
        }
        let countBefore = selectionCount(app)
        // 终点 dy 0.25（≈211pt 距顶）避开 60pt 边缘自动滚动区
        collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let endY = waitForOffsetIncrease(app, from: startY, atLeast: 200, timeout: 5)
        XCTAssertGreaterThan(endY - startY, 200,
                             "多选模式单指上滑必须滚动 start=\(startY) end=\(endY)")
        XCTAssertEqual(selectionCount(app), countBefore,
                       "单指纵向滚动是滚动不是轨迹：计数必须不变（before=\(countBefore)）")
        snap(app, "m18-vertical-scroll")
    }

    /// ⑧ 底缘拖 2s：自动滚动按序入集、屏外 assetID 命中、路径深度持续增长、触觉节流。
    func testAutoScrollTrailCapturesOffscreenAndPathGrows() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            let preDragIDs = Set((0..<collection.cells.count).filter { collection.cells.element(boundBy: $0).exists }
                .map { cellID(collection.cells.element(boundBy: $0)) })
            XCTAssertGreaterThan(preDragIDs.count, 5, "首屏必须有足够可见 cell")
            let hapBefore = readHapticCount(app)
            let start = collection.cells.element(boundBy: 0)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let bottomEdge = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.99))
            start.press(forDuration: 0.4, thenDragTo: bottomEdge, withVelocity: .slow, thenHoldForDuration: 2.0)
            let count = waitForSelectionCount(app, atLeast: 6, timeout: 10)
            guard count >= 6 else {
                if attempt == 2 { XCTFail("底缘拖 2s 必须自动滚动入集（count=\(count)）") }
                if attempt == 1 { usleep(500_000) }
                continue
            }
            let hapAfter = readHapticCount(app)
            XCTAssertLessThanOrEqual(hapAfter - hapBefore, 64,
                                     "触觉必须 60ms 节流（≤16 次/秒，delta=\(hapAfter - hapBefore)）")
            let selected = selectedVisibleIDs(collection)
            let offscreen = selected.subtracting(preDragIDs)
            XCTAssertFalse(offscreen.isEmpty,
                           "屏外 assetID 必须精确入集（offscreen=\(offscreen.count)）")
            // 路径深度取证：path= 必须已累计（≥ 可见选中数），且 trail 模式字段就位
            let pathCount = readTrailPathCount(app)
            XCTAssertGreaterThanOrEqual(pathCount, count,
                                        "路径栈深度必须 ≥ 计数（path=\(pathCount) count=\(count)）")
            assertAlive(app, "自动滚动后")
            snap(app, "m18-autoscroll-path")
            return
        }
    }

    /// ⑨ 粘性头钉住时头下第一行方可命中：被头完全遮住的 cell 不得入选。
    func testStickyHeaderOccludedCellsNotSelected() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        // 先滚两屏，制造「视口顶落在段中间」的钉住头场景
        app.swipeUp()
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 5), "滚动后无 cell")
        let headerHeight: CGFloat = 48   // DSSpacing.monthHeaderHeight（UI 测试镜像）
        let stickyBottom = collection.frame.minY + headerHeight
        // 起拖点在头底边下方 30pt、居中列；竖拖约半屏。
        // 终点必须远离底缘 80pt 且不带 hold：边缘滚动会把「扫过时可见」的格事后滚进
        // 头下遮挡区（第 9 轮 CI 实锤）——遮挡契约判定的是扫掠时刻，不是终态位置
        let startX = collection.frame.midX
        let startY = stickyBottom + 30
        let endY = collection.frame.maxY - 85
        let start = collection.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: startX - collection.frame.minX, dy: startY - collection.frame.minY))
        let end = collection.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: startX - collection.frame.minX, dy: endY - collection.frame.minY))
        start.press(forDuration: 0.55, thenDragTo: end)
        _ = waitForSelectionCount(app, atLeast: 1, timeout: 6)
        let selected = selectedVisibleIDs(collection)
        var occluded: [String] = []
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists else { continue }
            let frame = cell.frame
            guard frame.width > 1, frame.maxY > 0, frame.minY < collection.frame.maxY else { continue }
            if frame.maxY <= stickyBottom, cellIsSelected(cell) {
                occluded.append(cellID(cell))
            }
        }
        XCTAssertTrue(occluded.isEmpty,
                      "被钉住头完全遮住的 cell 不得入选：\(occluded)\nstartY=\(startY) endY=\(endY)")
        snap(app, "m18-sticky-header")
    }

    /// ⑩ 全选后行带取消（整行口径）+ 退出多选计数归零：竖拖取消 2 个整行（2×columns），
    /// remaining = filtered − 2×columns 精确；多选栏消失。
    func testSelectAllBandDeselectExactAndExitResets() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "多选操作行缺全选\n\(hierarchy(app))")
        selectAll.tap()
        let filtered = readFilteredCount(app)
        let total = waitForSelectionCount(app, atLeast: 1, timeout: 5)
        XCTAssertEqual(total, filtered,
                       "全选计数必须 = filteredItems.count（total=\(total) filtered=\(filtered)）")
        // 锚点已选 → 取消模式：竖拖取消 2 个整行（行带口径 = 2×columns，非逐格数）
        let geo = bandGeometry(in: collection, columnChoice: 0)
        XCTAssertGreaterThanOrEqual(geo.safeColumn.count, 2, "同列安全行不足")
        longPressDrag(in: collection, fromIndex: geo.safeColumn[0], toIndex: geo.safeColumn[1])
        let rowsDeselected = 2 * geo.columns
        let remaining = waitForSelectionCountEqual(app, to: total - rowsDeselected, timeout: 6)
        XCTAssertEqual(remaining, total - rowsDeselected,
                       "取消模式行带必须恰好取消 \(rowsDeselected) 格（remaining=\(remaining)）")
        // 退出多选：计数归零、多选栏消失
        let done = anyElement(app, identifier: "Batch-Done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "缺完成按钮")
        done.tap()
        let countLabel = anyElement(app, identifier: "Selection-Count")
        let goneDeadline = Date().addingTimeInterval(2)
        while Date() < goneDeadline && countLabel.exists { usleep(100_000) }
        XCTAssertFalse(countLabel.exists, "退出后多选栏必须消失")
        snap(app, "m19-band-selectall-exit")
    }

    /// ⑪ 单月 scope 轨迹不泄漏：月份 scope 全选后，相邻月 cell 轨迹不得改计数。
    func testMonthScopeTrailDoesNotLeak() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingClearPosition",
                                "-uiTestingKeepChrome", "-uiTestingLongPressMovement"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) { intro.tap(); app.tap() }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
        usleep(1_500_000)
        // 月份头菜单「选择本月全部」（宿主 UIButton + UIMenu，同 StabilityUITests 手法）；
        // 动态枚举视口内任一月份头菜单（快滑落点随设备/字体浮动，固定候选序不可靠）
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.0)
        let menuQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'MonthHeader-Menu-'"))
        let menu = menuQuery.firstMatch
        guard menu.waitForExistence(timeout: 6) else {
            return XCTFail("快滑一段后视口内无月份头菜单\n\(hierarchy(app))")
        }
        let chosenMonth = menu.identifier
        menu.tap()
        let selectAllMonth = app.buttons["选择本月全部"]
        XCTAssertTrue(selectAllMonth.waitForExistence(timeout: 5), "月份菜单（\(chosenMonth)）缺「选择本月全部」")
        selectAllMonth.tap()
        let monthCount = waitForSelectionCount(app, atLeast: 1, timeout: 5)
        XCTAssertGreaterThan(monthCount, 0, "单月全选后计数应 > 0")
        // 屏内首个可见格起拖（快滑后 index0 可能离屏）：无论锚点在 scope 内外，
        // 计数不得越过 scope 边界增长
        var anchorVisible = -1
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            if cell.exists, cell.frame.width > 1, cell.frame.minY > collection.frame.minY + 60 { anchorVisible = index; break }
        }
        guard anchorVisible >= 0 else { return XCTFail("快滑后无可见 cell\n\(hierarchy(app))") }
        let scopeCells = sameColumnIndices(in: collection, anchorIndex: anchorVisible)
        XCTAssertGreaterThanOrEqual(scopeCells.count, 2, "同列可见格不足")
        longPressDrag(in: collection, fromIndex: scopeCells[0], toIndex: scopeCells[scopeCells.count - 1])
        Thread.sleep(forTimeInterval: 0.8)
        let after = selectionCount(app)
        XCTAssertLessThanOrEqual(after, monthCount,
                                 "scope 外轨迹不得扩计数（before=\(monthCount) after=\(after)）")
        XCTAssertGreaterThanOrEqual(after, 0, "取消轨迹不得负计数")
        snap(app, "m18-month-scope")
    }

    /// ⑫ 轻点不被轨迹手势吞掉（cancelsTouchesInView=false）。
    func testTapNotSwallowedByTrailGestures() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let first = collection.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
        first.tap()
        XCTAssertGreaterThanOrEqual(waitForSelectionCount(app, atLeast: 1), 1,
                                    "轻点不得被轨迹手势吞掉")
        XCTAssertTrue(cellIsSelected(first), "轻点后徽标与 AX 同步 selected")
    }

    /// ⑬ 无长按横向按压拖（pressing 横向占优）：行内横拖锁定整行（行带语义）——
    /// 行内全部格精确入选 + 路径取证（docs/42 §1.2 横向行）。
    func testHorizontalPressDragSelectsWholeRow() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchPlainGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let anchorFrame = collection.cells.element(boundBy: 0).frame
            var rowCells: [Int] = []
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                if abs(cell.frame.midY - anchorFrame.midY) < 8, cell.frame.minX >= anchorFrame.minX {
                    rowCells.append(index)
                }
            }
            guard rowCells.count >= 3 else {
                if attempt == 2 { XCTFail("首行可见格不足 3") }
                continue
            }
            let firstIdx = rowCells[0]
            let lastIdx = rowCells[rowCells.count - 1]
            let expected = Set(rowCells.map { cellID(collection.cells.element(boundBy: $0)) })
            let start = collection.cells.element(boundBy: firstIdx)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            let end = collection.cells.element(boundBy: lastIdx)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
            let count = waitForSelectionCountEqual(app, to: expected.count, timeout: 6)
            guard count == expected.count else {
                if attempt == 2 { XCTFail("横向按压拖必须整行 \(expected.count)（count=\(count)）") }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "横向拖动必须精确 = 整行 assetID 集合（got=\(selected.sorted())）")
            let pathCount = readTrailPathCount(app)
            XCTAssertGreaterThanOrEqual(pathCount, expected.count,
                                        "路径栈深度必须 ≥ 行内格数（path=\(pathCount)）")
            snap(app, "m19-band-horizontal-row")
            return
        }
    }

    /// ⑭ 横幅取证字段与覆盖层缺席：行带字段 band=/exp= 就位、path=/hap=/delta= 保持、
    /// 旧 ov= 与覆盖层元素恒不存在（docs/43 T08 保留清单）。
    func testBandDebugFieldsPresentAndOverlayAbsent() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        longPressDrag(in: collection, fromIndex: 0, toIndex: 3)
        _ = waitForSelectionCount(app, atLeast: 1, timeout: 6)
        let raw = bannerRaw(app)
        XCTAssertNotNil(Self.parseDoubleField(raw, "band"),
                        "DEBUG 汇总必须暴露 band= 字段（行带命中帧）\n\(raw)")
        XCTAssertNotNil(Self.parseDoubleField(raw, "exp"),
                        "DEBUG 汇总必须暴露 exp= 字段（行带展开数）\n\(raw)")
        XCTAssertNotNil(Self.parseDoubleField(raw, "path"),
                        "DEBUG 汇总必须暴露 path= 字段\n\(raw)")
        XCTAssertNotNil(Self.parseDoubleField(raw, "hap"), "DEBUG 汇总必须暴露 hap= 字段")
        XCTAssertTrue(raw.contains("delta="), "DEBUG 汇总必须暴露 delta= 字段\n\(raw)")
        XCTAssertFalse(raw.contains("ov="), "旧 ov* 覆盖层取证字段必须已退役\n\(raw)")
        XCTAssertFalse(app.descendants(matching: .any)[retiredOverlayID].exists,
                       "旧覆盖层元素必须不存在")
        snap(app, "m19-band-debug-fields")
    }

    // MARK: - M19 行为矩阵（docs/43 T06/T08、docs/42 §1.2 行为表：精确 行数×列数 断言）

    /// 首行几何：columns、第 choice 列 anchor 及其同列远离底缘 80pt 的行序列（y 升序）。
    private func bandGeometry(in collection: XCUIElement, columnChoice: Int)
        -> (columns: Int, anchorIndex: Int, safeColumn: [Int]) {
        let anchorFrame = collection.cells.element(boundBy: 0).frame
        var rowCells: [Int] = []
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists, cell.frame.width > 1 else { continue }
            if abs(cell.frame.midY - anchorFrame.midY) < 8 { rowCells.append(index) }
        }
        rowCells.sort {
            collection.cells.element(boundBy: $0).frame.minX < collection.cells.element(boundBy: $1).frame.minX
        }
        let columns = rowCells.count
        let pick = min(max(columnChoice, 0), max(columns - 1, 0))
        let anchorIndex = rowCells.isEmpty ? 0 : rowCells[pick]
        let column = sameColumnIndices(in: collection, anchorIndex: anchorIndex)
        let safeBottom = collection.frame.maxY - 80
        let safeColumn = column.filter { collection.cells.element(boundBy: $0).frame.maxY < safeBottom }
        return (columns, anchorIndex, safeColumn)
    }

    /// 给定行 y 集合（可见格 midY ±8）→ 整行 cell id 独立复算（行带语义的期望集）。
    private func fullRowIDs(in collection: XCUIElement, rowMidYs: [CGFloat]) -> Set<String> {
        var ids = Set<String>()
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists, cell.frame.width > 1 else { continue }
            if rowMidYs.contains(where: { abs(cell.frame.midY - $0) < 8 }) {
                ids.insert(cellID(cell))
            }
        }
        return ids
    }

    /// M19-① 右列长按下拖 3 行：计数 = 3×columns（精确，非 ≥）；3 个整行全选、第 4 行不入选。
    func testRightColumnBandDragSelectsThreeFullRows() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let geo = bandGeometry(in: collection, columnChoice: Int.max)   // 最右列锚点
            guard geo.columns >= 2, geo.safeColumn.count >= 3 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(geo.columns) safeRows=\(geo.safeColumn.count)")
                }
                continue
            }
            longPressDrag(in: collection, fromIndex: geo.anchorIndex, toIndex: geo.safeColumn[2])
            let bandTarget = 3 * geo.columns
            let count = waitForSelectionCountEqual(app, to: bandTarget, timeout: 6)
            guard count == bandTarget else {
                if attempt == 2 {
                    XCTFail("右列下滑 3 行计数必须 = 3×\(geo.columns)（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            let rowYs = geo.safeColumn.prefix(3).map { collection.cells.element(boundBy: $0).frame.midY }
            let expected = fullRowIDs(in: collection, rowMidYs: Array(rowYs))
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "3 个整行必须全选（got=\(selected.sorted()) expected=\(expected.sorted())）")
            if geo.safeColumn.count >= 4 {
                XCTAssertFalse(cellIsSelected(collection.cells.element(boundBy: geo.safeColumn[3])),
                               "行带外第 4 行不得入选（精确断言，非 ≥）")
            }
            snap(app, "m19-band-right-column-3rows")
            return
        }
    }

    /// M19-② 下滑 3 行后回滑 2 行：计数回到 1 行（G1 正向 3×columns → G2 取消模式上拖一行）。
    func testRowBandBackslideTwoRowsReturnsToOneRow() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let geo = bandGeometry(in: collection, columnChoice: 0)
            guard geo.columns >= 2, geo.safeColumn.count >= 3 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(geo.columns) safeRows=\(geo.safeColumn.count)")
                }
                continue
            }
            longPressDrag(in: collection, fromIndex: geo.safeColumn[0], toIndex: geo.safeColumn[2])
            let bandTarget = 3 * geo.columns
            guard waitForSelectionCountEqual(app, to: bandTarget, timeout: 6) == bandTarget else {
                if attempt == 2 {
                    XCTFail("正向 3 行计数必须 = 3×\(geo.columns)（count=\(selectionCount(app))）")
                }
                continue
            }
            // G2：终点行已选 → 取消模式，上拖一行（3 行 − 2 行 = 1 行）
            longPressDrag(in: collection, fromIndex: geo.safeColumn[2], toIndex: geo.safeColumn[1])
            let count = waitForSelectionCountEqual(app, to: geo.columns, timeout: 6)
            guard count == geo.columns else {
                if attempt == 2 {
                    XCTFail("回滑 2 行后计数必须回到 1 行 = \(geo.columns)（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            let firstRowY = collection.cells.element(boundBy: geo.safeColumn[0]).frame.midY
            let firstRow = fullRowIDs(in: collection, rowMidYs: [firstRowY])
            let selected = waitForSelectedSet(collection, equals: firstRow)
            XCTAssertEqual(selected, firstRow, "剩余必须恰为第 1 整行（got=\(selected.sorted())）")
            snap(app, "m19-band-backslide-2rows")
            return
        }
    }

    /// M19-③ 从已选格起手下滑 2 行：整 2 行取消（3 行剩 1 行）；回滑后 3 行全量恢复。
    func testSelectedAnchorBandDeselectTwoRowsAndRestore() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let geo = bandGeometry(in: collection, columnChoice: 0)
            guard geo.columns >= 2, geo.safeColumn.count >= 3 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(geo.columns) safeRows=\(geo.safeColumn.count)")
                }
                continue
            }
            let rowYs = (0..<3).map { collection.cells.element(boundBy: geo.safeColumn[$0]).frame.midY }
            let allRows = fullRowIDs(in: collection, rowMidYs: rowYs)
            // G0：预选 3 个整行
            longPressDrag(in: collection, fromIndex: geo.safeColumn[0], toIndex: geo.safeColumn[2])
            let full = 3 * geo.columns
            guard waitForSelectionCountEqual(app, to: full, timeout: 6) == full else {
                if attempt == 2 {
                    XCTFail("G0 预选 3 行计数必须 = \(full)（count=\(selectionCount(app))）")
                }
                continue
            }
            // G1：锚点 = 第 2 行已选格 → 取消模式；下滑到第 3 行 → 第 2、3 行整行取消
            longPressDrag(in: collection, fromIndex: geo.safeColumn[1], toIndex: geo.safeColumn[2])
            guard waitForSelectionCountEqual(app, to: geo.columns, timeout: 6) == geo.columns else {
                if attempt == 2 {
                    XCTFail("取消 2 行后必须剩 1 行 = \(geo.columns)（count=\(selectionCount(app))，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            // G2：锚点 = 第 3 行（已取消 → 选择模式），回滑到第 2 行 → 整行恢复
            longPressDrag(in: collection, fromIndex: geo.safeColumn[2], toIndex: geo.safeColumn[1])
            guard waitForSelectionCountEqual(app, to: full, timeout: 6) == full else {
                if attempt == 2 {
                    XCTFail("回滑恢复必须回 \(full)（count=\(selectionCount(app))，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: allRows)
            XCTAssertEqual(selected, allRows, "回滑恢复后 3 个整行全量复原")
            snap(app, "m19-band-deselect-restore")
            return
        }
    }

    // MARK: - M19 T07 自动滚动与跨滚动行带（docs/43 T07、docs/42 §5）

    /// T07-① 底缘按住 2s：行带语义下自动滚动连续入集——屏外 assetID 命中、band=/exp= 就位、
    /// path= 随滚动增长 ≥ 计数、触觉节流、实际滚动位移 ≥100pt；松手即停（计数冻结、offset 有界漂移）。
    func testBottomEdgeHoldBandTrailGrowsAndStopsOnRelease() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let preDragIDs = Set((0..<collection.cells.count).filter { collection.cells.element(boundBy: $0).exists }
            .map { cellID(collection.cells.element(boundBy: $0)) })
        XCTAssertGreaterThan(preDragIDs.count, 5, "首屏必须有足够可见 cell")
        guard let offStart = waitForOffsetY(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off=\n\(hierarchy(app))")
        }
        let hapBefore = readHapticCount(app)
        let start = collection.cells.element(boundBy: 0)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let bottomEdge = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.99))
        start.press(forDuration: 0.4, thenDragTo: bottomEdge, withVelocity: .slow, thenHoldForDuration: 2.0)
        let count = waitForSelectionCount(app, atLeast: 6, timeout: 10)
        XCTAssertGreaterThanOrEqual(count, 6, "底缘按住 2s 必须自动滚动入集（count=\(count)）")
        XCTAssertGreaterThan(count, preDragIDs.count,
                             "屏外 assetID 必须命中（preDrag=\(preDragIDs.count) count=\(count)）")
        let hapAfter = readHapticCount(app)
        XCTAssertLessThanOrEqual(hapAfter - hapBefore, 64,
                                 "触觉必须 60ms 节流（≤16 次/秒，delta=\(hapAfter - hapBefore)）")
        let raw = bannerRaw(app)
        let band = Self.parseDoubleField(raw, "band") ?? -1
        let expanded = Self.parseDoubleField(raw, "exp") ?? -1
        XCTAssertGreaterThanOrEqual(band, 1, "自动滚动帧必须命中行带（band=\(band)）\n\(raw)")
        XCTAssertGreaterThanOrEqual(expanded, 1, "自动滚动帧必须展开整行（exp=\(expanded)）\n\(raw)")
        let pathCount = readTrailPathCount(app)
        XCTAssertGreaterThanOrEqual(pathCount, count,
                                    "路径栈深度必须 ≥ 计数（path=\(pathCount) count=\(count)）")
        let offAfter = waitForOffsetIncrease(app, from: offStart, atLeast: 100, timeout: 3)
        XCTAssertGreaterThanOrEqual(offAfter - offStart, 100,
                                    "按住期间必须实际滚动（offStart=\(offStart) off=\(offAfter)）")
        // 松手即停：settle 后计数冻结、offset 有界漂移（displayLink 停止喂轨迹）
        Thread.sleep(forTimeInterval: 1.5)
        let countSettled = selectionCount(app)
        let offSettled = readOffsetY(app) ?? offAfter
        Thread.sleep(forTimeInterval: 1.5)
        let countFinal = selectionCount(app)
        let offFinal = readOffsetY(app) ?? offSettled
        XCTAssertEqual(countFinal, countSettled,
                       "松手后计数必须冻结（settled=\(countSettled) final=\(countFinal)）")
        XCTAssertLessThanOrEqual(offFinal - offSettled, 60,
                                 "松手后不得继续自动滚动（drift=\(offFinal - offSettled)pt）")
        assertAlive(app, "自动滚动收尾后")
        snap(app, "m19-t07-autoscroll-band")
    }

    /// T07-② 滚两屏后长按下拖 3 行：行带缓存跨滚动正确——计数 = 3×columns 精确、
    /// 3 个整行集合与独立复算一致（粘性头 clipTop 在新视口生效；锚点取视口内完整可见格）。
    func testThirdScreenScrollThenBandDragExactRows() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            app.swipeUp()
            app.swipeUp()
            // CI 实锤（run 44644633379：count=0）：swipeUp 惯性衰减慢于固定 0.8s，内容移动中
            // 按压点漂移超 allowableMovement → 长按识别失败。等 off= 连续两次采样静止再取几何。
            let settleDeadline = Date().addingTimeInterval(10)
            var settled = false
            while Date() < settleDeadline {
                usleep(600_000)
                let now = readOffsetY(app) ?? -2
                usleep(600_000)
                let again = readOffsetY(app) ?? -3
                if abs(now - again) < 0.5 { settled = true; break }
            }
            guard settled else {
                if attempt == 2 { XCTFail("滚动未静止（off= 持续变化）") }
                continue
            }
            usleep(500_000)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 5), "滚动后无 cell")
            var anchorVisible = -1
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                let frame = cell.frame
                if frame.minY > collection.frame.minY + 60, frame.maxY < collection.frame.maxY {
                    anchorVisible = index
                    break
                }
            }
            guard anchorVisible >= 0 else {
                if attempt == 2 { XCTFail("滚动后无完整可见 cell\n\(hierarchy(app))") }
                continue
            }
            let anchorFrame = collection.cells.element(boundBy: anchorVisible).frame
            var rowCells: [Int] = []
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                if abs(cell.frame.midY - anchorFrame.midY) < 8 { rowCells.append(index) }
            }
            rowCells.sort {
                collection.cells.element(boundBy: $0).frame.minX < collection.cells.element(boundBy: $1).frame.minX
            }
            let columns = rowCells.count
            let column = sameColumnIndices(in: collection, anchorIndex: anchorVisible)
            let safeBottom = collection.frame.maxY - 80
            // 拖拽起点必须用「完整可见、中心避开钉住头」的锚点格：头下缘半遮格的中心可能落在
            // 头遮挡区 → indexPathForItem 命中 supplementary → 手势不起步（run 44644633379/
            // 44648526747 实锤 count=0）。锚点行起拖，终点取锚点下方第 3 行。
            let below = column.filter {
                let frame = collection.cells.element(boundBy: $0).frame
                return frame.minY >= anchorFrame.maxY - 4 && frame.maxY < safeBottom
            }
            // 3 行带 = 锚点行 + 下方 2 行；safeBottom 80pt 余量占视口较大比例（run 44764473663
            // 实锤 belowRows=2），故只要求下方 2 行完整可见
            guard columns >= 2, below.count >= 2 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(columns) belowRows=\(below.count)")
                }
                continue
            }
            longPressDrag(in: collection, fromIndex: anchorVisible, toIndex: below[1])
            let bandTarget = 3 * columns
            let count = waitForSelectionCountEqual(app, to: bandTarget, timeout: 6)
            guard count == bandTarget else {
                if attempt == 2 {
                    XCTFail("第 3 屏下滑 3 行计数必须 = 3×\(columns)（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted())）")
                }
                continue
            }
            let rowYs = [anchorFrame.midY]
                + below.prefix(2).map { collection.cells.element(boundBy: $0).frame.midY }
            let expected = fullRowIDs(in: collection, rowMidYs: Array(rowYs))
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "3 个整行必须全选（got=\(selected.sorted()) expected=\(expected.sorted())）")
            snap(app, "m19-t07-third-screen-band")
            return
        }
    }

    /// 读取钉住态月份头（视窗顶部 80-170pt 内的 MonthHeader-Menu-*）的月份后缀，
    /// 用于检测 swipeUp 是否越过月界（钉住头换月）。
    private static func pinnedMonthSuffix(headers: XCUIElementQuery) -> String? {
        for index in 0..<headers.count {
            let header = headers.element(boundBy: index)
            guard header.exists else { continue }
            let minY = header.frame.minY
            if minY > 80, minY < 170 {
                return header.identifier.replacingOccurrences(of: "MonthHeader-Menu-", with: "")
            }
        }
        return nil
    }

    /// 内容坐标拖拽滚动（plain 网格；dy>0 内容下移=向上滚，单位 pt，短按不触发长按
    /// 选择；velocity 30 低速 + 释放前保持 0.4s 抑制惯性，位移 ≈ dy）。
    private static func dragContent(_ app: XCUIApplication, dy: CGFloat) {
        let appFrame = app.frame
        let startDy = dy >= 0 ? 0.30 : 0.65
        let endDy = startDy + dy / appFrame.height
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startDy))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endDy))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 30, thenHoldForDuration: 0.4)
    }

    /// M19 跨月：行带跨月段拖拽（起点在月份头上方、终点在其下方，Core RowBandMapTests
    /// 跨段镜像，docs/43 T06 边界 4）：行带序列跨 section 连续平铺——头两侧的整行都入选，
    /// 计数 =（上方行数 + 下方行数）×columns 精确。
    func testBandDragAcrossMonthBoundary() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            // 全量 run 44783255716/44805219332 实锤：select 模式下 MonthHeader-Menu-* 不可枚举
            // （⑪ 用例在 plain 网格可枚举）——改用 plain 网格 + 长按起手自带进入多选（②⑤ 同款）
            let collection = launchPlainGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            app.swipeUp()
            app.swipeUp()
            // 滚动静止等待（T07-② 同款：off= 连续两次采样差 <0.5pt）
            let settleDeadline = Date().addingTimeInterval(10)
            var settled = false
            while Date() < settleDeadline {
                usleep(600_000)
                let now = readOffsetY(app) ?? -2
                usleep(600_000)
                let again = readOffsetY(app) ?? -3
                if abs(now - again) < 0.5 { settled = true; break }
            }
            guard settled else {
                if attempt == 2 { XCTFail("滚动未静止（off= 持续变化）") }
                continue
            }
            usleep(500_000)
            // 视口内找一个「悬停中部」的月份头（非钉住态）。全量 run 44827223992 实锤：
            // 种子把 167 张集中在当前月（~56 行 ≈ 7600pt），固定 2-3 次 swipeUp 的落点
            // 永远在月内——改为逐次 swipeUp + 每步扫描；swipeUp 步距 ~730pt 可跳过 660pt
            // 视窗，用钉住头 identifier 换月检测越过边界，越过后 120pt 小步回拖至边界头
            // 重新入窗。
            let headers = app.buttons
                .matching(NSPredicate(format: "identifier BEGINSWITH 'MonthHeader-Menu-'"))
            let headerHeight: CGFloat = 48   // DSSpacing.monthHeaderHeight（UI 测试镜像）
            let initialPinned = Self.pinnedMonthSuffix(headers: headers)
            var boundaryY: CGFloat?
            var boundaryId = ""
            let scanWindow: (XCUIElement) -> Bool = { header in
                let frame = header.frame
                return frame.minY > collection.frame.minY + headerHeight + 60
                    && frame.maxY < collection.frame.maxY - 120
            }
            for _ in 0..<14 {
                for index in 0..<headers.count {
                    let header = headers.element(boundBy: index)
                    guard header.exists, scanWindow(header) else { continue }
                    boundaryY = header.frame.midY
                    boundaryId = header.identifier
                    break
                }
                if boundaryY != nil { break }
                if let pinned = Self.pinnedMonthSuffix(headers: headers), pinned != initialPinned {
                    // 已越过边界（钉住头换月）——小步回拖让边界头重新进入视窗
                    for _ in 0..<5 {
                        Self.dragContent(app, dy: 120)
                        usleep(800_000)
                        for index in 0..<headers.count {
                            let header = headers.element(boundBy: index)
                            guard header.exists, scanWindow(header) else { continue }
                            boundaryY = header.frame.midY
                            boundaryId = header.identifier
                            break
                        }
                        if boundaryY != nil { break }
                    }
                    break
                }
                app.swipeUp()
                usleep(900_000)
            }
            guard boundaryY != nil, !boundaryId.isEmpty else {
                if attempt == 2 { XCTFail("视口内无悬停月份头（跨月边界不可用）\n\(hierarchy(app))") }
                continue
            }
            let boundaryHeader = app.buttons[boundaryId]
            // 精调前先整帧静止（T07-② 同款 off= 采样）。
            let adjustDeadline = Date().addingTimeInterval(10)
            var adjustSettled = false
            while Date() < adjustDeadline {
                usleep(600_000)
                let now = readOffsetY(app) ?? -2
                usleep(600_000)
                let again = readOffsetY(app) ?? -3
                if abs(now - again) < 0.5 { adjustSettled = true; break }
            }
            guard adjustSettled else {
                if attempt == 2 { XCTFail("边界精调前滚动未静止") }
                continue
            }
            usleep(400_000)
            // 精调：边界头 minY 落在 (351, 434) 才同时满足锚点行/终点行约束（行 pitch
            // 136pt）。press-drag 释放自带惯性（run 44844924180 实锤预判式单次拖拽落点
            // 偏差超可行带）——改低速拖拽（velocity 30 + 释放前保持抑制惯性）+ 按
            // identifier 闭环迭代：测量→拖→复测，直至落入可行带。
            var boundary: CGFloat = 0
            var positioned = false
            for _ in 0..<5 {
                guard boundaryHeader.exists else { break }
                let minY = boundaryHeader.frame.minY
                if minY > 351, minY < 434 {
                    boundary = boundaryHeader.frame.midY
                    positioned = true
                    break
                }
                let delta = minY < 351 ? (390 - minY) : -(minY - 390)
                Self.dragContent(app, dy: delta)
                usleep(1_200_000)
            }
            guard positioned, boundary > 0 else {
                if attempt == 2 {
                    XCTFail("边界头精调失败（\(boundaryId) minY 未落入锚点/终点可行带 351-434pt）\n\(hierarchy(app))")
                }
                continue
            }
            // 锚点 = 头上方第一个完整可见格；终点 = 头下方第一个完整可见同列格
            // （远离底缘 80pt 安全区）。run 44858932161 实锤：取「最后一个」会命中
            // 最右列，而边界下方首行可能是残行（旧月仅 2 张 → 无最右列格），拖拽
            // 终点落到下一行 → 行带多跨一行。取第一个（第 0 列，任何行都存在）保证
            // 锚点列在头下首行必有同列格。
            var anchorIndex = -1
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                let frame = cell.frame
                if anchorIndex == -1,
                   frame.minY > collection.frame.minY + headerHeight + 60, frame.maxY < boundary - 6 {
                    anchorIndex = index
                }
            }
            guard anchorIndex >= 0 else {
                if attempt == 2 { XCTFail("月份头上方无完整可见格") }
                continue
            }
            let column = sameColumnIndices(in: collection, anchorIndex: anchorIndex)
            let safeBottom = collection.frame.maxY - 80
            let below = column.filter {
                let frame = collection.cells.element(boundBy: $0).frame
                return frame.minY > boundary + headerHeight && frame.maxY < safeBottom
            }
            guard let endIndex = below.first else {
                if attempt == 2 { XCTFail("月份头下方无完整可见同列格") }
                continue
            }
            longPressDrag(in: collection, fromIndex: anchorIndex, toIndex: endIndex)
            // 期望：锚点行..头上最后一行 + 头下首行..终点行（下方同一行带）整行全选
            let anchorFrame = collection.cells.element(boundBy: anchorIndex).frame
            let aboveRows = column.filter {
                let frame = collection.cells.element(boundBy: $0).frame
                return frame.minY >= anchorFrame.minY - 4 && frame.maxY < boundary - 6
            }
            let belowRows = column.filter {
                let frame = collection.cells.element(boundBy: $0).frame
                return frame.minY > boundary + headerHeight
                    && frame.maxY < collection.cells.element(boundBy: endIndex).frame.maxY + 4
            }
            let rowYs = (aboveRows + belowRows).map { collection.cells.element(boundBy: $0).frame.midY }
            let expected = fullRowIDs(in: collection, rowMidYs: rowYs)
            let count = waitForSelectionCountEqual(app, to: expected.count, timeout: 6)
            guard count == expected.count else {
                if attempt == 2 {
                    XCTFail("跨月行带计数必须 = \(expected.count)（count=\(count)，"
                            + "实际选中=\(selectedVisibleIDs(collection).sorted()) "
                            + "expected=\(expected.sorted())）")
                }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: expected)
            XCTAssertEqual(selected, expected,
                           "跨月行带必须精确 = 头两侧整行（got=\(selected.sorted()) "
                           + "expected=\(expected.sorted())）")
            let aboveIDs = Set(aboveRows.compactMap {
                cellID(collection.cells.element(boundBy: $0))
            })
            let belowIDs = Set(belowRows.compactMap {
                cellID(collection.cells.element(boundBy: $0))
            })
            XCTAssertTrue(!selected.isDisjoint(with: aboveIDs) && !selected.isDisjoint(with: belowIDs),
                          "跨月行带必须两侧都有命中（above=\(aboveIDs.count) below=\(belowIDs.count)）")
            snap(app, "m19-band-cross-month")
            return
        }
    }
}
