// MARK: - 职责说明：诊断日志导出（docs/05 M7 任务 7 / docs/03 §5.9）——
// OSLogStore(scope: .currentProcessIdentifier)（iOS 15 可用）读取近 N 小时日志 →
// 临时文件 → 系统分享面板（保存到「文件」/隔空投送等，仍在本机）。

import SwiftUI
import OSLog
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

    var body: some View {
        List {
            Section("导出诊断日志") {
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

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-Double(hours.rawValue) * 3600))
            let entries = try store.getEntries(at: position)
            var lines: [String] = ["PhotoDesk 诊断日志 — \(Date())"]
            var count = 0
            for entry in entries {
                lines.append("\(entry.date) \(entry.composeMessage())")
                count += 1
                if count > 5_000 { break }   // 防超大文件
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoDesk-diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
            try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
            exportURL = url
            showShare = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}
