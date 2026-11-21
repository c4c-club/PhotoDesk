// MARK: - 职责说明：M20 红基线（T01，docs/49-M20-任务分段/T01-红基线与复现.md §3）——把三条
// 用户问题固化为可重复的失败证据；本文件不改任何生产代码：
// ① 长按 (1,1) 必须只选 1 张（当前行带语义把长按起手展开成整行）；
// ② 多选模式下从 cell0 直接横拖到 cell3 必须开始轨迹选择（当前触摸被消费、无 trail）；
// ③ denied 页必须有「去系统设置」、limited 0 张必须有「管理可见照片」、authorized 空库必须有
//    「导入照片」（Permission-Open-Settings / Permission-Manage-Limited / Library-Import，T03 才实现）。
// 编译口径：只引用现有公开 AX ID 与 launchArguments（Selection-Count / Library-DebugSummary /
// 「允许访问照片」与 RowBandSelectUITests 同款基建）。T03 落地 -uiTestingPermissionState /
// -uiTestingEmptyLibrary 注入后，网格用例经 authorized 直达网格（避免系统弹窗派发时机
// 竞态——run 44950888882 实锤：冷启动 intro 晚于 10s 窗口出现导致授权点按漏发）。
// 失败信息一律带 expected / actual / DEBUG 取证 / AX hierarchy 摘要，并落截图与完整层级附件（T01 §5）。

import XCTest
import UIKit

final class M20RedBaselineUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 基建（沿用 RowBandSelectUITests 验证过的驱动手法）

    private func installPermissionMonitor() {
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

    private static let baseLaunchArguments = ["-uiTestingSeedDatedPhotos", "-uiTestingClearPosition",
                                              "-uiTestingKeepChrome", "-uiTestingFilterYear", "0",
                                              "-uiTestingLongPressMovement"]

    /// 普通网格基建（docs/49 T01 §3.1 launchArguments 原样），extra 供各用例追加
    @discardableResult
    private func launchGrid(_ app: XCUIApplication, extra: [String] = []) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += Self.baseLaunchArguments + extra
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 10) {
            intro.tap()
            app.tap()
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现\n\(hierarchySummary(app))")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
        usleep(1_500_000)  // 布局/inset 稳定：静止按压期间内容位移 >8pt 会使长按失效
        return collection
    }

    /// 授权探针基建（docs/49 T01 §3.3–3.5）：不要求网格出现——当前 App 忽略
    /// -uiTestingPermissionState/-uiTestingEmptyLibrary，落到 intro/普通网格都是合法现场；
    /// 断言只针对目标按钮是否存在，避免「找不到网格」冒充预期失败（T01 §5）。
    private func launchPermissionProbe(_ app: XCUIApplication, extra: [String]) {
        installPermissionMonitor()
        app.launchArguments += Self.baseLaunchArguments + extra
        app.launch()
        let collection = app.collectionViews.firstMatch
        _ = collection.waitForExistence(timeout: 15)
        usleep(1_000_000)
    }

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// AX hierarchy 截断摘要（失败信息必带，T01 §5）
    private func hierarchySummary(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        return tree.count > 6000 ? String(tree.prefix(6000)) + "…(截断)" : tree
    }

    private func attachHierarchy(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func parseCount(_ label: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]+"),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range, in: label) else { return 0 }
        return Int(label[range]) ?? 0
    }

    /// Selection-Count 计数（-1 = 元素不存在）
    private func selectionCount(_ app: XCUIApplication) -> Int {
        let label = anyElement(app, identifier: "Selection-Count")
        guard label.exists else { return -1 }
        return Self.parseCount(label.label)
    }

    @discardableResult
    private func waitForSelectionCountEqual(_ app: XCUIApplication,
                                            to expected: Int,
                                            timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var value = selectionCount(app)
        while Date() < deadline {
            value = selectionCount(app)
            if value == expected { return value }
            usleep(100_000)
        }
        return value
    }

    private func cellIsSelected(_ cell: XCUIElement) -> Bool {
        ((cell.value as? String) ?? "").hasSuffix(" selected")
    }

    private func selectedVisibleValues(_ collection: XCUIElement) -> [String] {
        var values: [String] = []
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            if cell.exists, cellIsSelected(cell) {
                values.append((cell.value as? String) ?? "")
            }
        }
        return values
    }

    /// DEBUG 取证通道（Library-DebugSummary：off=/hap=/trail=/path=/delta=，仅 DEBUG 可读）
    private func trailDebugFields(_ app: XCUIApplication) -> String {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.exists else { return "Library-DebugSummary 缺失（DEBUG 钩子不可读）" }
        return ((banner.value as? String) ?? banner.label)
    }

    // MARK: - 红基线①（docs/49 T01 §3.1）：长按锚点必须只选 1 张

    func testLongPressAnchorSelectsExactlyOneCell() throws {
        let app = XCUIApplication()
        let collection = launchGrid(app, extra: ["-uiTestingPermissionState", "authorized"])
        let anchor = collection.cells.element(boundBy: 0)
        XCTAssertTrue(anchor.waitForExistence(timeout: 10), "网格无 cell\n\(hierarchySummary(app))")
        anchor.press(forDuration: 0.8)
        let count = waitForSelectionCountEqual(app, to: 1, timeout: 5)
        let selected = selectedVisibleValues(collection)
        attachHierarchy(app, name: "m20-red-1-hierarchy")
        XCTAssertEqual(count, 1,
                       "红基线①：长按 (1,1) 必须只选 1 张——expected=1, actual=\(count), " +
                       "selectedVisible=\(selected)（当前行带语义把长按起手展开成整行）" +
                       "\nAX 摘要：\(hierarchySummary(app))")
        guard count == 1 else {
            snap(app, "m20-red-1-longpress")
            return
        }
        XCTAssertEqual(selected.count, 1,
                       "红基线①：只允许 1 个 cell selected——actual=\(selected)")
        XCTAssertTrue(cellIsSelected(anchor),
                      "红基线①：入选必须是长按的锚点 cell（value=\((anchor.value as? String) ?? "")）")
    }

    // MARK: - 红基线②（docs/49 T01 §3.2）：选择模式下直接横拖必须开始轨迹选择

    func testSelectButtonDirectHorizontalDragStartsTrail() throws {
        let app = XCUIApplication()
        let collection = launchGrid(app, extra: ["-uiTestingSelectMode", "-uiTestingPermissionState", "authorized"])
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10),
                      "网格无 cell\n\(hierarchySummary(app))")
        XCTAssertTrue(collection.cells.count >= 4,
                      "可见 cell 不足 4 个（环境问题，不计入红基线）\n\(hierarchySummary(app))")
        let frames = (0..<4).map { collection.cells.element(boundBy: $0).frame }
        let geometry = frames.enumerated()
            .map { "c\($0.offset)=(x:\($0.element.minX), y:\($0.element.minY), \($0.element.width)x\($0.element.height))" }
            .joined(separator: " ")
        let start = collection.cells.element(boundBy: 0)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = collection.cells.element(boundBy: 3)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let count = waitForSelectionCountEqual(app, to: 4, timeout: 5)
        let debug = trailDebugFields(app)
        attachHierarchy(app, name: "m20-red-2-hierarchy")
        XCTAssertEqual(count, 4,
                       "红基线②：选择模式下从 cell0 直接横拖到 cell3 必须开始轨迹选择——" +
                       "expected=4, actual=\(count)（-1 = Selection-Count 不存在）, " +
                       "DEBUG[\(debug)]（当前触摸被消费、滚动被禁用、无 trail）, " +
                       "geometry: \(geometry)" +
                       "\nAX 摘要：\(hierarchySummary(app))")
        snap(app, "m20-red-2-drag")
    }

    // MARK: - 红基线③a（docs/49 T01 §3.3）：denied 页必须提供「去系统设置」

    func testDeniedScreenOffersSettings() throws {
        let app = XCUIApplication()
        launchPermissionProbe(app, extra: ["-uiTestingPermissionState", "denied"])
        let openSettings = anyElement(app, identifier: "Permission-Open-Settings")
        let exists = openSettings.waitForExistence(timeout: 10)
        attachHierarchy(app, name: "m20-red-3a-hierarchy")
        XCTAssertTrue(exists,
                      "红基线③a：denied 页必须提供「去系统设置」——expected 存在 " +
                      "Permission-Open-Settings, actual 不存在" +
                      "（当前 -uiTestingPermissionState 未实现，App 忽略该参数）" +
                      "\nAX 摘要：\(hierarchySummary(app))")
        let recheck = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "重新检查授权")).firstMatch
        XCTAssertFalse(recheck.exists && !exists,
                       "红基线③a：「重新检查授权」不得作为 denied 页主按钮单独存在" +
                       "（若存在只能是次按钮，且必须先有 Permission-Open-Settings）")
    }

    // MARK: - 红基线③b（docs/49 T01 §3.4）：limited 0 张必须提供「管理可见照片」

    func testLimitedEmptyOffersManage() throws {
        let app = XCUIApplication()
        launchPermissionProbe(app, extra: ["-uiTestingPermissionState", "limited",
                                           "-uiTestingEmptyLibrary"])
        let manage = anyElement(app, identifier: "Permission-Manage-Limited")
        let exists = manage.waitForExistence(timeout: 10)
        let plainEmpty = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "去拍一张或导入几张试试"))
            .firstMatch
        attachHierarchy(app, name: "m20-red-3b-hierarchy")
        XCTAssertTrue(exists,
                      "红基线③b：limited 0 张必须提供「管理可见照片」——expected 存在 " +
                      "Permission-Manage-Limited, actual 不存在" +
                      "（当前 -uiTestingPermissionState/-uiTestingEmptyLibrary 未实现，落到普通空态）" +
                      "\nAX 摘要：\(hierarchySummary(app))")
        XCTAssertFalse(plainEmpty.exists && !exists,
                       "红基线③b：limited 空库不得只呈现普通空态文案「去拍一张或导入几张试试」")
    }

    // MARK: - 红基线③c（docs/49 T01 §3.5）：authorized 空库必须提供「导入照片」

    func testAuthorizedEmptyOffersImport() throws {
        let app = XCUIApplication()
        launchPermissionProbe(app, extra: ["-uiTestingPermissionState", "authorized",
                                           "-uiTestingEmptyLibrary"])
        let importButton = anyElement(app, identifier: "Library-Import")
        let exists = importButton.waitForExistence(timeout: 10)
        attachHierarchy(app, name: "m20-red-3c-hierarchy")
        XCTAssertTrue(exists,
                      "红基线③c：authorized 空库必须提供「导入照片」——expected 存在 " +
                      "Library-Import, actual 不存在（当前普通空态无导入入口）" +
                      "\nAX 摘要：\(hierarchySummary(app))")
    }
}
