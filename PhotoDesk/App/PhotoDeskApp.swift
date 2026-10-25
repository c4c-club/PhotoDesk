// MARK: - 职责说明：App 入口——两个 Tab：照片库 / 工具（docs/04 §2 信息架构）。
// 照片库 Tab 由 LibraryRootView 驱动：授权引导 → 加载骨架 → 网格（空态/受限横幅随状态切换）。
// 颜色一律取自 DesignSystem token（AGENTS.md §5）。

import SwiftUI

@main
struct PhotoDeskApp: App {
    @StateObject private var container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryRootView(viewModel: container.libraryViewModel,
                                service: container.libraryService,
                                undoCenter: container.undoCenter)
                    .tabItem { Label("照片库", systemImage: "photo.stack") }

                ToolsView()
                    .tabItem { Label("工具", systemImage: "wrench.and.screwdriver") }
            }
        }
    }
}
