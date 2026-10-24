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
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

    /// 滚动内存峰值（5,000+ 张库；XCTMemoryMetric 记录驻留内存）
    func testScrollMemoryPerformance() throws {
        let app = XCUIApplication()
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
}
