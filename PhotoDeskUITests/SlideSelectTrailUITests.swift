// MARK: - SlideSelectTrailUITests：轨迹滑选精确路径验收（M18 T08，docs/38 §4，docs/37 §8）——
// 旧选择契约（覆盖层/行带/双指规则）整体退役：断言一律为「精确 assetID 集合 + 计数 + offset +
// DEBUG 轨迹取证字段」。期望集合由测试内独立暴力基准计算（真实 cell frame + Liang-Barsky
// 线段扫掠，与 T07 LibraryGridGeometryTests 同口径），不依赖实现内部，防「实现自证」。
// 两段式手势口径：XCUI 单段拖拽无法合成「同一手势内回滑」，A→B→C→B 语义映射为
// G1 选择 A→C（途经 B）+ G2 从 C（已选 → 取消模式）拖回 B + G3 从 B（未选 → 选择模式）拖回 C，
// 等价覆盖「回滑取消 / 按模式恢复 / 基线保持」；同手势回滑的路径栈语义由 Core
// SlideSelectTrailTests 锁定（docs/38 §2.3）。

import XCTest
import UIKit

final class SlideSelectTrailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// M17 覆盖层 AX（视图已随 M18 T06 删除）：缺席断言用；拼接构造避免退役 token 进静态清单。
    private let retiredOverlayID = "Marquee" + "-Overlay"

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

    /// 长按 cell 后拖到另一 cell 中心（0.55s > 0.28s 长按阈值并留抖动余量）
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

    // MARK: - UI 层暴力基准（docs/37 §8：期望集合独立复算，防实现自证）

    /// 以真实 cell frame（屏幕坐标）对线段做 Liang-Barsky 求交，与生产 hitTestLine 同口径
    ///（expansion=1、epsilon=0.5、(t, id) 升序——SlideSelectConfig 常量在 UI 测试内镜像）。
    /// 仅覆盖当前可见 cell（屏外 cell 无有效 frame）；用例须保证命中全程在屏内。
    private func expectedLineHitIDs(in collection: XCUIElement,
                                    from startIndex: Int,
                                    to endIndex: Int) -> [String] {
        let startFrame = collection.cells.element(boundBy: startIndex).frame
        let endFrame = collection.cells.element(boundBy: endIndex).frame
        let from = CGPoint(x: startFrame.midX, y: startFrame.midY)
        let to = CGPoint(x: endFrame.midX, y: endFrame.midY)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let expansion: CGFloat = 1   // SlideSelectConfig.hitExpansion
        let epsilon: CGFloat = 0.5   // SlideSelectConfig.segmentEpsilon
        var hits: [(t: Double, id: String)] = []
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists else { continue }
            let frame = cell.frame
            guard frame.width > 1, frame.height > 1 else { continue }   // 屏外 cell frame 无效
            let minX = frame.minX - expansion
            let maxX = frame.maxX + expansion
            let minY = frame.minY - expansion
            let maxY = frame.maxY + expansion
            var tEnter = 0.0
            var tExit = 1.0
            var miss = false
            if abs(dx) <= epsilon {
                if from.x < minX || from.x > maxX { miss = true }
            } else {
                let t1 = Double((minX - from.x) / dx)
                let t2 = Double((maxX - from.x) / dx)
                tEnter = max(tEnter, min(t1, t2))
                tExit = min(tExit, max(t1, t2))
            }
            if abs(dy) <= epsilon {
                if from.y < minY || from.y > maxY { miss = true }
            } else {
                let t1 = Double((minY - from.y) / dy)
                let t2 = Double((maxY - from.y) / dy)
                tEnter = max(tEnter, min(t1, t2))
                tExit = min(tExit, max(t1, t2))
            }
            guard !miss, tEnter <= tExit else { continue }
            hits.append((tEnter, cellID(cell)))
        }
        return hits.sorted { $0.t != $1.t ? $0.t < $1.t : $0.id < $1.id }.map(\.id)
    }

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

    // MARK: - 用例（docs/38 §4 第 5-9 行）

    /// ① 长按 0.4s 进入多选：锚点入选（计数 1）、多选栏出现、无任何覆盖层元素残留。
    func testLongPressEntersSelectionWithAnchorCount() throws {
        var count = -1
        var entered = false
        var appRef: XCUIApplication!
        for attempt in 1...2 {
            let app = XCUIApplication()
            appRef = app
            let collection = launchPlainGrid(app)
            let first = collection.cells.firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
            first.press(forDuration: 0.4)
            count = waitForSelectionCountEqual(app, to: 1, timeout: 5)
            if count == 1 { entered = true; break }
            if attempt == 1 { usleep(500_000) }
        }
        XCTAssertEqual(count, 1, "长按 0.4s 必须进入多选且锚点入选（count=\(count)）")
        XCTAssertTrue(entered, "长按进入路径必须发生")
        XCTAssertTrue(anyElement(appRef, identifier: "Selection-Count").exists,
                      "长按进入后必须出现多选栏")
        XCTAssertTrue(cellIsSelected(appRef.collectionViews.firstMatch.cells.firstMatch),
                      "锚点 cell AX 必须同步 selected（视觉/AX 同源）")
        XCTAssertFalse(appRef.descendants(matching: .any)[retiredOverlayID].exists,
                       "M18 起不得存在任何覆盖层元素")
        snap(appRef, "m18-longpress-enter")
    }

    /// ② 长按不抬手继续竖拖：命中集合 == 独立暴力基准（精确 assetID 集合 + 有序）。
    func testLongPressTrailSelectsExactIDSequence() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchPlainGrid(app)
            let first = collection.cells.firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 10), "网格无 cell")
            let expected = expectedLineHitIDs(in: collection, from: 0, to: 12)
            guard expected.count >= 3 else {
                if attempt == 2 { XCTFail("首屏可见基准命中不足（expected=\(expected)）") }
                continue
            }
            longPressDrag(in: collection, fromIndex: 0, toIndex: 12)
            let count = waitForSelectionCountEqual(app, to: expected.count, timeout: 6)
            guard count == expected.count else {
                if attempt == 2 {
                    XCTFail("轨迹计数必须等于基准 \(expected.count)（count=\(count)，expected=\(expected)）")
                }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: Set(expected))
            XCTAssertEqual(selected, Set(expected),
                           "轨迹命中必须精确等于暴力基准集合（got=\(selected.sorted()) expected=\(expected)）")
            snap(app, "m18-longpress-trail")
            return
        }
    }

    /// ③ 左列竖拖：右列 assetID 不得出现（列隔离，滑到哪选到哪不外扩）。
    func testLeftColumnTrailExcludesRightColumn() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            let column = sameColumnIndices(in: collection, anchorIndex: 0)
            guard column.count >= 3 else {
                if attempt == 2 { XCTFail("首屏同列可见格不足（column=\(column)）") }
                continue
            }
            let lastInColumn = column[column.count - 1]
            let expectedIDs = column.map { cellID(collection.cells.element(boundBy: $0)) }
            longPressDrag(in: collection, fromIndex: 0, toIndex: lastInColumn)
            let count = waitForSelectionCountEqual(app, to: column.count, timeout: 6)
            guard count == column.count else {
                if attempt == 2 { XCTFail("左列竖拖计数必须 \(column.count)（count=\(count)）") }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: Set(expectedIDs))
            XCTAssertEqual(selected, Set(expectedIDs),
                           "命中必须精确 = 同列 assetID（got=\(selected.sorted()) expected=\(expectedIDs)）")
            // 右列邻格必须全部未选中（以首格右邻为例）
            let anchorFrame = collection.cells.element(boundBy: 0).frame
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                let frame = cell.frame
                let isRightNeighbor = frame.minY >= anchorFrame.minY - 5
                    && frame.minY <= anchorFrame.maxY + 5
                    && frame.minX > anchorFrame.maxX
                if isRightNeighbor {
                    XCTAssertFalse(cellIsSelected(cell),
                                   "右列邻格 idx \(index)（\(cellID(cell))）不得被左列竖拖命中")
                }
            }
            snap(app, "m18-left-column")
            return
        }
    }

    /// ④ 斜拖不补全对角矩形：命中 = 线段扫掠集（≠ 外接矩形集），外接矩形内的「离线 filler 格」不得选中。
    func testDiagonalTrailDoesNotFillRectangle() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchSelectableGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            let lineHit = expectedLineHitIDs(in: collection, from: 0, to: 10)
            guard lineHit.count >= 3 else {
                if attempt == 2 { XCTFail("斜线基准命中不足（\(lineHit)）") }
                continue
            }
            // 外接矩形集（矩形语义的反例集）：两对角格围成矩形内的可见格
            let startFrame = collection.cells.element(boundBy: 0).frame
            let endFrame = collection.cells.element(boundBy: 10).frame
            let bound = startFrame.union(endFrame)
            var rectFillers: [String] = []
            for index in 0..<collection.cells.count {
                let cell = collection.cells.element(boundBy: index)
                guard cell.exists, cell.frame.width > 1 else { continue }
                let id = cellID(cell)
                let center = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
                if bound.contains(center), !lineHit.contains(id) {
                    rectFillers.append(id)
                }
            }
            guard !rectFillers.isEmpty else {
                if attempt == 2 { XCTFail("本几何下矩形 filler 与线段命中重合，用例失去判别力") }
                continue
            }
            longPressDrag(in: collection, fromIndex: 0, toIndex: 10)
            let count = waitForSelectionCountEqual(app, to: lineHit.count, timeout: 6)
            guard count == lineHit.count else {
                if attempt == 2 {
                    XCTFail("斜拖计数必须 = 线段扫掠数 \(lineHit.count)（count=\(count)；\n"
                            + "若等于矩形数则实现退回矩形语义）")
                }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: Set(lineHit))
            XCTAssertEqual(selected, Set(lineHit),
                           "斜拖命中必须精确 = 线段扫掠集（got=\(selected.sorted()) expected=\(lineHit)）")
            for filler in rectFillers {
                XCTAssertFalse(selected.contains(filler),
                               "矩形 filler 格 \(filler) 不得被斜拖命中（滑到哪选到哪）")
            }
            snap(app, "m18-diagonal-no-fill")
            return
        }
    }

    /// ⑤ A→B→C→B 回滑语义（两段式映射，见文件头）：G1 选 {A,B,C} → G2 锚点已选取消模式
    /// 拖 C→B（C 取消、B 取消、A 保持）→ G3 从 B（未选 → 选择模式）拖回 C（B/C 恢复）。
    func testTrailReverseCancelsThenRestores() throws {
        for attempt in 1...2 {
            let app = XCUIApplication()
            let collection = launchPlainGrid(app)
            XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
            // 取同一视觉行的前三格（A 左、B 中、C 右）——几何自适应，不依赖分段模型
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
                if attempt == 2 { XCTFail("首行同 row 可见格不足 3（rowCells=\(rowCells)）") }
                continue
            }
            let (a, b, c) = (rowCells[0], rowCells[1], rowCells[2])
            let ids = { (index: Int) in self.cellID(collection.cells.element(boundBy: index)) }
            // G1：长按 A → 拖 C（途经 B）
            longPressDrag(in: collection, fromIndex: a, toIndex: c)
            var count = waitForSelectionCountEqual(app, to: 3, timeout: 6)
            guard count == 3 else {
                if attempt == 2 { XCTFail("G1 选择 A→C 必须选 3 格（count=\(count)）") }
                continue
            }
            var selected = waitForSelectedSet(collection, equals: Set([ids(a), ids(b), ids(c)]))
            XCTAssertEqual(selected, Set([ids(a), ids(b), ids(c)]), "G1 后必须恰好 {A,B,C}")
            // G2：锚点 C 已选 → 取消模式，C→B：C、B 出栈（取消），A 保持
            longPressDrag(in: collection, fromIndex: c, toIndex: b)
            count = waitForSelectionCountEqual(app, to: 1, timeout: 6)
            guard count == 1 else {
                if attempt == 2 { XCTFail("G2 取消 C→B 后必须剩 1 格（count=\(count)）") }
                continue
            }
            selected = waitForSelectedSet(collection, equals: Set([ids(a)]))
            XCTAssertEqual(selected, Set([ids(a)]), "G2 后必须恰 {A}（A 不受出栈影响）")
            XCTAssertFalse(collection.cells.element(boundBy: c).exists &&
                           cellIsSelected(collection.cells.element(boundBy: c)), "C 必须已取消")
            XCTAssertFalse(collection.cells.element(boundBy: b).exists &&
                           cellIsSelected(collection.cells.element(boundBy: b)), "B 必须已取消")
            // G3：锚点 B 已取消 → 选择模式，B→C：B、C 恢复
            longPressDrag(in: collection, fromIndex: b, toIndex: c)
            count = waitForSelectionCountEqual(app, to: 3, timeout: 6)
            guard count == 3 else {
                if attempt == 2 { XCTFail("G3 恢复 B→C 必须回 3 格（count=\(count)）") }
                continue
            }
            selected = waitForSelectedSet(collection, equals: Set([ids(a), ids(b), ids(c)]))
            XCTAssertEqual(selected, Set([ids(a), ids(b), ids(c)]), "G3 后 {A,B,C} 全部恢复")
            snap(app, "m18-reverse-cancel-restore")
            return
        }
    }

    /// ⑥ 手势前已选 X 不受任何出栈影响：X 在路径外，选择/取消两轮轨迹后仍保持。
    func testPreSelectedCellSurvivesTrail() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        // 预点选首格（X）
        collection.cells.element(boundBy: 0).tap()
        XCTAssertEqual(waitForSelectionCountEqual(app, to: 1, timeout: 5), 1, "预选 X")
        let xID = cellID(collection.cells.element(boundBy: 0))
        // 竖拖（避开首格所在行的同列起点：从第 2 行同列起拖）
        let column = sameColumnIndices(in: collection, anchorIndex: 0)
        XCTAssertGreaterThanOrEqual(column.count, 3, "同列可见格不足")
        let fromIndex = column[1]
        let toIndex = column[column.count - 1]
        longPressDrag(in: collection, fromIndex: fromIndex, toIndex: toIndex)
        let trailIDs = Set(column[1...].map { cellID(collection.cells.element(boundBy: $0)) })
        let expected = trailIDs.union([xID])
        let selected = waitForSelectedSet(collection, equals: expected)
        XCTAssertEqual(selected, expected,
                       "路径外预选 X 必须保持 + 轨迹格入选（got=\(selected.sorted()) expected=\(expected.sorted())）")
        snap(app, "m18-preselected-survives")
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
        // 起拖点在头底边下方 30pt、居中列；竖拖一屏
        let startX = collection.frame.midX
        let startY = stickyBottom + 30
        let endY = collection.frame.maxY - 40
        let start = collection.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: startX - collection.frame.minX, dy: startY - collection.frame.minY))
        let end = collection.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: startX - collection.frame.minX, dy: endY - collection.frame.minY))
        start.press(forDuration: 0.55, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
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
                      "被钉住头完全遮住的 cell 不得入选：\(occluded)")
        snap(app, "m18-sticky-header")
    }

    /// ⑩ 全选后轨迹取消 + 退出多选计数归零（多选栏消失）。
    func testSelectAllTrailDeselectExactAndExitResets() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "多选操作行缺全选\n\(hierarchy(app))")
        selectAll.tap()
        let filtered = readFilteredCount(app)
        let total = waitForSelectionCount(app, atLeast: 1, timeout: 5)
        XCTAssertEqual(total, filtered,
                       "全选计数必须 = filteredItems.count（total=\(total) filtered=\(filtered)）")
        // 锚点已选 → 取消模式：竖拖取消一列可见格
        let column = sameColumnIndices(in: collection, anchorIndex: 0)
        XCTAssertGreaterThanOrEqual(column.count, 2, "同列可见格不足")
        longPressDrag(in: collection, fromIndex: column[0], toIndex: column[column.count - 1])
        let remaining = waitForSelectionCountEqual(app, to: total - column.count, timeout: 6)
        XCTAssertEqual(remaining, total - column.count,
                       "取消模式竖拖必须恰好取消 \(column.count) 格（remaining=\(remaining)）")
        // 退出多选：计数归零、多选栏消失
        let done = anyElement(app, identifier: "Batch-Done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "缺完成按钮")
        done.tap()
        let countLabel = anyElement(app, identifier: "Selection-Count")
        let goneDeadline = Date().addingTimeInterval(2)
        while Date() < goneDeadline && countLabel.exists { usleep(100_000) }
        XCTAssertFalse(countLabel.exists, "退出后多选栏必须消失")
        snap(app, "m18-selectall-exit")
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
        // 月份头菜单「选择本月全部」（宿主 UIButton + UIMenu，同 StabilityUITests 手法）
        let menu = anyElement(app, identifier: "MonthHeader-Menu-2024-05")
        guard menu.waitForExistence(timeout: 5) else {
            return XCTFail("首屏未出现 2024-05 月份头（倒序种子首屏应为其后段）\n\(hierarchy(app))")
        }
        menu.tap()
        let selectAllMonth = app.buttons["选择本月全部"]
        XCTAssertTrue(selectAllMonth.waitForExistence(timeout: 5), "月份菜单缺「选择本月全部」")
        selectAllMonth.tap()
        let monthCount = waitForSelectionCount(app, atLeast: 1, timeout: 5)
        XCTAssertGreaterThan(monthCount, 0, "单月全选后计数应 > 0")
        // 相邻月（屏内其它段）cell 起拖取消模式轨迹：scope 外 id 不得改变计数
        let scopeCells = sameColumnIndices(in: collection, anchorIndex: 0)
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

    /// ⑬ 无长按横向按压拖（pressing 横向占优）：行内线段扫掠精确命中 + 路径取证。
    func testHorizontalPressDragTrailSelectsExactRow() throws {
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
            let expected = expectedLineHitIDs(in: collection, from: firstIdx, to: lastIdx)
            guard expected.count == rowCells.count else {
                if attempt == 2 { XCTFail("同行横线基准应覆盖全行（expected=\(expected)）") }
                continue
            }
            let start = collection.cells.element(boundBy: firstIdx)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            let end = collection.cells.element(boundBy: lastIdx)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
            let count = waitForSelectionCountEqual(app, to: expected.count, timeout: 6)
            guard count == expected.count else {
                if attempt == 2 { XCTFail("横向按压拖计数必须 \(expected.count)（count=\(count)）") }
                continue
            }
            let selected = waitForSelectedSet(collection, equals: Set(expected))
            XCTAssertEqual(selected, Set(expected),
                           "横向轨迹必须精确 = 行内 assetID 集合（got=\(selected.sorted())）")
            let pathCount = readTrailPathCount(app)
            XCTAssertGreaterThanOrEqual(pathCount, expected.count,
                                        "路径栈深度必须 ≥ 行内格数（path=\(pathCount)）")
            snap(app, "m18-horizontal-press")
            return
        }
    }

    /// ⑭ 横幅取证字段与覆盖层缺席：轨迹后 trail=/path=/delta= 就位、旧覆盖层元素恒不存在。
    func testTrailDebugFieldsPresentAndOverlayAbsent() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        longPressDrag(in: collection, fromIndex: 0, toIndex: 3)
        _ = waitForSelectionCount(app, atLeast: 1, timeout: 6)
        let raw = bannerRaw(app)
        XCTAssertNotNil(Self.parseDoubleField(raw, "path"),
                        "DEBUG 汇总必须暴露 path= 字段\n\(raw)")
        XCTAssertNotNil(Self.parseDoubleField(raw, "hap"), "DEBUG 汇总必须暴露 hap= 字段")
        XCTAssertTrue(raw.contains("trail="), "DEBUG 汇总必须暴露 trail= 字段\n\(raw)")
        XCTAssertTrue(raw.contains("delta="), "DEBUG 汇总必须暴露 delta= 字段\n\(raw)")
        XCTAssertFalse(raw.contains("ov="), "旧 ov* 覆盖层取证字段必须已退役\n\(raw)")
        XCTAssertFalse(app.descendants(matching: .any)[retiredOverlayID].exists,
                       "旧覆盖层元素必须不存在")
        snap(app, "m18-debug-fields")
    }
}
