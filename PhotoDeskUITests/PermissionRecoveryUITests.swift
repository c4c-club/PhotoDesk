// MARK: - 职责说明：授权恢复 UI 验收（docs/49 T03 §3.1）——launchArguments 注入授权态与空库，
// 全程不触真实系统弹窗：denied 主按钮去系统设置 + recheck 后内联提示；limited 空库管理入口
// （不得出现导入）；authorized 空库导入入口 + 导入 sheet；intro 允许按钮。

import XCTest

final class PermissionRecoveryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// docs/49 T03 §3.1：全部用 launchArguments 注入，避免真实系统弹窗不确定
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingClearPosition", "-uiTestingKeepChrome",
                                "-uiTestingFilterYear", "0"] + extra
        app.launch()
        return app
    }

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func summary(_ app: XCUIApplication) -> String {
        String(app.debugDescription.prefix(3000))
    }

    // MARK: - denied（docs/49 T01 红基线③a 转绿）

    func testDeniedOffersSettingsAndRecheckHint() throws {
        let app = launch(["-uiTestingPermissionState", "denied"])
        let openSettings = anyElement(app, identifier: "Permission-Open-Settings")
        XCTAssertTrue(openSettings.waitForExistence(timeout: 10),
                      "denied 页主按钮必须是「去系统设置」(Permission-Open-Settings)\n\(summary(app))")
        let recheck = anyElement(app, identifier: "Permission-Recheck")
        XCTAssertTrue(recheck.waitForExistence(timeout: 5),
                      "denied 页必须有次按钮「重新检查授权」(Permission-Recheck)\n\(summary(app))")
        recheck.tap()
        let hint = app.staticTexts["仍未授权，请到系统设置开启"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "recheck 后仍 denied 必须显示内联提示「仍未授权，请到系统设置开启」\n\(summary(app))")
        XCTAssertFalse(anyElement(app, identifier: "Library-Import").exists,
                       "denied 页不得出现导入入口")
    }

    // MARK: - limited + empty（docs/49 T01 红基线③b 转绿）

    func testLimitedEmptyOffersManageNotImport() throws {
        let app = launch(["-uiTestingPermissionState", "limited", "-uiTestingEmptyLibrary"])
        let manage = anyElement(app, identifier: "Permission-Manage-Limited")
        XCTAssertTrue(manage.waitForExistence(timeout: 10),
                      "limited 0 张必须有「管理可见照片」(Permission-Manage-Limited)\n\(summary(app))")
        XCTAssertFalse(anyElement(app, identifier: "Library-Import").exists,
                       "limited 空库不得出现导入入口（导入仅 authorized 空态可达）")
    }

    // MARK: - authorized + empty（docs/49 T01 红基线③c 转绿）

    func testAuthorizedEmptyOffersImport() throws {
        let app = launch(["-uiTestingPermissionState", "authorized", "-uiTestingEmptyLibrary"])
        let importButton = anyElement(app, identifier: "Library-Import")
        XCTAssertTrue(importButton.waitForExistence(timeout: 10),
                      "authorized 空库必须有「导入照片」(Library-Import)\n\(summary(app))")
        importButton.tap()
        let sheet = anyElement(app, identifier: "Photo-Import-Sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10),
                      "点导入必须出现导入 sheet（Photo-Import-Sheet）\n\(summary(app))")
    }

    // MARK: - intro

    func testIntroOffersAllow() throws {
        let app = launch(["-uiTestingPermissionState", "notDetermined"])
        let allow = anyElement(app, identifier: "Permission-Allow")
        XCTAssertTrue(allow.waitForExistence(timeout: 10),
                      "intro 必须有「允许访问照片」(Permission-Allow)\n\(summary(app))")
    }
}
