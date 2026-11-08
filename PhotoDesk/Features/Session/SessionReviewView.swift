// MARK: - 职责说明：整理回顾面板（docs/09 D16 §2）——滑动暂存的待删除/待隐藏缩略图清单：
// 逐张恢复（零 PhotoKit 写）、「全部移到最近删除」（唯一删除提交入口，一次系统确认）、
// 「全部隐藏」、继续整理（关闭）。提交成功清空队列并回显结果；失败/取消队列保留。

import SwiftUI
import UIKit
import PhotoDeskCore

struct SessionReviewView: View {
    @ObservedObject var session: ReviewSessionController
    let pipeline: ImagePipelineProtocol
    let settings: SettingsStore
    /// 「继续整理」回调（关闭面板回到网格/查看器）
    var onClose: () -> Void

    @State private var resultMessage: String?
    @State private var showRestoreAllConfirmation = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if session.isEmpty {
                    emptyContent
                } else {
                    reviewContent
                }
            }
            .background(Color(ds: DSColor.bgPrimary))
            .navigationTitle("整理回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { onClose() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("继续整理") { onClose() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("SessionReviewRoot")
    }

    // MARK: - 内容

    private var reviewContent: some View {
        List {
            Section {
                HStack {
                    Text("待删除 \(session.pendingDeleteCount) · 待隐藏 \(session.pendingHideCount)")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                    Spacer()
                    if session.isCommitting {
                        ProgressView(value: session.commitProgress)
                            .frame(width: 80)
                    }
                }
                if !session.isEmpty {
                    Button("全部恢复（零系统写入）") {
                        showRestoreAllConfirmation = true
                    }
                    .accessibilityIdentifier("Session-RestoreAll")
                    .confirmationDialog("全部恢复？", isPresented: $showRestoreAllConfirmation,
                                        titleVisibility: .visible) {
                        Button("全部恢复", role: .destructive) { session.restoreAll() }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("将把待删除 \(session.pendingDeleteCount) 张、待隐藏 \(session.pendingHideCount) 张全部放回原处，不产生任何系统写入。")
                    }
                }
            }

            if !session.session.pendingDeleteIDs.isEmpty {
                Section("待删除（移到最近删除后 30 天内可在系统相册恢复）") {
                    thumbnailRows(ids: session.session.pendingDeleteIDs, kind: .delete)
                }
            }

            if !session.session.pendingHideIDs.isEmpty {
                Section("待隐藏（进入系统「已隐藏」相册，不释放空间）") {
                    thumbnailRows(ids: session.session.pendingHideIDs, kind: .hide)
                }
            }

            Section {
                if session.pendingDeleteCount > 0 {
                    Button {
                        Task { await commitDeletes() }
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("全部移到最近删除（\(session.pendingDeleteCount)）")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background(Color(ds: DSColor.accentDelete))
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                    }
                    .disabled(session.isCommitting)
                    .accessibilityIdentifier("SessionReview-CommitDelete")
                }

                if session.pendingHideCount > 0 {
                    Button {
                        Task { await commitHides() }
                    } label: {
                        HStack {
                            Image(systemName: "eye.slash")
                            Text("全部隐藏（\(session.pendingHideCount)）")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background(Color(ds: DSColor.accentHide))
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                    }
                    .disabled(session.isCommitting)
                    .accessibilityIdentifier("SessionReview-CommitHide")
                }

                if session.isCommitting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在提交…（iOS 可能弹一次系统确认）")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }

                if let resultMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Text(resultMessage)
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = resultMessage
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(Color(ds: DSColor.tint))
                        }
                        .accessibilityLabel("复制结果信息（含失败原因）")
                        .accessibilityIdentifier("SessionReview-Copy-Result")
                    }
                }
            } footer: {
                Text("「全部移到最近删除」会触发一次 iOS 系统确认（每批一次，不是每张一次）。取消后内容仍在待删除，不会丢失。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func thumbnailRows(ids: [String], kind: PendingKind) -> some View {
        ForEach(ids, id: \.self) { id in
            HStack(spacing: 12) {
                SessionThumb(itemID: id, pipeline: pipeline)
                Spacer()
                Button("恢复") {
                    session.restore(id: id)
                }
                .font(.subheadline)
                .foregroundColor(Color(ds: DSColor.tint))
                .accessibilityLabel("恢复第 \(ids.firstIndex(of: id).map { $0 + 1 } ?? 0) 项")
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.tint))
            Text("没有待处理的内容")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            if let resultMessage {
                // 提交结果（队列清空后仍回显——docs/09 D16：成功 Toast / 失败保留说明）
                Text(resultMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                    .padding(.horizontal, 24)
            }
            Button("完成") { onClose() }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color(ds: DSColor.tint))
                .foregroundColor(.white)
                .cornerRadius(DSSpacing.buttonCornerRadius)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 提交

    private func commitDeletes() async {
        let result = await session.commitDeletes()
        if result.failed {
            resultMessage = "系统未允许删除，\(session.pendingDeleteCount) 张仍在待删除"
        } else if result.skipped > 0 {
            resultMessage = "已移到系统「最近删除」\(result.committed) 项；\(result.skipped) 项在 iCloud，请先下载原件"
        } else {
            resultMessage = "已移到系统「最近删除」\(result.committed) 项"
        }
    }

    private func commitHides() async {
        let result = await session.commitHides()
        resultMessage = result.failed
            ? "隐藏提交失败，\(session.pendingHideCount) 张仍在待隐藏"
            : "已隐藏到系统「已隐藏」相册 \(result.committed) 项"
    }
}

/// 回顾页缩略图（200×200 像素，经 ImagePipeline，懒加载）
private struct SessionThumb: View {
    let itemID: String
    let pipeline: ImagePipelineProtocol
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(ds: DSColor.bgSecondary))
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .cornerRadius(DSSpacing.gridCornerRadius)
        .task {
            image = await pipeline.thumbnail(for: itemID,
                                             size: CGSize(width: 200, height: 200),
                                             scale: 1)
        }
    }
}
