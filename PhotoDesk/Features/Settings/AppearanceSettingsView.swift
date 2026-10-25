// MARK: - 职责说明：外观与网格设置（docs/05 M7 任务 2）——外观（跟随系统/浅色/深色）、
// 网格列数（2–5，立即作用于网格且记忆）、默认排序、iCloud 自动下载原件。
// 网格列数经 LibraryContainer 的 @AppStorage("grid.columns") 双向绑定即时生效。

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = "system"
    @AppStorage("grid.columns") private var gridColumns = 3
    @AppStorage("grid.sortAsc") private var sortAscending = false
    @AppStorage("icloud.autoDownload") private var autoDownloadOriginal = false

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
    }
}
