// MARK: - PositionRestoreUITests：位置记忆 v5 验收（docs/25 §5.8 / M15 P0-2，≥6 条）——
// 核心口径：冷启动/杀进程重启后回到「同一 assetID 同一像素位置」±2pt（≤1 行容差废止）；
// 10 次循环冷启动 10/10；强制杀进程；后台/前台；旋转锚点保持；筛选切换不泄漏跨 scope 锚点。
// 取证入口：Library-DebugSummary 的 off / anchor / visualY（与生产同一保存/恢复路径）。

import XCTest

final class PositionRestoreUITests: XCTestCase {
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

    private func headerElements(_ app: XCUIApplication) -> XCUIElementQuery {
        app.collectionViews.firstMatch
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '月 ·'"))
    }

    private func topHeaderText(_ app: XCUIApplication) -> String {
        let headers = headerElements(app)
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

    /// 月份跳转启动（等价月份面板点卡片）；面板渲染验证轮 + 跳转轮分离（绿10 同款规避）
    private func launchWithMonthJump(_ app: XCUIApplication, sectionID: String, headerText: String) {
        app.launchArguments += ["-uiTestingOpenMonthJump"]
        _ = launchToGrid(app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        app.launchArguments += ["-uiTestingMonthJump", sectionID]
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, headerText, timeout: 15),
                      "月份跳转后顶部应为 \(headerText)（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        Thread.sleep(forTimeInterval: 1.2)
    }

    private static func parseDoubleField(_ label: String, _ key: String) -> Double {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)=(-?[0-9]+(?:\\.[0-9]+)?)", options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return -1 }
        return Double(label[range]) ?? -1
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

    /// Library-DebugSummary → (off, anchor, visualY)
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

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func swipeUpOnce(in collection: XCUIElement) {
        let start = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    // MARK: - 主验收：10 次冷启动同像素恢复

    /// docs/26 §6.6：循环 10 次——滚到新深度 → 记录 anchor + off → terminate → relaunch →
    /// 断言同 assetID 且 |off 差| ≤ 2pt（「≤1 行」容差废止）。
    func testColdLaunchRestoresSamePixelPosition10Times() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        // 后续冷启动验证纯位置恢复，摘掉跳转 flag（同一实例参数跨轮累积）
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        let collection = app.collectionViews.firstMatch

        for round in 0..<10 {
            if round > 0 {
                // 每轮向下滚动 1-2 屏产生新锚点（拖动结束即 saveNow 落盘）
                swipeUpOnce(in: collection)
                Thread.sleep(forTimeInterval: 0.6)
                if round % 2 == 0 {
                    swipeUpOnce(in: collection)
                    Thread.sleep(forTimeInterval: 0.6)
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
            guard let before = debugSnapshot(app) else {
                return XCTFail("轮 \(round + 1)：Library-DebugSummary 必须暴露 off/anchor/visualY")
            }
            app.terminate()
            _ = launchToGrid(app)
            Thread.sleep(forTimeInterval: 0.8)
            guard let after = debugSnapshot(app) else {
                return XCTFail("轮 \(round + 1)：重启后必须能读取位置快照")
            }
            XCTAssertEqual(after.anchor, before.anchor,
                           "轮 \(round + 1)：冷启动锚点 assetID 必须一致（before=\(before.anchor) after=\(after.anchor)）")
            XCTAssertLessThanOrEqual(abs(after.off - before.off), 2.0,
                                     "轮 \(round + 1)：冷启动像素 offset 差必须 ≤ 2pt（before=\(before.off) after=\(after.off)）")
            assertAlive(app, "轮 \(round + 1) 冷启动恢复后")
            if round == 9 {
                snap(app, "m15-position-10x")
            }
        }
    }

    /// 强杀进程（terminate 后立即重启，不做优雅保存）：最后一笔必须已在拖动结束时落盘
    func testForceKillRestores() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        let collection = app.collectionViews.firstMatch
        swipeUpOnce(in: collection)
        Thread.sleep(forTimeInterval: 0.8)
        guard let before = debugSnapshot(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off/anchor/visualY")
        }
        app.terminate()
        _ = launchToGrid(app)
        Thread.sleep(forTimeInterval: 0.8)
        guard let after = debugSnapshot(app) else {
            return XCTFail("重启后必须能读取位置快照")
        }
        XCTAssertEqual(after.anchor, before.anchor, "强杀后锚点必须一致")
        XCTAssertLessThanOrEqual(abs(after.off - before.off), 2.0,
                                 "强杀后像素 offset 差必须 ≤ 2pt（before=\(before.off) after=\(after.off)）")
        snap(app, "m15-position-force-kill")
    }

    /// 后台 → 前台：willResignActive saveNow + flush，回来不回顶不漂移
    func testBackgroundForegroundRestores() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        let collection = app.collectionViews.firstMatch
        swipeUpOnce(in: collection)
        Thread.sleep(forTimeInterval: 0.8)
        guard let before = debugSnapshot(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off/anchor/visualY")
        }
        XCUIDevice.shared.press(XCUIDevice.Button.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(collection.waitForExistence(timeout: 10), "回前台后网格必须就绪")
        Thread.sleep(forTimeInterval: 0.8)
        guard let after = debugSnapshot(app) else {
            return XCTFail("回前台后必须能读取位置快照")
        }
        XCTAssertEqual(after.anchor, before.anchor, "后台/前台往返锚点必须一致")
        XCTAssertLessThanOrEqual(abs(after.off - before.off), 2.0,
                                 "后台/前台往返 offset 差必须 ≤ 2pt")
        assertAlive(app, "后台/前台往返后")
        snap(app, "m15-position-background")
    }

    /// 旋转保持锚点（横屏/竖屏同一 asset 仍可见；±1 行内）
    func testRotationKeepsAnchor() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        let collection = app.collectionViews.firstMatch
        Thread.sleep(forTimeInterval: 0.5)
        guard let before = debugSnapshot(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off/anchor/visualY")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10), "横屏后应保持锚点月份")
        guard let landscape = debugSnapshot(app) else {
            return XCTFail("横屏后必须能读取位置快照")
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10), "回竖屏后应保持锚点月份")
        guard let restored = debugSnapshot(app) else {
            return XCTFail("回竖屏后必须能读取位置快照")
        }
        // 旋转是不同投影（列宽变化）：断言锚点 asset 一致，offset 允许布局重排误差（≤1 行由 AX 侧守门）
        XCTAssertEqual(landscape.anchor, before.anchor, "横屏锚点 asset 必须一致")
        XCTAssertEqual(restored.anchor, before.anchor, "回竖屏锚点 asset 必须一致")
        assertAlive(app, "旋转锚点保持后")
        XCUIDevice.shared.orientation = .portrait
        snap(app, "m15-position-rotation")
    }

    /// 筛选切换不得泄漏跨 scope 锚点：换年份后不得把 2024 的锚点带进 2023 视图
    func testFilterSwitchDoesNotLeakAnchor() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        guard let anchor2024 = debugSnapshot(app) else {
            return XCTFail("2024 视图必须能读取位置快照")
        }
        XCTAssertFalse(anchor2024.anchor.isEmpty)
        // 换筛选（2023）：queryKey 变化 → 不得恢复 2024 的锚点
        app.launchArguments.removeAll { $0 == "-uiTestingFilterYear" }
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        app.terminate()
        app.launchArguments += ["-uiTestingFilterYear", "2023"]
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2023", timeout: 10),
                      "筛选 2023 后顶部应为 2023（顶部：\(topHeaderText(app))）")
        guard let snapshot2023 = debugSnapshot(app) else {
            return XCTFail("2023 视图必须能读取位置快照")
        }
        // 2023 scope 首次打开从未保存过位置 → 必须从顶部开始；绝不能带进 2024 的锚点/offset
        XCTAssertLessThanOrEqual(snapshot2023.off, 2.0,
                                 "2023 视图首启必须回顶（off=\(snapshot2023.off)），跨 scope 锚点泄漏")
        if !anchor2024.anchor.isEmpty {
            XCTAssertNotEqual(snapshot2023.anchor, anchor2024.anchor,
                              "2024 锚点泄漏进 2023 视图")
        }
        XCTAssertNotEqual(topHeaderText(app), "", "2023 视图必须有月份头")
        assertAlive(app, "筛选切换后")
        snap(app, "m15-position-filter-switch")
    }

    /// 月份跳转落点持久化（S11 语义收编；跳转即 saveNow，重启后仍回目标月）
    func testMonthJumpPersistsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        app.terminate()
        _ = launchToGrid(app)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10),
                      "跳转后重启未回到 2024年5月（顶部：\(topHeaderText(app))）\n\(hierarchy(app))")
        assertAlive(app, "月份跳转重启后")
        snap(app, "m15-position-month-jump-persist")
    }
}
