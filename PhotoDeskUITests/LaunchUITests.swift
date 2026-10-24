// MARK: - 职责说明：UI 冒烟测试——验证 App 能在 iOS 15.5 模拟器正常启动并渲染占位根视图。

import XCTest

final class LaunchUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["RootPlaceholder"].waitForExistence(timeout: 10))
    }
}
