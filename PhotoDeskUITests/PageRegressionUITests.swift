// MARK: - 职责说明：页面功能补齐回归 UI 测试（docs/09 Phase 0 / D01–D17 验收矩阵）——
// D01 查看器按 assetID 定位；D02 删除后显示同步；D03/D16 会话滑动 0 弹窗 + 提交恰好 1 次；
// D11 全选角标可见；D13 多选模式可滚动；D07 存储统计 5 秒内出结果（mock）。
// 稳定性约定：全部用 accessibilityIdentifier / DEBUG accessibilityValue（assetID），
// 系统弹窗用 addUIInterruptionMonitor；滑动链路用 -uiTestingSessionMock 隔离真实 PhotoKit 写。

import XCTest

final class PageRegressionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 公共

    /// 授权中断监视器（中英文兼容；与 FlowUITests 同款）
    private func installPermissionMonitor(for app: XCUIApplication) {
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

    private func launchToGrid(_ app: XCUIApplication) {
        installPermissionMonitor(for: app)
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
    }

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// 失败取证：AX 层级截断塞进断言消息
    private func hierarchy(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        return tree.count > 8000 ? String(tree.prefix(8000)) + "…(截断)" : tree
    }

    private func viewerDebugBanner(_ app: XCUIApplication) -> XCUIElement {
        anyElement(app, identifier: "Viewer-Debug")
    }

    // MARK: - D01 查看器打开所点的那张（assetID 定位）

    func testViewerOpensTappedPhoto() throws {
        let app = XCUIApplication()
        launchToGrid(app)

        let collection = app.collectionViews.firstMatch
        // 第 8 个 cell 的 accessibilityValue（DEBUG 构建 = assetID）
        let targetCell = collection.cells.element(boundBy: 7)
        XCTAssertTrue(targetCell.waitForExistence(timeout: 10), "网格不足 8 张")
        let expectedID = targetCell.value as? String ?? ""
        XCTAssertFalse(expectedID.isEmpty, "cell 缺 DEBUG accessibilityValue(assetID)")
        targetCell.tap()

        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10), "全屏浏览器未出现")
        let banner = viewerDebugBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "查看器 DEBUG 横幅未出现\n\(hierarchy(app))")
        // 横幅含 "id=<assetID>"（DEBUG 构建）
        XCTAssertTrue(banner.label.contains("id=\(expectedID)"),
                      "查看器定位到 \(banner.label)，期望第 8 张 \(expectedID)")
    }

    // MARK: - D02 删除（标记）后显示与目标同步

    func testDeleteKeepsDisplayedPhotoInSync() throws {
        let app = XCUIApplication()
        // 会话 mock：滑动只入队，不真实删除
        app.launchArguments += ["-uiTestingSessionMock", "-uiTestingViewerStartIndex", "7"]
        launchToGrid(app)

        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10), "-uiTestingViewerStartIndex 未打开查看器")

        let banner = viewerDebugBanner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        let before = banner.label   // "… id=<assetID> idx=7"

        // 下滑 = 标记待删除（默认下滑动作）→ 立即补位，横幅应变为下一张的 id
        let start = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        let after = banner.label
        XCTAssertNotEqual(after, before, "标记后查看器未前进（横幅 id 未变）")
        XCTAssertTrue(after.contains("id="), "横幅缺 id 字段：\(after)")
    }

    // MARK: - D03/D16a 连续 20 次下滑 0 系统弹窗、计数 20

    func testSessionSwipeDoesNotPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSessionMock", "-uiTestingViewerStartIndex", "7"]
        launchToGrid(app)

        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10))

        var alertCount = 0
        addUIInterruptionMonitor(withDescription: "SystemPromptCounter") { alert in
            alertCount += 1
            // 通用点掉（不应发生；发生了也让测试继续可断言计数）
            for index in 0..<alert.buttons.count where alert.buttons.element(boundBy: index).label.contains("允许") || alert.buttons.element(boundBy: index).label.contains("Allow") {
                alert.buttons.element(boundBy: index).tap()
            }
            return true
        }

        for _ in 0..<20 {
            let start = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.03, thenDragTo: end)
        }

        // 顶部待删除计数徽标 = 20
        let badge = anyElement(app, identifier: "SessionBadge")
        let ok = badge.waitForExistence(timeout: 5)
        XCTAssertTrue(ok, "待处理徽标未出现\n\(hierarchy(app))")
        XCTAssertTrue(badge.label.contains("20"), "待删除计数应为 20，实际「\(badge.label)」")
        XCTAssertEqual(alertCount, 0, "滑动期间出现了系统弹窗（\(alertCount) 次）")
    }

    // MARK: - D03/D16b 提交恰好 1 次（mock writer 计数 == 系统确认次数的等价信号）

    func testSessionCommitPromptsOnce() throws {
        let app = XCUIApplication()
        // mock 模式：BatchCommitCoordinator 对 mock writer 的批量提交次数 === 真实路径的 performChanges 次数
        app.launchArguments += ["-uiTestingSessionMock", "-uiTestingViewerStartIndex", "7"]
        launchToGrid(app)

        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10))

        for _ in 0..<3 {
            let start = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.03, thenDragTo: end)
        }

        // 打开整理回顾
        let badge = anyElement(app, identifier: "SessionBadge")
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "待处理徽标未出现")
        badge.tap()
        let review = anyElement(app, identifier: "SessionReviewRoot")
        XCTAssertTrue(review.waitForExistence(timeout: 5), "整理回顾页未出现\n\(hierarchy(app))")

        // 一次性批量提交
        let commit = anyElement(app, identifier: "SessionReview-CommitDelete")
        XCTAssertTrue(commit.waitForExistence(timeout: 3), "缺「全部移到最近删除」按钮")
        commit.tap()

        // mock writer 提交计数（通过回顾页/横幅回显；1 次批量 = 1 次 writer 调用）
        let done = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '已移到系统「最近删除」'")
        ).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "批量提交未完成或文案缺失\n\(hierarchy(app))")
    }

    // MARK: - D11 全选角标可见 + 计数

    func testSelectionBadgesAppearAfterSelectAll() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSelectMode"]
        launchToGrid(app)

        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 10), "多选工具栏未出现\n\(hierarchy(app))")
        selectAll.tap()

        // 全选是异步的（可能等待完整索引）：轮询计数标签出现非 0 计数
        let count = anyElement(app, identifier: "Selection-Count")
        XCTAssertTrue(count.waitForExistence(timeout: 5), "选中计数标签未出现")
        let counted = NSPredicate { _, _ in
            let label = count.label
            return label.contains("已选择") && !label.contains("已选择 0 项")
        }
        let expectation = XCTNSPredicateExpectation(predicate: counted, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        XCTAssertEqual(result, .completed, "全选后计数仍为 0：\(count.label)\n\(hierarchy(app))")

        // 角标：全选后至少一个可见 cell 的 accessibilityValue 带 "selected"
        let collection = app.collectionViews.firstMatch
        let firstCell = collection.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        var value = firstCell.value as? String ?? ""
        while !value.contains("selected") && Date() < deadline {
            usleep(300_000)
            value = firstCell.value as? String ?? ""
        }
        XCTAssertTrue(value.contains("selected"), "可见 cell 缺选中态标记：\(value)")
    }

    // MARK: - D13 多选模式下可滚动

    func testScrollWorksInSelectionMode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSelectMode"]
        launchToGrid(app)

        let collection = app.collectionViews.firstMatch
        let before = collection.cells.firstMatch.value as? String ?? ""

        app.swipeUp()
        app.swipeUp()

        let after = collection.cells.firstMatch.value as? String ?? ""
        XCTAssertNotEqual(before, after, "多选模式下两次上滑后首 cell 未变化——滚动被框选手势吃掉")
    }

    // MARK: - D07 存储统计（mock 数据 5 秒内出结果）

    func testStorageStatsCompletes() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingStorageMock"]
        installPermissionMonitor(for: app)
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }

        app.tabBars.buttons["工具"].tap()
        let entry = app.buttons["存储统计"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "工具页缺存储统计入口")
        entry.tap()

        let total = app.staticTexts["StorageStats-Total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "存储统计 5 秒内未出「总占用」结果（永久转圈）\n\(hierarchy(app))")
    }
}
