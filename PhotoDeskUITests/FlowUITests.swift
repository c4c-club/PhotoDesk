// MARK: - 职责说明：M8 流程 UI 测试（docs/05 §10 任务 8.2）——
// ① 批量选择（长按进入 → 工具栏 → 全选 → 完成）；② 撤销往返（上滑收藏 → Toast 撤销 → 再上滑仍可收藏，
// 证明撤销真实回滚了 PhotoKit 状态）；③ 清理确认流程（扫描 → 重复组 → 保留推荐项 → 待清理 →
// 确认弹窗出现后取消——**不执行删除**，真实删除走真机冒烟）。

import XCTest

final class FlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 授权中断监视器（中英文兼容）
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

    /// 启动并进入网格（授权 → cell 就绪）
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

    // MARK: - ① 批量选择

    func testBatchSelectionFlow() throws {
        let app = XCUIApplication()
        launchToGrid(app)

        // 长按进入多选
        let firstCell = app.collectionViews.cells.firstMatch
        firstCell.press(forDuration: 1.2)

        let selectAll = app.buttons["全选"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "长按后批量工具栏未出现")

        selectAll.tap()
        let deleteButton = app.buttons["移到最近删除"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "批量工具栏缺「移到最近删除」")

        // 退出多选（不执行破坏性操作）
        app.buttons["完成"].tap()
        XCTAssertFalse(app.buttons["全选"].waitForExistence(timeout: 2), "退出多选后工具栏应消失")
    }

    // MARK: - ② 撤销往返（收藏 → 撤销 → 仍可再收藏）

    func testSwipeFavoriteThenUndoRoundTrip() throws {
        let app = XCUIApplication()
        launchToGrid(app)

        app.collectionViews.cells.firstMatch.tap()
        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10), "全屏浏览器未出现")

        func swipeUp() {
            let start = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        // 第一次上滑 → 已收藏
        swipeUp()
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已收藏'")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "收藏 Toast 未出现")

        // 点「撤销」→ Toast 消失（PhotoKit 状态回滚为未收藏）
        let undo = app.buttons["撤销"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Toast 缺撤销按钮")
        undo.tap()

        // 撤销窗口后再上滑 → 仍能出现「已收藏」＝ 撤销确实回滚了收藏状态
        sleep(2)
        swipeUp()
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "撤销后再收藏失败——撤销未真实回滚")
    }

    // MARK: - ③ 清理确认流程（弹窗出现即止，不删除）

    func testCleanupConfirmationFlow() throws {
        let app = XCUIApplication()
        launchToGrid(app)

        app.tabBars.buttons["工具"].tap()
        let cleanupEntry = app.buttons["智能清理"]
        XCTAssertTrue(cleanupEntry.waitForExistence(timeout: 5), "工具页缺智能清理入口")
        cleanupEntry.tap()

        let start = app.buttons["开始扫描"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "清理页缺开始扫描")
        start.tap()

        // 扫描完成：五类卡片或"没有可清理内容"（5,300 张模拟器库约需 10–40s）
        let doneMarker = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '没有发现可清理的内容' OR label CONTAINS '重复照片'")
        ).firstMatch
        XCTAssertTrue(doneMarker.waitForExistence(timeout: 180), "扫描未在 180s 内完成")

        // 有重复组则走完整确认链；没有则本用例以空结果通过
        guard app.staticTexts.matching(NSPredicate(format: "label CONTAINS '重复照片'")).firstMatch.exists
        else { return }

        app.staticTexts.matching(NSPredicate(format: "label CONTAINS '重复照片'")).firstMatch.tap()
        let keepRecommended = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '保留推荐项'")
        ).firstMatch
        XCTAssertTrue(keepRecommended.waitForExistence(timeout: 10), "重复组 sheet 缺保留推荐项按钮")
        keepRecommended.tap()

        // 待清理清单按钮（docs/04 §7 文案）
        let execute = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '移到最近删除（可在 30 天内恢复）'")
        ).firstMatch
        XCTAssertTrue(execute.waitForExistence(timeout: 5), "待清理清单缺执行按钮")
        execute.tap()

        // 二次确认弹窗出现 → 取消（真实删除走真机冒烟；系统另有不可绕过的确认框）
        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "二次确认弹窗未出现")
        cancel.tap()
    }
}
