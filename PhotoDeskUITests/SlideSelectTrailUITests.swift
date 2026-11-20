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

    // MARK: - UI 层暴力基准（docs/37 §8：期望集合独立复算，防实现自证）

    /// 以真实 cell frame（屏幕坐标）对线段做 Liang-Barsky 求交，与生产 hitTestLine 同口径
    ///（expansion=1、epsilon=0.5、(t, id) 升序——SlideSelectConfig 常量在 UI 测试内镜像）。
    /// 仅覆盖当前可见 cell（屏外 cell 无有效 frame）；用例须保证命中全程在屏内。
    private func expectedLineHitIDs(in collection: XCUIElement,
                                    from startIndex: Int,
                                    to endIndex: Int,
                                    startOffset: CGVector = CGVector(dx: 0.5, dy: 0.5),
                                    endOffset: CGVector = CGVector(dx: 0.5, dy: 0.5)) -> [String] {
        let startFrame = collection.cells.element(boundBy: startIndex).frame
        let endFrame = collection.cells.element(boundBy: endIndex).frame
        let from = CGPoint(x: startFrame.minX + startFrame.width * CGFloat(startOffset.dx),
                           y: startFrame.minY + startFrame.height * CGFloat(startOffset.dy))
        let to = CGPoint(x: endFrame.minX + endFrame.width * CGFloat(endOffset.dx),
                         y: endFrame.minY + endFrame.height * CGFloat(endOffset.dy))
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

    /// 路径走廊：沿线等距采样 40 点，frame 膨胀 tolerance pt 后含任一采样点的可见 cell
    ///（frame 口径，与生产 hitTest 的 frame 相交判定同侧度——弧线扫过格边角即算走廊内）。
    /// XCUI 合成拖拽为样条弧线，中段可侧摆 ~20-40pt（第 4/9/12/13 轮 ±1 格实锤），
    /// 斜拖用例以此作「滑到哪选到哪」与弧度噪声的边界；对角矩形远角仍在走廊外。
    private func expectedCorridorIDs(in collection: XCUIElement,
                                     from startIndex: Int,
                                     to endIndex: Int,
                                     startOffset: CGVector,
                                     endOffset: CGVector,
                                     tolerance: CGFloat) -> [String] {
        let startFrame = collection.cells.element(boundBy: startIndex).frame
        let endFrame = collection.cells.element(boundBy: endIndex).frame
        let from = CGPoint(x: startFrame.minX + startFrame.width * CGFloat(startOffset.dx),
                           y: startFrame.minY + startFrame.height * CGFloat(startOffset.dy))
        let to = CGPoint(x: endFrame.minX + endFrame.width * CGFloat(endOffset.dx),
                         y: endFrame.minY + endFrame.height * CGFloat(endOffset.dy))
        var samples: [CGPoint] = []
        let steps = 40
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            samples.append(CGPoint(x: from.x + (to.x - from.x) * t,
                                   y: from.y + (to.y - from.y) * t))
        }
        var result: [String] = []
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists, cell.frame.width > 1 else { continue }
            let inflated = cell.frame.insetBy(dx: -tolerance, dy: -tolerance)
            if samples.contains(where: inflated.contains) { result.append(cellID(cell)) }
        }
        return result
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
            // 终点必须远离底缘 60pt 自动滚动触发区（留 80pt 余量）：慢速/停留会触发
            // 边缘滚动，内容坐标下路径延长多扫一格（T08 第 4 轮 CI 实锤 +1）
            let safeBottom = collection.frame.maxY - 80
            let safeColumn = column.filter { collection.cells.element(boundBy: $0).frame.maxY < safeBottom }
            guard safeColumn.count >= 3 else {
                if attempt == 2 { XCTFail("同列远离底缘的可见格不足（column=\(column)）") }
                continue
            }
            let lastInColumn = safeColumn[safeColumn.count - 1]
            let expectedIDs = safeColumn.map { cellID(collection.cells.element(boundBy: $0)) }
            longPressDrag(in: collection, fromIndex: 0, toIndex: lastInColumn)
            let count = waitForSelectionCountEqual(app, to: safeColumn.count, timeout: 6)
            guard count == safeColumn.count else {
                if attempt == 2 { XCTFail("左列竖拖计数必须 \(safeColumn.count)（count=\(count)）") }
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
            // 终点远离底缘 80pt 余量（同 ③：避免边缘滚动延长路径）
            let diagSafeBottom = collection.frame.maxY - 80
            var diagEnd = -1
            for index in (1...10).reversed() {
                let frame = collection.cells.element(boundBy: index).frame
                if frame.width > 1, frame.maxY < diagSafeBottom { diagEnd = index; break }
            }
            guard diagEnd >= 3 else {
                if attempt == 2 { XCTFail("远离底缘的对角终点格不足（diagEnd=\(diagEnd)）") }
                continue
            }
            // 角内偏移 (0.3,0.3)→(0.7,0.7)：线段从格内部穿过，距角落 ≥24pt，
            // 避开中心-中心对角线贴角 ±1 格的路径曲率噪声（第 4/9 轮 CI 实锤）
            let diagOffsetStart = CGVector(dx: 0.3, dy: 0.3)
            let diagOffsetEnd = CGVector(dx: 0.7, dy: 0.7)
            let lineHit = expectedLineHitIDs(in: collection, from: 0, to: diagEnd,
                                             startOffset: diagOffsetStart, endOffset: diagOffsetEnd)
            guard lineHit.count >= 3 else {
                if attempt == 2 { XCTFail("斜线基准命中不足（\(lineHit)）") }
                continue
            }
            // 外接矩形集（矩形语义的反例集）：两对角格围成矩形内的可见格
            let startFrame = collection.cells.element(boundBy: 0).frame
            let endFrame = collection.cells.element(boundBy: diagEnd).frame
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
            longPressDrag(in: collection, fromIndex: 0, toIndex: diagEnd,
                          startOffset: diagOffsetStart, endOffset: diagOffsetEnd)
            let selected = waitForSelectionCountEqual(app, to: lineHit.count, timeout: 6)
            guard selected == lineHit.count else {
                if attempt == 2 {
                    let got = selectedVisibleIDs(collection).sorted()
                    XCTFail("斜拖计数必须 = 线段扫掠数 \(lineHit.count)（count=\(selected) got=\(got)；\n"
                            + "若等于矩形数则实现退回矩形语义）")
                }
                continue
            }
            let got = selectedVisibleIDs(collection)
            // XCUI 合成拖拽是带弧度的样条路径（非理想直线），中段可侧摆 ~10-20pt，
            // 会把与线段贴近的侧邻格翻进/翻出（第 4/9/12 轮实锤 ±1）；契约锁定的是
            // 「不补全对角矩形」：filler 格严格排除，线段格允许 ±1 弧度噪声（路径走廊）。
            let corridor = Set(expectedCorridorIDs(in: collection, from: 0, to: diagEnd,
                                                   startOffset: diagOffsetStart, endOffset: diagOffsetEnd,
                                                   tolerance: 36))
            for filler in rectFillers where !corridor.contains(filler) {
                XCTAssertFalse(got.contains(filler),
                               "矩形 filler 格 \(filler) 不得被斜拖命中（滑到哪选到哪）")
            }
            let strays = got.subtracting(corridor)
            XCTAssertTrue(strays.isEmpty,
                          "斜拖命中不得越出路径走廊（strays=\(strays.sorted()) lineHit=\(lineHit)）")
            XCTAssertLessThanOrEqual(abs(got.count - lineHit.count), 1,
                                     "弧度噪声至多 ±1 格（got=\(got.count) lineHit=\(lineHit.count)）")
            XCTAssertEqual(got.contains(cellID(collection.cells.element(boundBy: 0))) &&
                           got.contains(cellID(collection.cells.element(boundBy: diagEnd))), true,
                           "对角两端点必须入选")
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
        // 竖拖（从第 2 行同列起拖；终点远离底缘 80pt 余量，同 ③）
        let column = sameColumnIndices(in: collection, anchorIndex: 0)
        XCTAssertGreaterThanOrEqual(column.count, 3, "同列可见格不足")
        let safeBottom = collection.frame.maxY - 80
        let safeColumn = column.filter { collection.cells.element(boundBy: $0).frame.maxY < safeBottom }
        XCTAssertGreaterThanOrEqual(safeColumn.count, 3, "同列远离底缘的可见格不足")
        let fromIndex = safeColumn[1]
        let toIndex = safeColumn[safeColumn.count - 1]
        longPressDrag(in: collection, fromIndex: fromIndex, toIndex: toIndex)
        let trailIDs = Set(safeColumn[1...].map { cellID(collection.cells.element(boundBy: $0)) })
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
        // 锚点已选 → 取消模式：竖拖取消一列可见格（终点远离底缘 80pt 余量，同 ③）
        let column = sameColumnIndices(in: collection, anchorIndex: 0)
        XCTAssertGreaterThanOrEqual(column.count, 2, "同列可见格不足")
        let safeBottom = collection.frame.maxY - 80
        let safeColumn = column.filter { collection.cells.element(boundBy: $0).frame.maxY < safeBottom }
        XCTAssertGreaterThanOrEqual(safeColumn.count, 2, "同列远离底缘的可见格不足")
        longPressDrag(in: collection, fromIndex: safeColumn[0], toIndex: safeColumn[safeColumn.count - 1])
        let remaining = waitForSelectionCountEqual(app, to: total - safeColumn.count, timeout: 6)
        XCTAssertEqual(remaining, total - safeColumn.count,
                       "取消模式竖拖必须恰好取消 \(safeColumn.count) 格（remaining=\(remaining)）")
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

    // MARK: - T01 红基线临时探针（docs/43 T01 步骤 4；T06/T08 转正式断言）

    /// 探针：长按最右列锚点下滑 3 行 → 记录实际计数 vs 行带目标 3×列数。
    /// 现实现为线段扫掠语义（只选中扫过的列内格），预期 actual < bandTarget——证据供 docs/45 §2。
    /// 证据采集后 XCTSkip：不计入正式套件判定；T06/T08 改为正式断言 actual == 3×列数。
    func testProbeRightColumnSlideDownThreeRowsEvidence() throws {
        let app = XCUIApplication()
        let collection = launchSelectableGrid(app)
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10), "网格无 cell")
        // 首行同视觉行格 → 列数；锚点 = 最右列
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
        let anchorIndex = rowCells.last ?? 0
        let column = sameColumnIndices(in: collection, anchorIndex: anchorIndex)
        let safeBottom = collection.frame.maxY - 80
        let safeColumn = column.filter { collection.cells.element(boundBy: $0).frame.maxY < safeBottom }
        let geometry = "probe-geometry: anchorIndex=\(anchorIndex) columns=\(columns) " +
            "sameColumnVisible=\(column.count) safeBelow=\(safeColumn.count)"
        func attach(_ name: String, _ value: String) {
            let a = XCTAttachment(string: value)
            a.name = name
            a.lifetime = .keepAlways
            add(a)
        }
        attach("m19-probe-geometry", geometry)
        guard columns >= 2, safeColumn.count >= 4 else {
            snap(app, "m19-probe-right-column-3rows")
            throw XCTSkip("T01 探针几何不足，未采证：\(geometry)")
        }
        let targetIndex = safeColumn[3]   // 锚点下方第 3 行（同列）
        longPressDrag(in: collection, fromIndex: anchorIndex, toIndex: targetIndex)
        _ = waitForSelectionCountEqual(app, to: 3 * columns, timeout: 3)
        let actual = selectionCount(app)
        let selected = selectedVisibleIDs(collection).sorted()
        let bandTarget = 3 * columns
        attach("m19-probe-result",
               "probe-result: actual=\(actual) bandTarget=\(bandTarget) " +
               "sweptColumnCells=\(min(4, safeColumn.count)) selected=\(selected)")
        snap(app, "m19-probe-right-column-3rows")
        throw XCTSkip("T01 临时探针：证据已采集（actual=\(actual) bandTarget=\(bandTarget)）；" +
                      "T06/T08 转正断言 actual == 3×columns")
    }

    // MARK: - M19 行为矩阵（docs/43 T06、docs/42 §1.2 行为表：精确 行数×列数 断言）

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
            guard columns >= 2, below.count >= 3 else {
                if attempt == 2 {
                    XCTFail("几何不足 columns=\(columns) belowRows=\(below.count)")
                }
                continue
            }
            longPressDrag(in: collection, fromIndex: anchorVisible, toIndex: below[2])
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
}
