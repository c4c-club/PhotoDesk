// MARK: - 职责说明：UI 测试钩子集中解析（docs/09 Phase 0）——
// 仅 #if DEBUG 编译；由启动参数驱动（-uiTestingViewerStartIndex / -uiTestingSelectMode /
// -uiTestingGridNoSelection【网格捏合 UI 测试禁 cell 点选：合成双指易误投成点按打开查看器】/
// -uiTestingStorageMock / -uiTestingSessionMock / -uiTestingFaceIDBypass / -uiTestingFaceIDFailure /
// -uiTestingAppLock / -uiTestingDatedPhotos / -uiTestingDisableAnimations【docs/13 Phase 0：
// 关闭全 App 动画，稳定坐标点击用，不是修复手段】/ -uiTestingOpenFilterSheet /
// -uiTestingOpenMonthJump【网格就绪后自动打开筛选/月份面板，仅验证渲染】/
// -uiTestingFilterYear <n>【网格就绪后应用年份筛选，0 = 清空——等价用户在面板选年并应用，
// 走同一条 setFilter 路径；iOS 15 XCUITest 对 SwiftUI Toolbar/Form 内 Button 的合成点击不可靠（CI 轮 9–12 实证）】/
// -uiTestingMonthJump <sectionID>【网格就绪后跳转指定月份分组，等价月份面板点卡片，走同一条 scrollToSection】）。
// Release 构建全部返回 false，绝不影响生产路径。

import Foundation

#if DEBUG
enum UITestHooks {
    /// 启动参数中是否包含某个布尔开关（如 "-uiTestingSessionMock"）
    static func enabled(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    /// 读取「<flag> <int>」形式的启动参数值（如 "-uiTestingViewerStartIndex 7"）
    static func intValue(_ flag: String) -> Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag),
              index + 1 < args.count,
              let value = Int(args[index + 1]) else { return nil }
        return value
    }

    /// 读取「<flag> <string>」形式的启动参数值（如 "-uiTestingMonthJump 2024-05"）
    static func stringValue(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag),
              index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
#endif
