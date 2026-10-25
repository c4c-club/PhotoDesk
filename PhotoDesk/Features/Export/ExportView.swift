// MARK: - 职责说明：导出页（docs/05 M6 任务 6.8）——
// 格式（原图/JPEG/PNG/HEIC）/ 长边（1080/2048/4096/原始）/ 质量滑杆 / 去位置开关；
// 动作：保存到相册 / 分享（ActivityViewWrapper）；iCloud 下载进度；有 GPS 且未勾选去除时导出前询问（默认询问）。

import SwiftUI
import PhotoDeskCore

struct ExportView: View {
    @StateObject private var viewModel: ExportViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showShareSheet = false
    @State private var showGPSAsk = false
    @State private var savedToast = false

    init(viewModel: ExportViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("格式") {
                    Picker("格式", selection: $viewModel.options.format) {
                        ForEach(PhotoDeskCore.ExportOptions.Format.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("尺寸") {
                    Picker("长边", selection: $viewModel.options.longEdge) {
                        ForEach(PhotoDeskCore.ExportOptions.LongEdge.allCases, id: \.self) { edge in
                            Text(edge.displayName).tag(edge)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("质量")
                        Slider(value: $viewModel.options.quality, in: 0.1...1)
                    }
                    .opacity(viewModel.options.format == .png ? 0.4 : 1)   // PNG 无损
                    .disabled(viewModel.options.format == .png)
                }

                Section {
                    Toggle(isOn: $viewModel.options.stripLocation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("去除位置信息")
                            Text("导出文件的 EXIF 不含 GPS")
                                .font(.caption)
                                .foregroundColor(Color(ds: DSColor.textSecondary))
                        }
                    }
                }

                Section {
                    Button {
                        handleSave()
                    } label: {
                        if viewModel.isExporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                if let progress = viewModel.downloadProgress {
                                    Text("下载原件 \(Int(progress * 100))%")
                                } else {
                                    Text("导出中…")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("保存到相册")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.isExporting)

                    Button {
                        Task {
                            await exportAndShare()
                        }
                    } label: {
                        Label("分享…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isExporting)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.accentDelete))
                }
                if viewModel.savedToLibrary {
                    Label("已保存到相册", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.accentAlbum))
                }
            }
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ActivityViewWrapper(items: [url], isPresented: $showShareSheet)
            }
        }
        .confirmationDialog("包含位置信息", isPresented: $showGPSAsk, titleVisibility: .visible) {
            Button("去除位置信息并导出") {
                viewModel.options.stripLocation = true
                Task { await saveToLibrary() }
            }
            Button("保留位置导出") {
                viewModel.options.stripLocation = false
                Task { await saveToLibrary() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这张照片包含位置信息。去除后导出文件的 EXIF 不含 GPS。")
        }
    }

    // MARK: - 动作（默认询问：有 GPS 且未勾选去除 → 先问）

    private func handleSave() {
        if viewModel.itemLikelyHasGPS && !viewModel.options.stripLocation {
            showGPSAsk = true
        } else {
            Task { await saveToLibrary() }
        }
    }

    private func saveToLibrary() async {
        do {
            try await viewModel.saveToLibrary()
            savedToast = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func exportAndShare() async {
        do {
            if viewModel.itemLikelyHasGPS && !viewModel.options.stripLocation {
                showGPSAsk = true
                return
            }
            _ = try await viewModel.shareFile()
            showShareSheet = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
