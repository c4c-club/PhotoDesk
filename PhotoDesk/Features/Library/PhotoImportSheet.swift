// MARK: - 职责说明：空库导入入口（docs/49 T03 §2.4）——PhotosPicker 选图 → Data 落临时文件 →
// PhotoWriter.saveNewImage(fromFile:creationDate:) 写回照片库（写操作走 performChanges，AGENTS §4）；
// 并发 ≤ 2；失败中文提示（无法读取所选照片 / 保存到照片库失败）；成功后依赖 PhotoChangeObserver 增量同步。
// 仅 authorized 空态可达；limited 走「管理可见照片」；denied 不可达。

import SwiftUI
import PhotosUI

struct PhotoImportSheet: View {
    /// 关闭 sheet（完成按钮；导入成功不自动关，用户可继续追加选择）
    var onClose: (() -> Void)? = nil

    @State private var selection: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: DSSpacing.gridSpacing) {
                PhotosPicker(selection: $selection,
                             maxSelectionCount: 30,
                             matching: .images) {
                    Label("选择照片", systemImage: "photo.on.rectangle")
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(ds: DSColor.tint))
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                }
                .disabled(isImporting)
                .accessibilityIdentifier("Photo-Import-Picker")
                if isImporting {
                    ProgressView()
                    Text("正在导入…")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                if let resultMessage {
                    Text(resultMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                Spacer()
            }
            .padding(DSSpacing.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(ds: DSColor.bgPrimary))
            .accessibilityIdentifier("Photo-Import-Sheet")
            .navigationTitle("导入照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { onClose?() }
                        .accessibilityIdentifier("Photo-Import-Done")
                }
            }
            .onChange(of: selection) { items in
                guard !items.isEmpty else { return }
                Task { await importItems(items) }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 导入管线（并发 ≤ 2，docs/49 T03 §2.4）

    private enum ImportOutcome { case success, readFailed, writeFailed }

    private func importItems(_ items: [PhotosPickerItem]) async {
        isImporting = true
        resultMessage = nil
        var succeeded = 0
        var readFailed = 0
        var writeFailed = 0
        let writer = AppContainer.shared.photoWriter
        var cursor = 0
        while cursor < items.count {
            let chunk = Array(items[cursor..<min(cursor + 2, items.count)])
            let outcomes = await withTaskGroup(of: ImportOutcome.self) { group in
                for item in chunk {
                    group.addTask { await Self.importOne(item, writer: writer) }
                }
                var collected: [ImportOutcome] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }
            for outcome in outcomes {
                switch outcome {
                case .success:   succeeded += 1
                case .readFailed: readFailed += 1
                case .writeFailed: writeFailed += 1
                }
            }
            cursor += 2
        }
        var parts: [String] = []
        if succeeded > 0 { parts.append("已导入 \(succeeded) 张") }
        if readFailed > 0 { parts.append("无法读取所选照片 ×\(readFailed)") }
        if writeFailed > 0 { parts.append("保存到照片库失败 ×\(writeFailed)") }
        resultMessage = parts.isEmpty ? nil : parts.joined(separator: "；")
        isImporting = false
        selection = []   // 允许再次选择；空数组走 onChange 早退，不会递归
    }

    /// 单张：Data → 临时文件 → 写回照片库 → 删临时文件（writer 只收文件 URL）
    private static func importOne(_ item: PhotosPickerItem,
                                  writer: PhotoWriterProtocol) async -> ImportOutcome {
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            return .readFailed
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoImport-\(UUID().uuidString).jpg", isDirectory: false)
        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            return .readFailed
        }
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        do {
            _ = try await writer.saveNewImage(fromFile: tmpURL, creationDate: nil)
            return .success
        } catch {
            return .writeFailed
        }
    }
}
