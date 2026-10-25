// MARK: - 职责说明：导出 ViewModel（docs/05 M6 任务 6.8 / 任务 4）——
// 选项（格式/长边/质量/去 GPS）→ 取原件（iCloud 自动下载，进度经 progressHandler）→
// ExportRenderer 文件渲染 → 保存到相册（PHAssetCreationRequest）或分享（临时 URL → ActivityViewWrapper）。

import Foundation
import PhotoDeskCore
import Photos
import UIKit

final class ExportViewModel: ObservableObject {
    let item: PhotoItem

    @Published var options = PhotoDeskCore.ExportOptions()
    @Published private(set) var isExporting = false
    @Published private(set) var downloadProgress: Double?
    /// 导出结果（分享用临时 URL）
    @Published private(set) var exportedFileURL: URL?
    @Published private(set) var savedToLibrary = false
    @Published var errorMessage: String?

    private let writer: PhotoWriterProtocol
    private let settings: SettingsStore

    init(item: PhotoItem, writer: PhotoWriterProtocol, settings: SettingsStore) {
        self.item = item
        self.writer = writer
        self.settings = settings
    }

    /// 资源是否带 GPS（「默认询问」的判断依据；有 GPS 且未勾选去除时导出前询问）
    var itemLikelyHasGPS: Bool {
        item.location != nil
    }

    /// 取原件 URL（iCloud 自动下载；进度回 downloadProgress）
    func requestSourceURL() async throws -> URL {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
        guard let asset = assets.firstObject else { throw ExportError.cannotLoadImage }

        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        // PHContentEditingInputRequestOptions 的进度回调只有 fraction 一个参数（与 PHImageRequestOptions 的四参不同）
        options.progressHandler = { [weak self] fraction in
            // 先把 weak self 绑定为局部 let（@Sendable 闭包内直接用 self? 的属性赋值会报类型歧义，M3 同款坑）
            guard let weakSelf = self else { return }
            let progress = Double(fraction)
            DispatchQueue.main.async {
                weakSelf.downloadProgress = progress
            }
        }
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, info in
                if let input, input.fullSizeImageURL != nil {
                    continuation.resume(returning: input)
                } else {
                    continuation.resume(throwing: ExportError.cannotLoadImage)
                }
            }
        }
        downloadProgress = nil
        guard let url = input.fullSizeImageURL else { throw ExportError.cannotLoadImage }
        return url
    }

    /// 渲染导出文件（保存与分享共用）
    func renderExportFile() async throws -> URL {
        isExporting = true
        defer { isExporting = false }
        let sourceURL = try await requestSourceURL()
        let url = try ExportRenderer.export(from: sourceURL,
                                            options: options,
                                            transform: nil,
                                            adjustments: nil)
        exportedFileURL = url
        return url
    }

    /// 保存到相册（PHAssetCreationRequest；creationDate 沿用原件）
    func saveToLibrary() async throws {
        let url = try await renderExportFile()
        _ = try await writer.saveNewImage(fromFile: url, creationDate: item.creationDate)
        savedToLibrary = true
    }

    /// 分享前调用（返回临时文件 URL）
    func shareFile() async throws -> URL {
        try await renderExportFile()
    }
}
