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

/// 工具 Tab 占位：清理 / 相簿 / 统计 / 设置入口自 M4/M3/M5/M7 逐个落位；
/// 手势教学临时入口挂这里（M7 迁入设置页，docs/04 §3.4「重新观看手势教学」）
private struct ToolsPlaceholderView: View {
    @State private var showTutorial = false

    var body: some View {
        VStack(spacing: 20) {
            Text("工具")
                .font(.largeTitle)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .padding(.top, 48)
            Button {
                showTutorial = true
            } label: {
                Label("手势教学", systemImage: "hand.draw")
                    .font(.body)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(ds: DSColor.bgSecondary))
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(ds: DSColor.bgSecondary).ignoresSafeArea())
        .fullScreenCover(isPresented: $showTutorial) {
            GestureTutorialView()
        }
    }
}
