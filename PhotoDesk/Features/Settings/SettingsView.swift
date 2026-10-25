// MARK: - 职责说明：设置中枢（docs/04 §2 / docs/05 M7）——
// 分组入口：手势 ★ / 外观与网格 / 隐私与锁定 / 缓存与存储 / 无障碍 / 关于与诊断。
// 子页各自持有 @AppStorage（改动即存即生效），本页只做导航。

import SwiftUI

struct SettingsView: View {
    @AppStorage("gesture.enabled") private var gesturesEnabled = true

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GestureSettingsView()
                } label: {
                    Label("手势设置", systemImage: "hand.draw")
                }
                .accessibilityIdentifier("Settings-Gesture")

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("外观与网格", systemImage: "square.grid.3x3")
                }
            }

            Section("隐私") {
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("隐私与锁定", systemImage: "lock.shield")
                }
                NavigationLink {
                    CacheManagerView()
                } label: {
                    Label("缓存与存储", systemImage: "internaldrive")
                }
            }

            Section("无障碍") {
                Toggle(isOn: $gesturesEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用上下滑手势")
                        Text("关闭后浏览页底部显示 收藏 / 隐藏 / 移到最近删除 按钮")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
                .accessibilityLabel("启用上下滑手势")
                NavigationLink {
                    GestureTutorialView()
                } label: {
                    Label("手势教学", systemImage: "questionmark.circle")
                }
            }

            Section("关于") {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                }
                LabeledRow(title: "版本", value: "1.0.0 (1)")
                LabeledRow(title: "构建通道", value: "纯本地 · 零上传")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 键值行（设置页通用）
struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Spacer()
            Text(value)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}
