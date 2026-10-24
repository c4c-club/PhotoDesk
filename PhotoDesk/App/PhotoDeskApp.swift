// MARK: - 职责说明：App 入口——P-1 阶段仅用于打通 CI 编译/测试链路，并验证 PhotoDeskCore 本地包依赖可编译可链接。
// 完整骨架（AppContainer / Router / RootTabView）自 M0 起按 docs/03 §3 落位。

import SwiftUI
import PhotoDeskCore

@main
struct PhotoDeskApp: App {
    var body: some Scene {
        WindowGroup {
            Text("PhotoDesk · core \(PhotoDeskCoreInfo.placeholderVersion)")
                .accessibilityIdentifier("RootPlaceholder")
        }
    }
}
