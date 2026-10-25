// MARK: - 职责说明：工具 Tab（docs/04 §2）——
// 入口页：已隐藏（Face ID 门禁）/ 相簿 / 最近删除（说明+跳转）/ 手势教学。
// 智能清理与存储统计随 M4/M5 接入。导航壳用 NavigationView + .stack（iOS 15，AGENTS.md §2 黑名单）。

import SwiftUI

struct ToolsView: View {
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink {
                        CleanupView(viewModel: AppContainer.shared.makeCleanupViewModel(),
                                    coordinator: AppContainer.shared.scanCoordinator)
                    } label: {
                        Label("智能清理", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("Tools-Cleanup")

                    NavigationLink {
                        VaultView(vault: AppContainer.shared.vaultService,
                                  repository: AppContainer.shared.assetRepository,
                                  pipeline: AppContainer.shared.imagePipeline)
                    } label: {
                        Label("已隐藏", systemImage: "lock.fill")
                    }
                    .accessibilityIdentifier("Tools-Vault")

                    NavigationLink {
                        AlbumsView()
                    } label: {
                        Label("相簿", systemImage: "rectangle.stack")
                    }

                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("最近删除", systemImage: "trash.circle")
                    }
                }
                Section {
                    NavigationLink {
                        GestureTutorialView()
                    } label: {
                        Label("手势教学", systemImage: "hand.draw")
                    }
                }
                Section {
                    Text("存储统计将在 M5 开放")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具")
            .navigationViewStyle(.stack)   // iOS 15 双层导航陷阱（AGENTS.md §7）
        }
    }
}
