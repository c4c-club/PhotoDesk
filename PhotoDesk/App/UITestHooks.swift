// MARK: - 职责说明：UI 测试钩子集中解析（docs/09 Phase 0）——
// 仅 #if DEBUG 编译；由启动参数驱动（-uiTestingViewerStartIndex / -uiTestingSelectMode /
// -uiTestingStorageMock / -uiTestingSessionMock / -uiTestingFaceIDBypass / -uiTestingFaceIDFailure /
// -uiTestingAppLock / -uiTestingDatedPhotos）。Release 构建全部返回 false，绝不影响生产路径。

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
}
#endif
