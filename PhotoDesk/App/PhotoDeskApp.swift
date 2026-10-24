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
                                service: container.libraryService)
                    .tabItem { Label("照片库", systemImage: "photo.stack") }

                ToolsPlaceholderView()
                    .tabItem { Label("工具", systemImage: "wrench.and.screwdriver") }
            }
        }
    }
}

/// 工具 Tab 占位：清理 / 相簿 / 统计 / 设置入口自 M4/M3/M5/M7 逐个落位
private struct ToolsPlaceholderView: View {
    var body: some View {
        Text("工具")
            .font(.largeTitle)
            .foregroundColor(Color(ds: DSColor.textSecondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(ds: DSColor.bgSecondary))
    }
}
