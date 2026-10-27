// MARK: - 职责说明：M8 流程 UI 测试（docs/05 §10 任务 8.2）——
// ① 批量选择（长按进入 → 全选 → 移到最近删除按钮可见 → 完成）；② 撤销往返（上滑收藏 → 撤销 →
// 再上滑仍可收藏，证明撤销真实回滚了 PhotoKit 状态）；③ 清理扫描可启动、可取消。
// 稳定性约定：全部用 accessibilityIdentifier + descendants(.any) 定位（UIToolbar 内 UIBarButtonItem
// 的 AX 暴露类型跨版本不稳定）；undoWindow 经 launchArguments 调 30s 消竞态。

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

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// 失败取证：把当前 AX 层级（截断）塞进断言消息——CI 日志可直接读出真实元素树
    private func hierarchy(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        return tree.count > 8000 ? String(tree.prefix(8000)) + "…(截断)" : tree
    }

    // MARK: - ① 批量选择（长按进入 → 全选 → 移到最近删除按钮存在 → 完成）

    func testBatchSelectionFlow() throws {
        let app = XCUIApplication()
        // -uiTestingSelectMode：App 侧测试钩子（启动即进入多选）——长按与 SwiftUI 工具栏按钮的
        // XCUITest 触发均不可靠（AX scroll-to-visible 失败），测试钩子是标准做法
        app.launchArguments += ["-uiTestingSelectMode"]
        launchToGrid(app)

        let selectAll = anyElement(app, identifier: "Batch-SelectAll")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 10), "多选态下批量工具栏未出现\n\(hierarchy(app))")

        selectAll.tap()
        let deleteButton = anyElement(app, identifier: "Batch-Delete")
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "批量工具栏缺「移到最近删除」")

        // 退出多选（不执行破坏性操作）
        let done = anyElement(app, identifier: "Batch-Done")
        done.tap()
        XCTAssertFalse(selectAll.waitForExistence(timeout: 2), "退出多选后工具栏应消失")
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
        guard toast.waitForExistence(timeout: 5) else {
            XCTFail("收藏 Toast 未出现\n\(hierarchy(app))")
            return
        }

        // 点「撤销」：按钮固定在 Toast 右端——用 toast 坐标点击（100% 命中，绕开按钮 AX 查询差异）
        toast.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        // 撤销窗口（30s）内再上滑 → 仍能出现「已收藏」＝ 撤销确实回滚了收藏状态
        sleep(2)
        swipeUp()
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "撤销后再收藏失败——撤销未真实回滚")
    }

    // MARK: - ③ 清理扫描可启动、可取消（全程扫描耗时属真机专项，docs/05 M4 验收）

    func testCleanupScanStartAndCancel() throws {
        let app = XCUIApplication()
        // -CleanupAutoStart：App 侧测试钩子（清理页 onAppear 自动开始扫描）——
        // Form 内 Button 的 AX/coordinate 点击均不可靠（Library-Select 同款问题），测试钩子是标准做法
        app.launchArguments += ["-CleanupAutoStart"]
        launchToGrid(app)

        app.tabBars.buttons["工具"].tap()
        let cleanupEntry = app.buttons["智能清理"]
        XCTAssertTrue(cleanupEntry.waitForExistence(timeout: 5), "工具页缺智能清理入口")
        cleanupEntry.tap()

        // 进入扫描态（百分比文本出现）
        let progress = anyElement(app, identifier: "Cleanup-Progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 60), "扫描未进入运行态\n\(hierarchy(app))")

        // 取消 → 回到可再次扫描状态（取消按钮同样走 coordinate 点击）
        let cancel = anyElement(app, identifier: "Cleanup-Cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "缺取消按钮")
        cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let startAgain = anyElement(app, identifier: "Cleanup-Start")
        XCTAssertTrue(startAgain.waitForExistence(timeout: 10), "取消后未回到待机态")
    }
}
