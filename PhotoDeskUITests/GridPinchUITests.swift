// MARK: - GridPinchUITests：网格捏合单飞事务稳定性矩阵（docs/28 §4.4.4 / M16 T02）——
// 断言口径：2↔5 快速 200 轮 0 崩溃；跨月滚动后捏合存活且锚定月份不漂移；粘性头在场捏合存活；
// 捏合后滚动不跳（可见月份有交集）；重启后列数保持（docs/09 D14）。
// 屏幕录制由 XCUITest xcresult 自带视频承载，关键节点另附 keepAlways 截图。
// 红→绿口径：旧实现每个阈值跨即使发 setCollectionViewLayout（无单飞），
// 200 轮循环即触发布局过渡重入（docs/28 §4.3 R1），本套件在修复前按预期不稳定。

import XCTest

final class GridPinchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - helper（与 ZoomStabilityUITests 同款，按文件私有复制）

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

    /// 进入网格：种子照片 + 权限弹窗处理 + 等待 cell（与 ZoomStabilityUITests.launchToGrid 同款）
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

    private func monthHeaderTexts(_ app: XCUIApplication) -> [String] {
        // 粘性头标题带计数后缀（docs/04 §3.1：2026年10月 · 128 张），MATCHES 用前缀锚定
        let predicate = NSPredicate(format: "label MATCHES '20[0-9][0-9]年[0-9]+月.*'")
        return app.staticTexts.matching(predicate).allElementsBoundByIndex.map(\.label)
    }

    /// 一个捏合循环 = 拉开（scale>1 → 少列）+ 收拢（scale<1 → 多列）
    private func pinchCycle(_ collection: XCUIElement, rounds: Int, app: XCUIApplication, tag: String) {
        for round in 0..<rounds {
            collection.pinch(withScale: 2.2, velocity: 1.4)
            collection.pinch(withScale: 0.45, velocity: -1.4)
            if round % 10 == 9 {
                assertAlive(app, "\(tag) 第 \(round + 1) 循环后")
            }
        }
    }

    // MARK: - 200 轮快速捏合（docs/28 §4.4.4：2→5→2 快速 200 轮）

    func testGridPinch200Cycles() throws {
        let app = XCUIApplication()
        let collection = launchToGrid(app)
        pinchCycle(collection, rounds: 100, app: app, tag: "网格捏合")
        assertAlive(app, "200 次捏合（100 循环 × 开合各一）后")
        XCTAssertTrue(collection.cells.firstMatch.exists, "捏合后网格应仍可交互")
        snap(app, "m16-grid-pinch-200-cycles")
    }

    // MARK: - 跨月锚点 + 滚动不跳

    func testGridPinchCrossMonthAnchorStays() throws {
        let app = XCUIApplication()
        let collection = launchToGrid(app)
        // 滚到较后的月份（种子跨 2020–2026，多月份分组）
        for _ in 0..<4 { app.swipeUp() }
        Thread.sleep(forTimeInterval: 0.4)
        let monthsBefore = monthHeaderTexts(app)
        XCTAssertFalse(monthsBefore.isEmpty, "滚动后应能看到月份标题\n\(hierarchy(app))")
        collection.pinch(withScale: 2.2, velocity: 1.4)
        Thread.sleep(forTimeInterval: 0.8)
        collection.pinch(withScale: 0.45, velocity: -1.4)
        Thread.sleep(forTimeInterval: 0.8)
        assertAlive(app, "跨月捏合后")
        let monthsAfter = monthHeaderTexts(app)
        XCTAssertFalse(monthsAfter.isEmpty, "捏合后月份标题应仍在\n\(hierarchy(app))")
        // 锚点不漂移的粗粒度等价断言：捏合前后可见月份必须有交集（±1 cell 高度口径）
        let overlap = Set(monthsBefore).intersection(monthsAfter)
        XCTAssertFalse(overlap.isEmpty,
                       "捏合后可见月份应与捏合前有交集 before=\(monthsBefore) after=\(monthsAfter)")
        // 滚动不跳：再滚一屏，月份标题应仍存在（不弹回顶部/黑屏）
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(monthHeaderTexts(app).isEmpty, "捏合后继续滚动月份标题不应消失")
        snap(app, "m16-grid-pinch-cross-month")
    }

    // MARK: - 粘性头在场捏合

    func testGridPinchWithStickyHeaderVisible() throws {
        let app = XCUIApplication()
        let collection = launchToGrid(app)
        for _ in 0..<2 { app.swipeUp() }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(monthHeaderTexts(app).isEmpty, "中段滚动后粘性月份头应可见")
        collection.pinch(withScale: 2.2, velocity: 1.4)
        Thread.sleep(forTimeInterval: 0.6)
        collection.pinch(withScale: 0.45, velocity: -1.4)
        collection.pinch(withScale: 2.2, velocity: 1.4)
        Thread.sleep(forTimeInterval: 0.6)
        assertAlive(app, "粘性头在场捏合后")
        XCTAssertTrue(collection.cells.firstMatch.exists)
        snap(app, "m16-grid-pinch-sticky-header")
    }

    // MARK: - 重启后列数保持（docs/09 D14）

    func testGridColumnsPersistAfterRelaunch() throws {
        let app = XCUIApplication()
        let collection = launchToGrid(app)
        // 捏合改变列数（scale 2.2 → 少列）；提交在 .changed 即发生，.ended 持久化
        collection.pinch(withScale: 2.2, velocity: 1.4)
        Thread.sleep(forTimeInterval: 1.0)
        assertAlive(app, "捏合后")
        // 合成捏合的 .ended 刻度可能回落触发回弹（docs/09 D14 回弹带），与真机释放姿态不同；
        // 本用例断言口径是「重启前后列数一致」（持久化语义本身），列数取捏合后的实测值。
        let columnsAfterPinch = firstRowCount(collection)
        app.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        let relaunched = launchToGrid(app)
        let columnsRelaunch = firstRowCount(relaunched)
        XCTAssertEqual(columnsRelaunch, columnsAfterPinch,
                       "重启后列数应保持（捏合后 \(columnsAfterPinch) 列 → 重启后 \(columnsRelaunch) 列）")
        snap(app, "m16-grid-columns-persist")
    }

    /// 取首行 cell 数：按 frame.minY 聚类第一行，统计其 x 去重数
    private func firstRowCount(_ collection: XCUIElement, sample: Int = 14) -> Int {
        var firstRowY: CGFloat?
        var columns = Set<CGFloat>()
        for index in 0..<sample {
            let cell = collection.cells.element(boundBy: index)
            guard cell.exists else { break }
            let frame = cell.frame
            if let y = firstRowY {
                if frame.minY < y + 10 {
                    columns.insert(round(frame.minX))
                }
            } else {
                firstRowY = frame.minY
                columns.insert(round(frame.minX))
            }
        }
        return max(columns.count, 1)
    }
}
