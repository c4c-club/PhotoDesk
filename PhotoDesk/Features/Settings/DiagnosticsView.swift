// MARK: - 职责说明：诊断日志导出页（docs/05 M7 任务 7 / docs/03 §5.9）——
// 装配在 DiagnosticsExporter（docs/16 M12 Phase 1 抽出为可测试纯装配）：
// 读取近 N 小时日志 → 临时文件 → 系统分享面板（保存到「文件」/隔空投送等，仍在本机，不联网）。

import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    enum Hours: Int, CaseIterable, Identifiable {
        case one = 1, four = 4, twentyFour = 24
        var id: Int { rawValue }
        var label: String { rawValue == 1 ? "1 小时" : "\(rawValue) 小时" }
    }

    @State private var hours: Hours = .one
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var logBytes: Int64 = 0

    var body: some View {
        List {
            Section("导出诊断日志") {
                LabeledRow(title: "本机日志占用",
                           value: ByteCountFormatter.string(fromByteCount: logBytes, countStyle: .file))
                Picker("时间范围", selection: $hours) {
                    ForEach(Hours.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                Button {
                    Task { await export() }
                } label: {
                    if isExporting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("导出中…")
                        }
                    } else {
                        Label("导出并分享", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.accentDelete))
                }
                Text("日志仅包含本进程运行信息，导出动作不联网")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .task { logBytes = DiagnosticsExporter.currentLogBytes() }
        .sheet(isPresented: $showShare) {
            if let exportURL {
                ActivityViewWrapper(items: [exportURL], isPresented: $showShare)
            }
        }
    }

    private func export() async {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        guard let url = DiagnosticsExporter.export(hours: hours.rawValue) else {
            errorMessage = "导出失败：无法写入临时文件"
            return
        }
        exportURL = url
        showShare = true
    }
}
