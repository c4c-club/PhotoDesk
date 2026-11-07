// MARK: - 职责说明：UI 冒烟测试——验证 App 在 iOS 15.5 模拟器正常启动，信息架构符合 docs/16 M12：
// 无底部分页（TabBar 移除）、顶部无 App 标题、左上「工具」入口存在且网格可达。

import XCTest

final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsGridWithoutTabBarOrTitle() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSeedDatedPhotos"]
        app.launch()

        // 网格可达（授权引导 → 网格；无授权时网格也会在授权后出现）
        let collection = app.collectionViews.firstMatch
        if !collection.waitForExistence(timeout: 30) {
            let intro = app.buttons["允许访问照片"]
            if intro.waitForExistence(timeout: 5) {
                intro.tap()
                app.tap()
            }
        }
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现")

        // R07：无 TabBar
        XCTAssertFalse(app.tabBars.firstMatch.exists, "M12 R07：不得再有底部分页 TabBar")
        // R05：顶部无 App 标题
        XCTAssertFalse(app.navigationBars.staticTexts["照片管家"].exists,
                       "M12 R05：顶部不得显示「照片管家」标题")
        // R07：左上工具入口存在
        let tools = app.descendants(matching: .any)["Library-Tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5), "左上缺 Library-Tools 工具入口")
    }
}
