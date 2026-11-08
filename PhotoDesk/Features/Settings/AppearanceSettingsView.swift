// MARK: - 职责说明：外观与网格设置（docs/05 M7 任务 2）——外观（跟随系统/浅色/深色）、
// 网格列数（2–5，立即作用于网格且记忆）、默认排序、iCloud 自动下载原件。
// 网格列数经 LibraryContainer 的 @AppStorage("grid.columns") 双向绑定即时生效。

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = "system"
    @AppStorage("grid.columns") private var gridColumns = 3
    @AppStorage("grid.sortAsc") private var sortAscending = false
    @AppStorage("icloud.autoDownload") private var autoDownloadOriginal = false
    /// 位置记忆总开关（docs/09 D08；与 LibraryPositionStore.isEnabled 同源）
    @AppStorage("library.rememberPosition") private var rememberPosition = true
    @State private var clearConfirmation = false

    var body: some View {
        List {
            Section("外观") {
                Picker("外观", selection: $appearanceRaw) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("照片网格") {
                Stepper("网格列数：\(gridColumns) 列", value: $gridColumns, in: 2...5)
                    .onChange(of: gridColumns) { _ in
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                Toggle("按时间正序排列", isOn: $sortAscending)
            }

            Section {
                Toggle(isOn: $rememberPosition) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记住上次整理位置")
                        Text("回到照片库时自动滚到上次浏览的位置（按筛选分别记忆）")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
                Button(role: .destructive) {
                    clearConfirmation = true
                } label: {
                    Text("清除位置记忆")
                }
                .accessibilityIdentifier("Settings-Clear-Position")
            } footer: {
                Text("位置记忆只存在本机文件（Application Support），按当前视图与筛选组合分别保存。")
            }

            Section("iCloud") {
                Toggle(isOn: $autoDownloadOriginal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动下载原件")
                        Text("浏览 iCloud 照片时自动下载原图（会消耗流量）")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("外观与网格")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除位置记忆？", isPresented: $clearConfirmation) {
            Button("清除", role: .destructive) {
                AppContainer.shared.positionStore.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有视图的「上次整理位置」都会被清除，下次回到照片库从顶部开始。")
        }
    }
}
