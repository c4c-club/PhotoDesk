// MARK: - 职责说明：缓存与存储管理（docs/05 M7 任务 4）——显示磁盘缩略图缓存与撤销保险副本占用，
// 一键清理；内存缓存为 NSCache 自动管理（低内存自动回收，仅显示上限口径）。

import SwiftUI

struct CacheManagerView: View {
    @State private var diskBytes: Int64 = 0
    @State private var trashBytes: Int64 = 0
    @State private var trashCount = 0
    @State private var isClearing = false
    @State private var showClearConfirmation = false
    @State private var clearTrashInstead = false
    @State private var releasedMessage: String?

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        List {
            Section("内存缓存") {
                LabeledRow(title: "缩略图内存缓存", value: "自动管理（上限 60 MB）")
                Text("系统在内存紧张时自动回收，无需手动清理")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }

            Section("磁盘缓存") {
                LabeledRow(title: "缩略图磁盘缓存",
                           value: Self.byteFormatter.string(fromByteCount: diskBytes))
                Text("LRU 淘汰，上限 200 MB")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Button("清理磁盘缓存") {
                    clearTrashInstead = false
                    showClearConfirmation = true
                }
                .disabled(isClearing)
                .accessibilityIdentifier("Cache-Clear-Disk")
            }

            Section("撤销保险副本") {
                LabeledRow(title: "沙盒副本占用",
                           value: Self.byteFormatter.string(fromByteCount: trashBytes))
                LabeledRow(title: "副本条目", value: "\(trashCount) 项")
                Text("仅用于撤销窗口内恢复；清理后只能通过系统「最近删除」找回照片")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Button("清空撤销副本") {
                    clearTrashInstead = true
                    showClearConfirmation = true
                }
                .disabled(isClearing)
                .accessibilityIdentifier("Cache-Purge-Trash")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("缓存与存储")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .confirmationDialog(clearTrashInstead ? "清空撤销副本？" : "清理磁盘缓存？",
                            isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            if clearTrashInstead {
                Button("清空撤销副本", role: .destructive) { Task { await purgeTrash() } }
            } else {
                Button("清理磁盘缓存", role: .destructive) { clearDiskCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(clearTrashInstead
                 ? "清理后只能通过系统「最近删除」找回照片，确定继续？"
                 : "将删除本机缩略图缓存，不影响照片原件。")
        }
        .alert("清理完成", isPresented: Binding(
            get: { releasedMessage != nil },
            set: { if !$0 { releasedMessage = nil } }
        )) {
            Button("好", role: .cancel) { releasedMessage = nil }
        } message: {
            Text(releasedMessage ?? "")
        }
    }

    private func clearDiskCache() {
        let before = diskBytes
        isClearing = true
        AppContainer.shared.imagePipeline.clearCaches()
        Task {
            await reload()
            let freed = max(0, before - diskBytes)
            releasedMessage = "已释放 \(Self.byteFormatter.string(fromByteCount: freed))"
        }
    }

    private func reload() async {
        let container = AppContainer.shared
        diskBytes = await container.imagePipeline.diskCacheBytes
        let records = await container.trashBin.allRecords()
        trashBytes = records.reduce(0) { $0 + $1.byteSize }
        trashCount = records.count
        isClearing = false
    }

    private func purgeTrash() async {
        await AppContainer.shared.trashBin.purgeAll()
        await reload()
    }
}
