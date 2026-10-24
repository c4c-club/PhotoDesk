// MARK: - 职责说明：UI 冒烟测试——验证 App 在 iOS 15.5 模拟器正常启动，且信息架构为两个 Tab（照片库 / 工具，
// docs/04 §2）。M0 验收项「能看到两个 Tab」的自动化版本。

import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunchesWithTwoTabs() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["照片库"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["工具"].exists)
    }
}
