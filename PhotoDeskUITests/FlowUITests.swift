// MARK: - 职责说明：M8 流程 UI 测试（docs/05 §10 任务 8.2）——
// ① 批量选择（工具栏「多选」→ 全选 → 完成）；② 撤销往返（上滑收藏 → 撤销 → 再上滑仍可收藏，
// 证明撤销真实回滚了 PhotoKit 状态）；③ 清理扫描可启动、可取消（全程扫描耗时属真机专项）。
// 稳定性约定：全部用 accessibilityIdentifier 定位；undoWindow 经 launchArguments 调 30s 消竞态。

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

    /// 启动并进入网格（授权 → cell 就绪）；undoWindow 经 launchArguments 覆盖（消除 Toast 5s 窗口竞态）
    private func launchToGrid(_ app: XCUIApplication, undoWindow: Double = 30) {
        installPermissionMonitor(for: app)
        app.launchArguments += ["-gesture.undoWindow", "\(undoWindow)"]
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

        // 工具栏「多选」按钮进入（docs/04 §3.1；坐标点击绕开 SwiftUI 工具栏按钮的 AX action 失败）
        let selectButton = app.buttons["Library-Select"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 5), "导航栏缺「多选」按钮")
        selectButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let selectAll = app.buttons["Batch-SelectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "进入多选后批量工具栏未出现")

        selectAll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let deleteButton = app.buttons["Batch-Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "批量工具栏缺「移到最近删除」")

        // 退出多选（不执行破坏性操作）
        app.buttons["Batch-Done"].tap()
        XCTAssertFalse(app.buttons["Batch-SelectAll"].waitForExistence(timeout: 2),
                       "退出多选后工具栏应消失")
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

        // 点「撤销」（identifier 定位）→ PhotoKit 状态回滚
        let undo = app.buttons["Toast-Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Toast 缺撤销按钮")
        undo.tap()

        // 撤销窗口（30s）内再上滑 → 仍能出现「已收藏」＝ 撤销确实回滚了收藏状态
        sleep(2)
        swipeUp()
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "撤销后再收藏失败——撤销未真实回滚")
    }

    // MARK: - ③ 清理扫描可启动、可取消（全程扫描耗时属真机专项，docs/05 M4 验收）

    func testCleanupScanStartAndCancel() throws {
        let app = XCUIApplication()
        launchToGrid(app)

        app.tabBars.buttons["工具"].tap()
        let cleanupEntry = app.buttons["智能清理"]
        XCTAssertTrue(cleanupEntry.waitForExistence(timeout: 5), "工具页缺智能清理入口")
        cleanupEntry.tap()

        let start = app.buttons["开始扫描"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "清理页缺开始扫描")
        start.tap()

        // 进入扫描态（进度环/百分比出现）
        let runningMarker = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '.*扫描中.*|.*[0-9]+%.*'")
        ).firstMatch
        XCTAssertTrue(runningMarker.waitForExistence(timeout: 30), "扫描未进入运行态")

        // 取消 → 回到可再次扫描状态
        let cancelButton = app.buttons["取消"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "缺取消按钮")
        cancelButton.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "取消后未回到待机态")
    }
}
