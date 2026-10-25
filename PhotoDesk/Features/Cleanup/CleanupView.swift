// MARK: - 职责说明：智能清理页（docs/04 §3.3 / docs/05 M4 任务 4.8）——
// 扫描态：环形进度 + 已扫/总数 + 取消；完成态：五类结果卡片（图标/数量/可省空间）→
// 重复组对比 sheet（★推荐角标 + 一键保留推荐项）→ 待清理清单 → 二次确认（docs/04 §7 文案）→ 批量执行。

import SwiftUI
import Photos
import PhotoDeskCore

struct CleanupView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @ObservedObject var coordinator: ScanCoordinator
    @State private var showGroupSheet = false
    @State private var showConfirm = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Group {
            switch coordinator.phase {
            case .idle:
                idleView
            case .running(let scanned, let total):
                runningView(scanned: scanned, total: total)
            case .cancelled:
                resultView
            case .completed:
                resultView
            case .failed(let message):
                Text("扫描失败：\(message)")
                    .foregroundColor(Color(ds: DSColor.accentDelete))
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("智能清理")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 待机（开始扫描）

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.tint))
            Text("扫描重复照片、截图、大文件与模糊照片")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .padding(.horizontal, 32)
            Button {
                viewModel.startScan()
            } label: {
                Text("开始扫描")
                    .font(.body)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color(ds: DSColor.tint))
                    .foregroundColor(.white)
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 扫描中（环形进度，docs/04 §3.3）

    private func runningView(scanned: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color(ds: DSColor.bgSecondary), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(scanned) / CGFloat(total) : 0)
                    .stroke(Color(ds: DSColor.tint), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(total > 0 ? "\(Int(Double(scanned) / Double(total) * 100))%" : "0%")
                    .font(.title2)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
            }
            .frame(width: 140, height: 140)

            Text("扫描中…  \(scanned) / \(total)")
                .font(.body)
                .foregroundColor(Color(ds: DSColor.textSecondary))

            Button("取消") {
                viewModel.cancelScan()
            }
            .foregroundColor(Color(ds: DSColor.accentDelete))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 结果卡片

    private var resultView: some View {
        List {
            if let summary = summary {
                if !summary.duplicateGroups.isEmpty {
                    Button {
                        showGroupSheet = true
                    } label: {
                        card(icon: "square.on.square", tint: DSColor.accentHide,
                             title: "重复照片",
                             detail: "\(summary.duplicateGroups.count) 组 · \(summary.duplicateGroups.reduce(0) { $0 + $1.members.count - 1 }) 张可清理")
                    }
                }
                if !summary.screenshotIDs.isEmpty {
                    card(icon: "camera.viewfinder", tint: DSColor.accentInfo,
                         title: "屏幕截图",
                         detail: "\(summary.screenshotIDs.count) 张 · \(Self.byteFormatter.string(fromByteCount: summary.screenshotBytes))")
                }
                if !summary.largeFileIDs.isEmpty {
                    card(icon: "arrow.down.doc", tint: DSColor.accentShare,
                         title: "大文件",
                         detail: "\(summary.largeFileIDs.count) 个 · \(Self.byteFormatter.string(fromByteCount: summary.largeFileBytes))")
                }
                if !summary.blurryIDs.isEmpty {
                    card(icon: "camera.metering.unknown", tint: DSColor.accentFavorite,
                         title: "模糊照片",
                         detail: "\(summary.blurryIDs.count) 张 · \(Self.byteFormatter.string(fromByteCount: summary.blurryBytes))")
                }
                if summary.duplicateGroups.isEmpty, summary.screenshotIDs.isEmpty,
                   summary.largeFileIDs.isEmpty, summary.blurryIDs.isEmpty {
                    Text("没有发现可清理的内容")
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }

                // 待清理清单
                if !viewModel.pendingIDs.isEmpty {
                    Section("待清理清单 · \(viewModel.pendingIDs.count) 张") {
                        Button {
                            showConfirm = true
                        } label: {
                            Text("移到最近删除（可在 30 天内恢复）")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                                .background(Color(ds: DSColor.accentDelete))
                                .cornerRadius(DSSpacing.buttonCornerRadius)
                        }
                        .disabled(coordinator.isRunning)
                    }
                }
            }
        }
        .refreshable { viewModel.startScan() }
        .sheet(isPresented: $showGroupSheet) {
            DuplicateGroupsSheet(viewModel: viewModel, groups: summary?.duplicateGroups ?? [])
        }
        .confirmationDialog(
            "移到「最近删除」？",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("移到最近删除", role: .destructive) {
                Task { _ = await viewModel.executePending() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将把 \(viewModel.pendingIDs.count) 张照片移到「最近删除」。照片会在那里保留 30 天，期间随时可以在系统相册恢复，不是永久删除。")
        }
    }

    private var summary: ScanCoordinator.ScanSummary? {
        if case .completed(let summary) = coordinator.phase { return summary }
        if case .cancelled = coordinator.phase { return nil }
        return nil
    }

    private func card(icon: String, tint: UIColor, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color(uiColor: tint))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 重复组对比（docs/04 §3.3：并排卡片 + ★推荐角标）

private struct DuplicateGroupsSheet: View {
    @ObservedObject var viewModel: CleanupViewModel
    let groups: [DuplicateGroup]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    Section("第 \(index + 1) 组 · 距离 \(group.minHammingDistance)") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(group.members, id: \.self) { memberID in
                                    DuplicateThumb(itemID: memberID,
                                                   isRecommended: memberID == group.recommendedKeepID,
                                                   pipeline: AppContainer.shared.imagePipeline)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        Button {
                            viewModel.keepRecommended(in: group)
                            dismiss()
                        } label: {
                            Text("保留推荐项，其余 \(group.members.count - 1) 张加入待清理清单")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("重复照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct DuplicateThumb: View {
    let itemID: String
    let isRecommended: Bool
    let pipeline: ImagePipelineProtocol
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color(ds: DSColor.bgSecondary))
                    }
                }
                .frame(width: 96, height: 96)
                .clipped()
                .cornerRadius(DSSpacing.gridCornerRadius)
                if isRecommended {
                    // ★推荐角标（docs/04 §3.3）
                    Text("★推荐")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(ds: DSColor.accentFavorite))
                        .cornerRadius(4)
                        .offset(x: 2, y: 2)
                }
            }
            if isRecommended {
                Text("建议保留")
                    .font(.system(size: 9))
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
        }
        .task {
            image = await pipeline.thumbnail(for: itemID,
                                             size: CGSize(width: 96, height: 96),
                                             scale: UIScreen.main.scale)
        }
    }
}
