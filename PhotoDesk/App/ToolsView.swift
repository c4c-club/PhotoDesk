// MARK: - 职责说明：工具页（docs/04 §2；docs/16 M12 R07：由照片库左上「工具」按钮 sheet 呈现）——
// 入口页：智能清理 / 已隐藏（Face ID 门禁）/ 相簿 / 最近删除 / 存储统计 / 手势教学 / 设置。
// 保留自身 NavigationView(.stack) 以支撑 NavigationLink 子页推入；新增 Tools-Close 关闭按钮
//（@Environment(\.dismiss)；下拉关闭同样回库）。状态隔离保持现状：libraryViewModel 常驻，
// 每次呈现重建 cleanup/vault VM，VaultView.onDisappear 立即锁，scanCoordinator 单例保留清理结果。

import SwiftUI

struct ToolsView: View {
    @Environment(\.dismiss) private var dismiss

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
                        VaultView(viewModel: AppContainer.shared.makeVaultViewModel())
                    } label: {
                        Label("已隐藏", systemImage: "lock.fill")
                    }
                    .accessibilityIdentifier("Tools-Vault")

                    NavigationLink {
                        AlbumsView()
                    } label: {
                        Label("相簿", systemImage: "rectangle.stack")
                    }
                    .accessibilityIdentifier("Tools-Albums")

                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("最近删除", systemImage: "trash.circle")
                    }
                    .accessibilityIdentifier("Tools-RecentlyDeleted")
                }
                Section {
                    NavigationLink {
                        StorageStatsView()
                    } label: {
                        Label("存储统计", systemImage: "chart.pie")
                    }
                    .accessibilityIdentifier("Tools-StorageStats")
                }
                Section {
                    NavigationLink {
                        GestureTutorialView()
                    } label: {
                        Label("手势教学", systemImage: "hand.draw")
                    }
                    .accessibilityIdentifier("Tools-GestureTutorial")
                }
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("Tools-Settings")
                }
                Section {
                    Button {
                        dismiss()   // R07：完成 → 回照片库
                    } label: {
                        Label("完成", systemImage: "checkmark")
                            .foregroundColor(Color(ds: DSColor.tint))
                    }
                    .accessibilityIdentifier("Tools-Close")
                }
                Section {
                    Text("搜索历史与智能视图已列入后续版本规划")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具")
            .navigationViewStyle(.stack)   // iOS 15 双层导航陷阱（AGENTS.md §7）
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityIdentifier("Tools-Close-Bar")
                    .accessibilityLabel("关闭工具")
                }
            }
        }
    }
}
