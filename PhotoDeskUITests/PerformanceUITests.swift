// MARK: - 职责说明：M1 性能验收（docs/05 §3：冷启动 < 2.0s、5,000 张滚动内存峰值 < 250MB）——
// Instruments 在无 Mac 环境不可用，CI 用 XCTest 指标替代（docs/06 §6.3）。
// FPS 以真机验证为准（docs/06 §3.2：模拟器性能 ≠ 真机）。本类在 CI 由 -only-testing 单独跑（大照片量后）。

import XCTest

final class PerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
        app.launch()
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 15), "照片网格未出现")

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
