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
    private func launchToGrid(_ app: XCUIApplication, readyTimeout: TimeInterval = 30) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += ["-uiTestingKeepChrome", "-uiTestingFilterYear", "0"]
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: readyTimeout), "照片网格未出现\n\(hierarchy(app))")
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

    private static func parseDoubleField(_ label: String, _ key: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)=(-?[0-9]+(?:\\.[0-9]+)?)", options: .caseInsensitive),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return Double(label[range])
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

    /// Library-DebugSummary → (off, anchor, visualY)；off/visualY 允许负值（顶部回弹区 off=-44 合法）
    private func debugSnapshot(_ app: XCUIApplication) -> (off: Double, anchor: String, visualY: Double?)? {
        let raw = rawSummary(app)
        guard !raw.isEmpty else { return nil }
        let off = Self.parseDoubleField(raw, "off")
        let visualY = Self.parseDoubleField(raw, "visualY")
        guard let off, off.isFinite,
              let anchor = Self.parseStringField(raw, "anchor"), !anchor.isEmpty else { return nil }
        return (off, anchor, visualY)
    }

    private func rawSummary(_ app: XCUIApplication) -> String {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.exists else { return "" }
        return ((banner.value as? String) ?? banner.label)
    }

    /// 重启/回前台后的读取必须等恢复收敛：轮询直到连续两次读取一致（20s 上限）。
    /// 不硬性要求 raw 含 restore=（2023 视图等首启场景没有恢复，只有稳定快照）。
    private func debugSnapshotAfterRestore(_ app: XCUIApplication,
                                           timeout: TimeInterval = 20) -> (off: Double, anchor: String, visualY: Double?)? {
        let deadline = Date().addingTimeInterval(timeout)
        var stable: (off: Double, anchor: String, visualY: Double?)?
        while Date() < deadline {
            if let snap = debugSnapshot(app) {
                if let prev = stable, prev.anchor == snap.anchor, abs(prev.off - snap.off) <= 1.0 {
                    return snap
                }
                stable = snap
            }
            usleep(300_000)
        }
        return debugSnapshot(app)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fmt(_ value: Double?) -> String { value.map { String($0) } ?? "nil" }

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
            // 先等本轮启动的恢复收敛：套件内先前用例可能留有旧锚点，I1 门禁要求 settled
            // 才接受保存；不收敛就滑动会让 saveNow 被拒、存盘仍是旧锚点（轮 1 实锤）。
            _ = debugSnapshotAfterRestore(app)
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
            guard let before = debugSnapshotAfterRestore(app) else {
                return XCTFail("轮 \(round + 1)：Library-DebugSummary 必须暴露 off/anchor/visualY raw=\(rawSummary(app))")
            }
            // 拖动结束的 saveNow 是减速中途值，静止补存在 +1.5s；terminate 前给足静止时间
            Thread.sleep(forTimeInterval: 1.6)
            app.terminate()
            _ = launchToGrid(app)
            guard let after = debugSnapshotAfterRestore(app) else {
                return XCTFail("轮 \(round + 1)：重启后必须能读取位置快照 raw=\(rawSummary(app))")
            }
            guard after.anchor == before.anchor else {
                return XCTFail("轮 \(round + 1)：冷启动锚点 assetID 必须一致（before=\(before.anchor) off=\(before.off) " +
                               "visualY=\(fmt(before.visualY)) after=\(after.anchor) off=\(after.off) visualY=\(fmt(after.visualY))）" +
                               "raw=\(rawSummary(app))")
            }
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
        guard let before = debugSnapshotAfterRestore(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off/anchor/visualY")
        }
        Thread.sleep(forTimeInterval: 1.6)   // 静止补存 +1.5s 落盘后再杀
        app.terminate()
        _ = launchToGrid(app)
        guard let after = debugSnapshotAfterRestore(app) else {
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
        guard let before = debugSnapshotAfterRestore(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off/anchor/visualY")
        }
        Thread.sleep(forTimeInterval: 1.6)   // 静止补存落盘，退后台读到的就是静止位置
        XCUIDevice.shared.press(XCUIDevice.Button.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(collection.waitForExistence(timeout: 10), "回前台后网格必须就绪")
        guard let after = debugSnapshotAfterRestore(app) else {
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
        guard let before = debugSnapshotAfterRestore(app) else {
            return XCTFail("Library-DebugSummary 必须暴露 off/anchor/visualY")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10), "横屏后应保持锚点月份")
        guard let landscape = debugSnapshotAfterRestore(app) else {
            return XCTFail("横屏后必须能读取位置快照")
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(waitTopHeaderContains(app, "2024年5月", timeout: 10), "回竖屏后应保持锚点月份")
        guard let restored = debugSnapshotAfterRestore(app) else {
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
        guard let anchor2024 = debugSnapshotAfterRestore(app) else {
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
        guard let snapshot2023 = debugSnapshotAfterRestore(app) else {
            return XCTFail("2023 视图必须能读取位置快照 raw=\(rawSummary(app))")
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

    // MARK: - M16 T03（docs/28 §5.7）：v6 恢复硬化与深锚点

    /// 恢复诊断解析：by=策略 / verify ok=true|false / rej=恢复期被拒保存请求数。
    private func parseRestoreDiagnostics(_ label: String) -> (by: String, verifyOK: Bool?) {
        let by = Self.parseStringField(label, "by") ?? ""
        let okRaw = Self.parseStringField(label, "ok")
        return (by, okRaw.map { $0 == "true" })
    }

    /// 20 次冷启动 ≥19 次同 assetID ±2pt；0 次假 settled（asset 主路径 verify ok=false 却无 fallback）。
    func testColdLaunchRestoresSamePixelPosition20Times() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        let collection = app.collectionViews.firstMatch
        var pixelMisses = 0
        var fakeSettled = 0
        for round in 0..<20 {
            _ = debugSnapshotAfterRestore(app)
            if round > 0 {
                swipeUpOnce(in: collection)
                Thread.sleep(forTimeInterval: 0.6)
                if round % 3 == 0 {
                    swipeUpOnce(in: collection)
                    Thread.sleep(forTimeInterval: 0.6)
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
            guard let before = debugSnapshotAfterRestore(app) else {
                return XCTFail("轮 \(round + 1)：Library-DebugSummary 必须暴露 off/anchor/visualY raw=\(rawSummary(app))")
            }
            Thread.sleep(forTimeInterval: 1.6)
            app.terminate()
            _ = launchToGrid(app)
            guard let after = debugSnapshotAfterRestore(app) else {
                return XCTFail("轮 \(round + 1)：重启后必须能读取位置快照 raw=\(rawSummary(app))")
            }
            if after.anchor != before.anchor || abs(after.off - before.off) > 2.0 {
                pixelMisses += 1
            }
            let raw = rawSummary(app)
            let diagnostics = parseRestoreDiagnostics(raw)
            if diagnostics.verifyOK == false, diagnostics.by == "asset",
               !raw.contains("fallback"), raw.contains("restore=ok") {
                fakeSettled += 1
            }
            assertAlive(app, "轮 \(round + 1) 冷启动恢复后")
            if round == 19 {
                snap(app, "m16-position-20x")
            }
        }
        XCTAssertLessThanOrEqual(pixelMisses, 1,
                                 "20 次冷启动至少 19 次同 assetID ±2pt（miss=\(pixelMisses)）")
        XCTAssertEqual(fakeSettled, 0, "0 次假 settled（docs/28 §5.4：verify 必须真实 attributes）")
    }

    /// 锚点 globalIndex > 500 + 跨月窗口：深库（519 张）月跳最旧月 2002-01（锚点 idx≈518）→
    /// 滚一屏存锚点 → 冷启动走 v6 waitingForHead 逐批 head 补偿 → 同 assetID ±2pt、
    /// by=asset、不得降级 fallback（§5.5 步骤 4 补偿正确性的端到端实证）。
    func testDeepAnchorRestoresThroughHeadBackfill() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos", "-uiTestingSeedDeepLibrary"]
        launchWithMonthJump(app, sectionID: "2002-01", headerText: "2002年1月")
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        let collection = app.collectionViews.firstMatch
        swipeUpOnce(in: collection)
        Thread.sleep(forTimeInterval: 0.8)
        guard let before = debugSnapshotAfterRestore(app) else {
            return XCTFail("深锚点场景必须能读取位置快照 raw=\(rawSummary(app))")
        }
        Thread.sleep(forTimeInterval: 1.6)
        app.terminate()
        _ = launchToGrid(app, readyTimeout: 60)
        guard let after = debugSnapshotAfterRestore(app, timeout: 40) else {
            return XCTFail("深锚点冷启动必须恢复 raw=\(rawSummary(app))")
        }
        XCTAssertEqual(after.anchor, before.anchor, "深锚点（globalIndex>500）恢复 assetID 必须一致")
        XCTAssertLessThanOrEqual(abs(after.off - before.off), 2.0,
                                 "深锚点冷启动像素差必须 ≤2pt（before=\(before.off) after=\(after.off)）")
        let raw = rawSummary(app)
        XCTAssertTrue(raw.contains("by=asset"), "v6 主路径必须 asset 精确落地 raw=\(raw)")
        XCTAssertFalse(raw.contains("fallback"), "head 回填补偿后不得降级 fallback raw=\(raw)")
        assertAlive(app, "深锚点恢复后")
        snap(app, "m16-position-deep-anchor")
    }

    /// 恢复中强制滚动：用户拖动接管（§5.5）→ cancelRestore → 恢复让位，最终存活、
    /// 快照可读、用户滚动位置保留（不被恢复重新拉回）。
    func testUserScrollDuringRestoreTakesOver() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        launchWithMonthJump(app, sectionID: "2024-05", headerText: "2024年5月")
        app.launchArguments.removeAll { $0 == "-uiTestingMonthJump" }
        app.launchArguments.removeAll { $0 == "-uiTestingOpenMonthJump" }
        let collection = app.collectionViews.firstMatch
        swipeUpOnce(in: collection)
        Thread.sleep(forTimeInterval: 0.8)
        guard let before = debugSnapshotAfterRestore(app) else {
            return XCTFail("必须能读取位置快照 raw=\(rawSummary(app))")
        }
        Thread.sleep(forTimeInterval: 1.6)
        app.terminate()
        _ = launchToGrid(app)
        // 冷启动恢复进行中立即抢滚两屏：用户滚动优先于恢复定位
        collection.swipeUp()
        collection.swipeUp()
        Thread.sleep(forTimeInterval: 2.5)
        assertAlive(app, "恢复中强制滚动后")
        guard let after = debugSnapshotAfterRestore(app, timeout: 20) else {
            return XCTFail("接管后必须能读取位置快照 raw=\(rawSummary(app))")
        }
        XCTAssertGreaterThanOrEqual(after.off, before.off + 100,
                                    "用户接管的滚动位置必须保留，不得被恢复拉回（before=\(before.off) after=\(after.off)）")
        snap(app, "m16-position-restore-takeover")
    }
}
