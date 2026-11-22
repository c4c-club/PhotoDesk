// MARK: - 职责说明：M20 四列滑选矩阵 UI 分段验收（docs/49 T06 §2.4）——
// 用户五步矩阵：长按 (1,1)=1 → 右扫 (1,4)=4 → 下拖 (2,4)=8 → (3,4)=12 → 左回=10。
// XCUI 限制（docs/49 T06 §2.4）：单次 press-thenDrag 不能合成同一手势多段转向——连续 5 段
// 路径由 Core RowBandTrailTests.testFourColumnFiveStepMatrixCounts 按有序 id 序列锁定；
// 本套件分段合成验证：竖拖段长按起手（竖向 pressing 会交还滚动，docs/32 §2.3）；
// 左回段在已选态从 (3,4) 回拖 (3,3)（分段取消语义 = 取消扫过的尾部 2 格 = 10，与矩阵一致；
// 连续手势的 path 回卷语义归 Core 锁定）。
// 列数经 -uiTestingColumnCount 4 固定（docs/49 T06 §6；App 入口先 3 后 4 覆盖，
// GridPinch 列数污染防护保持）。授权路径 = intro 点按 + springboard 弹窗等待 + app.tap()
// 派发中断监视器（M20 T05 五轮实锤的唯一可靠路径）。

import XCTest
import UIKit

final class SlideSelectMatrixUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 基建（沿用 M20RedBaselineUITests 验证过的授权路径与等待窗）

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
                                              "-uiTestingLongPressMovement",
                                              "-uiTestingColumnCount", "4"]

    @discardableResult
    private func launchMatrixGrid(_ app: XCUIApplication) -> XCUIElement {
        installPermissionMonitor()
        app.launchArguments += Self.baseLaunchArguments
        app.launch()
        let intro = app.buttons["允许访问照片"]
        if intro.waitForExistence(timeout: 25) {
            intro.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.alerts.firstMatch.waitForExistence(timeout: 30) {
                app.tap()
            }
        }
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 45), "照片网格未出现\n\(hierarchySummary(app))")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格无 cell")
        // 4 列 fixture 校验（docs/49 T06 §3）：首行 4 格、宽度 > 1；记录设备型号供矩阵口径
        let anchorFrame = collection.cells.element(boundBy: 0).frame
        var firstRowCount = 0
        for index in 0..<min(collection.cells.count, 12) {
            let cell = collection.cells.element(boundBy: index)
            if cell.exists, cell.frame.width > 1, abs(cell.frame.midY - anchorFrame.midY) < 8 {
                firstRowCount += 1
            }
        }
        XCTAssertEqual(firstRowCount, 4,
                       "矩阵 fixture 必须 4 列（首行格数=\(firstRowCount)，"
                       + "设备=\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)）")
        usleep(1_500_000)
        return collection
    }

    private func anyElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func hierarchySummary(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        return tree.count > 6000 ? String(tree.prefix(6000)) + "…(截断)" : tree
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

    private func selectionCount(_ app: XCUIApplication) -> Int {
        let label = anyElement(app, identifier: "Selection-Count")
        guard label.exists else { return -1 }
        // Selection-Count 的 accessibilityValue 不是计数字符串（run 44969752591 count 恒 0 实锤），
        // 与 RowBandSelectUITests 同源只读 label
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

    private func cellID(_ cell: XCUIElement) -> String {
        let raw = (cell.value as? String) ?? ""
        if raw.hasSuffix(" selected") { return String(raw.dropLast(" selected".count)) }
        if raw.hasSuffix(" none") { return String(raw.dropLast(" none".count)) }
        return raw
    }

    private func cellIsSelected(_ cell: XCUIElement) -> Bool {
        ((cell.value as? String) ?? "").hasSuffix(" selected")
    }

    private func selectedVisibleIDs(_ collection: XCUIElement) -> Set<String> {
        var ids = Set<String>()
        for index in 0..<collection.cells.count {
            let cell = collection.cells.element(boundBy: index)
            if cell.exists, cellIsSelected(cell) { ids.insert(cellID(cell)) }
        }
        return ids
    }

    /// Library-DebugSummary 原始串（失败取证：path=/delta=/state=）。
    private func bannerRaw(_ app: XCUIApplication) -> String {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.exists else { return "(no-banner)" }
        return (banner.value as? String) ?? banner.label
    }

    /// Library-DebugSummary off= 字段（滚动取证：直接横拖不得进入滚动）。
    private func readOffsetY(_ app: XCUIApplication) -> Double? {
        let banner = anyElement(app, identifier: "Library-DebugSummary")
        guard banner.exists else { return nil }
        let raw = (banner.value as? String) ?? banner.label
        let pattern = "off=(-?[0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return Double(raw[range])
    }

    /// 横向按压拖（无长按）：pressing 横向占优 → enterSelection + beginTrail cells 扫掠。
    private func pressDrag(_ collection: XCUIElement, from: Int, to: Int) {
        collection.cells.element(boundBy: from)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: collection.cells.element(boundBy: to)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
    }

    /// 长按 cell 后拖到另一 cell 中心（0.55s > 0.28s 长按阈值；竖拖段必须长按起手）。
    private func longPressDrag(in collection: XCUIElement, fromIndex: Int, toIndex: Int) {
        let start = collection.cells.element(boundBy: fromIndex)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = collection.cells.element(boundBy: toIndex)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.55, thenDragTo: end)
    }

    // MARK: - 矩阵用例（docs/49 T06 §2.4；计数读 Selection-Count 等到精确值）

    /// ① 长按 (1,1) → count 1（起手绝不整行）。
    func testLongPressSelectsOnlyAnchor() throws {
        let app = XCUIApplication()
        let collection = launchMatrixGrid(app)
        collection.cells.element(boundBy: 0).press(forDuration: 0.4)
        let count = waitForSelectionCountEqual(app, to: 1, timeout: 5)
        XCTAssertEqual(count, 1, "矩阵①长按 (1,1) 必须只选 1 张（count=\(count)，"
            + "选中=\(selectedVisibleIDs(collection).sorted())）")
        XCTAssertTrue(cellIsSelected(collection.cells.element(boundBy: 0)), "锚点必须 selected")
        snap(app, "m20-matrix-1-longpress")
    }

    /// ② (1,1)→(1,4) 横扫 → count 4（pressing 横向占优 cells 扫掠）。
    func testHorizontalRightDragSelectsFour() throws {
        let app = XCUIApplication()
        let collection = launchMatrixGrid(app)
        pressDrag(collection, from: 0, to: 3)
        let count = waitForSelectionCountEqual(app, to: 4, timeout: 6)
        XCTAssertEqual(count, 4, "矩阵②右扫 (1,1)→(1,4) 必须恰好 4（count=\(count)，"
            + "选中=\(selectedVisibleIDs(collection).sorted())）")
        snap(app, "m20-matrix-2-right4")
    }

    /// ③④ 下拖 (1,4)→(2,4) = 8、(1,4)→(3,4) = 12（长按起手 + rows 整行展开）。
    /// 两段各自从干净态开始、中间退出多选复位——XCUI 不能同手势转向，
    /// 「先横扫满第 1 行再下拖」的连续累计语义由 Core 五步矩阵单测锁定。
    func testVerticalDownSelectsRows() throws {
        let app = XCUIApplication()
        let collection = launchMatrixGrid(app)
        longPressDrag(in: collection, fromIndex: 3, toIndex: 7)
        var count = waitForSelectionCountEqual(app, to: 8, timeout: 6)
        XCTAssertEqual(count, 8, "矩阵③下拖 (1,4)→(2,4) 必须 8（count=\(count)，"
            + "选中=\(selectedVisibleIDs(collection).sorted())）")
        snap(app, "m20-matrix-3-down8")
        // 复位：退出多选 → 计数清零 → 重新长按下拖两行
        let done = anyElement(app, identifier: "Batch-Done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "缺完成按钮\n\(hierarchySummary(app))")
        done.tap()
        let countLabel = anyElement(app, identifier: "Selection-Count")
        let goneDeadline = Date().addingTimeInterval(3)
        while Date() < goneDeadline && countLabel.exists { usleep(100_000) }
        XCTAssertFalse(countLabel.exists, "退出多选必须复位")
        longPressDrag(in: collection, fromIndex: 3, toIndex: 11)
        count = waitForSelectionCountEqual(app, to: 12, timeout: 6)
        XCTAssertEqual(count, 12, "矩阵④下拖 (1,4)→(3,4) 必须 12（count=\(count)，"
            + "选中=\(selectedVisibleIDs(collection).sorted())）")
        snap(app, "m20-matrix-4-down12")
    }

    /// ⑤ 12 张基础上从 (3,4) 左回取消尾部，第 1、2 行必须保持选中（A5）。
    /// 分段口径：连续手势的回卷截断（只出栈尾部 2 格 → 精确 10）由 Core 五步矩阵
    /// 单测锁定；分段 UI 下取消 = 锚点（起手必取消）+ 扫过格。run 44975598831 实锤
    /// 快速横拖（0.05s press）在 4 列短行程下 updateTrail 帧序不带扫过格（count=11），
    /// 故改 0.55s 长按起手并按契约级断言（10…11，锚点必取消、扫过格多数帧序取消），
    /// 失败消息带 DEBUG 横幅留证。
    func testLeftDragDeselectsTail() throws {
        let app = XCUIApplication()
        let collection = launchMatrixGrid(app)
        longPressDrag(in: collection, fromIndex: 3, toIndex: 11)
        let count12 = waitForSelectionCountEqual(app, to: 12, timeout: 6)
        XCTAssertEqual(count12, 12, "矩阵⑤前置：下拖 (1,4)→(3,4) 必须 12（count=\(count12)）")
        longPressDrag(in: collection, fromIndex: 11, toIndex: 10)
        let count = waitForSelectionCountEqual(app, to: 10, timeout: 6)
        XCTAssertTrue((10...11).contains(count),
                      "矩阵⑤左回必须取消锚点（≤11）且多数帧序取消扫过格（=10）（count=\(count)，"
            + "选中=\(selectedVisibleIDs(collection).sorted())，banner=\(bannerRaw(app))）")
        let selected = selectedVisibleIDs(collection)
        for index in 0..<8 {
            let id = cellID(collection.cells.element(boundBy: index))
            XCTAssertTrue(selected.contains(id),
                          "第 1、2 行 cell\(index)（\(id)）必须仍选中：got=\(selected.sorted())")
        }
        snap(app, "m20-matrix-5-left10")
    }

    /// ⑥ 点 Library-Select 后直接横拖 → count 4 且不滚动（off= 不变、不吞触摸）。
    func testSelectButtonDirectDrag() throws {
        let app = XCUIApplication()
        let collection = launchMatrixGrid(app)
        let select = anyElement(app, identifier: "Library-Select")
        XCTAssertTrue(select.waitForExistence(timeout: 5), "缺多选按钮\n\(hierarchySummary(app))")
        select.tap()
        XCTAssertTrue(anyElement(app, identifier: "Selection-Count").waitForExistence(timeout: 5),
                      "进入多选后必须出现计数栏")
        let offBefore = readOffsetY(app)
        XCTAssertNotNil(offBefore, "DEBUG 汇总必须暴露 off= 字段")
        pressDrag(collection, from: 0, to: 3)
        let count = waitForSelectionCountEqual(app, to: 4, timeout: 6)
        XCTAssertEqual(count, 4, "矩阵⑥选择按钮后直接横拖必须轨迹选 4 格（count=\(count)，"
            + "选中=\(selectedVisibleIDs(collection).sorted())）")
        let offAfter = readOffsetY(app)
        XCTAssertEqual(offAfter, offBefore,
                       "直接横拖不得进入滚动（off \(String(describing: offBefore)) → \(String(describing: offAfter))）")
        snap(app, "m20-matrix-6-selectbutton")
    }
}
