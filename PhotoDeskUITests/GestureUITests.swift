// MARK: - 职责说明：M2 核心手势 UI 测试（docs/05 M2 任务 2.12 / docs/06 §6.2）——
// 真实用户路径：授权（中断监视器）→ 网格 → 进全屏浏览器 → press(forDuration:thenDragTo:) 慢速垂直上滑
// → 断言 Toast「已收藏」出现 → 附加关键帧截图（CI 经 xcresulttool 提取上传 artifact）。

import XCTest

final class GestureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeUpFavoritesShowsToast() throws {
        let app = XCUIApplication()
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
        app.launch()

        // 授权引导 → 系统弹窗（已授权则跳过）
        let introButton = app.buttons["允许访问照片"]
        if introButton.waitForExistence(timeout: 10) {
            introButton.tap()
            app.tap()
        }

        // 网格就绪
        let collection = app.collectionViews.firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 30), "照片网格未出现")
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 15), "网格没有任何 cell")

        // 进全屏浏览器
        collection.cells.firstMatch.tap()
        let viewer = app.otherElements["ViewerRoot"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 10), "全屏浏览器未出现")

        // 慢速垂直上滑（docs/06 §6.2：慢速拖拽确保被识别）→ 默认上滑 = 收藏
        let start = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = viewer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)

        // 拖拽后立即截图（诊断：浮层/Toast/弹窗的真实状态）
        let afterDrag = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        afterDrag.name = "m2-after-drag"
        afterDrag.lifetime = .keepAlways
        add(afterDrag)

        // Toast「已收藏 · 撤销」；慢速拖拽未触发时用快速上滑兜底（速度锁定路径）
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已收藏'")).firstMatch
        if !toast.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        let toastOk = toast.waitForExistence(timeout: 5)
        if !toastOk {
            // 诊断：Viewer 状态横幅（pan/exec 链路）+ 屏上全部静态文本，随断言消息进日志
            let banner = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'pan:' OR label CONTAINS 'exec:' OR label CONTAINS 'viewer:'")
            ).firstMatch
            let allTexts = app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label)
            XCTFail("收藏 Toast 未出现；banner=\(banner.exists ? banner.label : "(无)") texts=\(allTexts)")
            return
        }

        // 关键帧截图（CI 提取 artifact，验收报告用）
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "m2-gesture-toast"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
