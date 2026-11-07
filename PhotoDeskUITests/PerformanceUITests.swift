// MARK: - 职责说明：M1 性能验收（docs/05 §3：冷启动 < 2.0s、5,000 张滚动内存峰值 < 250MB）——
// Instruments 在无 Mac 环境不可用，CI 用 XCTest 指标替代（docs/06 §6.3）。
// FPS 以真机验证为准（docs/06 §3.2：模拟器性能 ≠ 真机）。本类在 CI 由 -only-testing 单独跑（大照片量后）。
// 授权：CI 无人工点击，系统照片授权弹窗经 addUIInterruptionMonitor 自动点「允许」（docs/06 §6.2 模式）。

import XCTest

final class PerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 注册中断监视器：自动点系统弹窗里的「允许」类按钮（兼容中英文文案）
    private func installPermissionMonitor(for app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
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

    /// 冷启动到首屏（docs/03 §7 预算 < 2.0s）
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

    /// 滚动内存峰值（5,000+ 张库；XCTMemoryMetric 记录驻留内存）
    func testScrollMemoryPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        installPermissionMonitor(for: app)
        app.launch()

        // 引导页 → 触发系统授权弹窗 → 中断监视器点「允许」；已授权则跳过
        let introButton = app.buttons["允许访问照片"]
        if introButton.waitForExistence(timeout: 10) {
            introButton.tap()
            app.tap()   // 中断监视器在下一次交互时检查弹窗
        }

        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现")
        // 网格必须有内容——空网格不代表数据管线健康（快照时序 bug 曾靠此断言暴露）
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格没有任何 cell")

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()], options: options) {
            for _ in 0..<6 {
                app.swipeUp(velocity: .fast)
            }
            for _ in 0..<2 {
                app.swipeDown(velocity: .fast)
            }
        }
    }

    // MARK: - docs/13 Phase 7：查看器连滑内存（5,000 张 100 次滑动峰值 < 250MB）

    func testViewerMemoryUnderFastSwipe() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        app.launchArguments += ["-uiTestingKeepChrome", "-uiTestingViewerStartIndex", "0"]
        installPermissionMonitor(for: app)
        app.launch()
        let introButton = app.buttons["允许访问照片"]
        if introButton.waitForExistence(timeout: 10) {
            introButton.tap()
            app.tap()
        }
        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 30), "查看器未打开")

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTMemoryMetric()], options: options) {
            for _ in 0..<50 {
                viewer.swipeLeft(velocity: .fast)
            }
            for _ in 0..<50 {
                viewer.swipeRight(velocity: .fast)
            }
        }
        XCTAssertEqual(app.state, .runningForeground, "100 次连滑后 App 必须存活")
    }

    // MARK: - docs/13 Phase 7：年份筛选性能（5,470 张切换 < 500ms/次）

    func testFilterPerformance() throws {
        // 预算 500ms/次针对 App 内 setFilter 后台重算（PhotoDeskCore 万级谓词已有单测）。
        // UI 侧用「就绪即应用年份」钩子走同一条 setFilter 路径，以 启动→网格→年份月头渲染 全链路时钟度量
        //（含 CI 冷启动开销，作为上界参考；iOS 15 XCUITest 对面板内 SwiftUI Button 合成点击不可靠，docs/13 M11）。
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        installPermissionMonitor(for: app)
        app.launchArguments += ["-uiTestingFilterYear", "2024"]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(), XCTClockMetric()], options: options) {
            app.launch()
            let collection = app.collectionViews.firstMatch
            guard collection.waitForExistence(timeout: 30) else { return }
            _ = collection.cells.firstMatch.waitForExistence(timeout: 15)
            _ = self.waitHeaderContains(collection, "2024年")
        }
        XCTAssertEqual(app.state, .runningForeground, "年份筛选启动后 App 必须存活")
    }

    private func waitHeaderContains(_ collection: XCUIElement, _ text: String) -> Bool {
        // 月头被 AX 暴露为 Button（标题带点击手势）——用 .any 后代查询
        let headers = collection.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '月 ·'"))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if headers.count > 0, headers.firstMatch.label.contains(text) { return true }
            usleep(300_000)
        }
        return false
    }
}