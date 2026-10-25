// MARK: - 职责说明：沙盒撤销保险副本（docs/03 §5.1 / 红线 1）★——
// 「移到最近删除」执行前必先落副本：requestContentEditingInput 拿原件（视频经 AVAssetExportSession 导出）
// → 拷入 ApplicationSupport/_Trash/<uuid>.<ext> → Core Data TrashItem 索引。
// 撤销：PHAssetCreationRequest.fromImage/fromVideo 重建并回写 creationDate / location（docs/02 §3.5）。
// 定位澄清：副本是「撤销保险」不是备份——真正兜底是系统「最近删除」30 天；设置可整体关闭（关闭后撤销窗口内不提供恢复）。
// 容量淘汰走 PhotoDeskCore.TrashPolicy 纯逻辑（上限默认 2GB，设置 trash.limitMB 可调）；原件获取失败（iCloud 未下载）
// → .needsDownload，调用方必须拒绝删除并提示「请先下载原件」。

import AVFoundation
import CoreData
import Foundation
import Photos
import PhotoDeskCore
import UniformTypeIdentifiers

/// 副本流程错误
enum TrashError: LocalizedError {
    /// iCloud 原件未下载——调用方必须拒绝执行删除
    case needsDownload
    case exportFailed
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .needsDownload: return "这张照片存储在 iCloud，请先下载原件"
        case .exportFailed:  return "原件副本导出失败"
        case .recordNotFound: return "撤销副本不存在（可能已被容量淘汰）"
        }
    }
}

/// 副本元数据（metaJSON 编解码；恢复 creationDate / GPS 用）
struct TrashMeta: Codable, Equatable {
    var creationDate: Date?
    var latitude: Double?
    var longitude: Double?
    var pixelWidth: Int
    var pixelHeight: Int
    var utType: String?
}

/// 一条副本记录（内存视图，对应 Core Data TrashItem）
struct TrashRecord: Identifiable, Equatable {
    let id: UUID
    let originLocalID: String
    let fileRelativePath: String
    let mediaType: Int16     // 0 image / 1 video（PHAssetMediaType.rawValue）
    let byteSize: Int64
    let meta: TrashMeta
    let createdAt: Date
}

@MainActor
final class TrashBin {
    private let persistence: PersistenceController
    private let settings: SettingsStore
    /// 容量上限（测试可注入小值；生产跟随设置 trash.limitMB）
    private let limitBytesOverride: Int64?

    private let fileManager = FileManager.default
    var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("_Trash", isDirectory: true)
    }

    /// 副本开关关闭时拒绝落副本（调用方直接删除，撤销窗口内不提供恢复，docs/04 §3.4）
    var isSafetyCopyEnabled: Bool { settings.safetyCopyEnabled }

    init(persistence: PersistenceController,
         settings: SettingsStore,
         limitBytesOverride: Int64? = nil) {
        self.persistence = persistence
        self.settings = settings
        self.limitBytesOverride = limitBytesOverride
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var limitBytes: Int64 {
        limitBytesOverride ?? Int64(settings.trashLimitMB) * 1024 * 1024
    }

    // MARK: - 落副本（删除前必调）

    /// 拉取原件 → 拷贝入沙盒 → 写 TrashItem 索引 → 容量淘汰
    /// - Throws: TrashError.needsDownload（iCloud 原件未下载——必须拒绝删除）
    func storeCopy(forAssetID assetID: String) async throws -> TrashRecord {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { throw TrashError.recordNotFound }
        let isVideo = asset.mediaType == .video

        let sourceURL = try await (isVideo ? exportVideoURL(asset) : originalImageURL(asset))
        guard let sourceURL else { throw TrashError.needsDownload }

        let recordID = UUID()
        let ext = sourceURL.pathExtension.isEmpty
            ? (isVideo ? "mov" : "jpg")
            : sourceURL.pathExtension
        let destURL = directory.appendingPathComponent("\(recordID.uuidString).\(ext)")

        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw TrashError.exportFailed
        }

        let byteSize = (try? fileManager.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
        let meta = TrashMeta(creationDate: asset.creationDate,
                             latitude: asset.location?.coordinate.latitude,
                             longitude: asset.location?.coordinate.longitude,
                             pixelWidth: asset.pixelWidth,
                             pixelHeight: asset.pixelHeight,
                             utType: isVideo ? UTType.quickTimeMovie.identifier : UTType.jpeg.identifier)
        let record = TrashRecord(id: recordID,
                                 originLocalID: assetID,
                                 fileRelativePath: destURL.lastPathComponent,
                                 mediaType: Int16(asset.mediaType.rawValue),
                                 byteSize: byteSize ?? 0,
                                 meta: meta,
                                 createdAt: Date())
        upsert(record)
        await evictIfNeeded()
        return record
    }

    // MARK: - 撤销重建（Toast「撤销」）

    /// 从副本重建照片并回写 creationDate / location → 返回新 localIdentifier（旧 id 已随删除失效）
    func restore(recordID: UUID) async throws -> String {
        guard let record = record(id: recordID) else { throw TrashError.recordNotFound }
        let url = directory.appendingPathComponent(record.fileRelativePath)
        guard fileManager.fileExists(atPath: url.path) else { throw TrashError.recordNotFound }

        let meta = record.meta
        let isVideo = record.mediaType == PHAssetMediaType.video.rawValue
        final class NewIDBox: @unchecked Sendable { var id: String? }
        let box = NewIDBox()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            PHPhotoLibrary.shared().performChanges {
                // PHAssetCreationRequest 必须在 performChanges 内创建（placeholder 由此产生）
                let request: PHAssetCreationRequest?
                if isVideo {
                    request = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    request = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
                guard let request, let placeholder = request.placeholderForCreatedAsset else { return }
                request.creationDate = meta.creationDate
                if let latitude = meta.latitude, let longitude = meta.longitude {
                    request.location = CLLocation(latitude: latitude, longitude: longitude)
                }
                box.id = placeholder.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success, let id = box.id {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: TrashError.exportFailed)
                }
            }
        }
        // 副本保留（容量淘汰兜底），支持再次恢复场景
    }

    // MARK: - 索引存取

    func record(id: UUID) -> TrashRecord? {
        var found: TrashRecord?
        persistence.container.viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TrashItem")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let object = try? persistence.container.viewContext.fetch(request).first {
                found = Self.record(from: object)
            }
        }
        return found
    }

    func allRecords() -> [TrashRecord] {
        var result: [TrashRecord] = []
        persistence.container.viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TrashItem")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let objects = (try? persistence.container.viewContext.fetch(request)) ?? []
            result = objects.map(Self.record(from:))
        }
        return result
    }

    func upsert(_ record: TrashRecord) {
        persistence.performBackground { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: "TrashItem", into: context)
            object.setValue(record.id, forKey: "id")
            object.setValue(record.originLocalID, forKey: "originLocalID")
            object.setValue(record.fileRelativePath, forKey: "fileRelativePath")
            object.setValue(record.mediaType, forKey: "mediaType")
            object.setValue(record.byteSize, forKey: "byteSize")
            if let data = try? JSONEncoder().encode(record.meta),
               let json = String(data: data, encoding: .utf8) {
                object.setValue(json, forKey: "metaJSON")
            }
            object.setValue(record.createdAt, forKey: "createdAt")
            try? context.save()
        }
    }

    private func deleteRow(id: UUID) {
        persistence.performBackground { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "TrashItem")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            (try? context.fetch(request))?.forEach { context.delete($0) }
            try? context.save()
        }
    }

    // MARK: - 容量淘汰（PhotoDeskCore.TrashPolicy 纯逻辑）

    func evictIfNeeded() async {
        let records = allRecords()
        guard !records.isEmpty else { return }
        // 纯逻辑在 PhotoDeskCore.TrashPolicy（红线 2）：App 侧只做记录映射与文件/索引清理
        let coreRecords = records.map {
            PhotoDeskCore.TrashRecord(id: $0.id, byteSize: $0.byteSize, createdAt: $0.createdAt)
        }
        let candidates = TrashPolicy.evictionCandidates(from: coreRecords, limitBytes: limitBytes)
        for id in candidates {
            if let record = records.first(where: { $0.id == id }) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(record.fileRelativePath))
                deleteRow(id: id)
            }
        }
    }

    /// 删除记录 + 文件（撤销副本过期清理，M7 接设置页）
    func purge(id: UUID) {
        if let record = record(id: id) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(record.fileRelativePath))
        }
        deleteRow(id: id)
    }

    // MARK: - 原件获取

    /// 图片：requestContentEditingInput（禁网络——拿不到 URL 即 iCloud 未下载）
    private func originalImageURL(_ asset: PHAsset) async throws -> URL? {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input?.fullSizeImageURL)
            }
        }
    }

    /// 视频：AVAssetExportSession 导出（docs/05 M3 任务；副本格式统一 mov）
    private func exportVideoURL(_ asset: PHAsset) async throws -> URL? {
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
        guard let avAsset else { return nil }   // iCloud 未下载

        let session = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality)
        guard let session else { throw TrashError.exportFailed }
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("trash-export-\(UUID().uuidString).mov")
        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = true
        try? fileManager.removeItem(at: outputURL)

        if #available(iOS 16.0, *) {
            // SDK 仅有无参 async export（使用上方已配置的 outputURL / outputFileType）
            try await session.export()
            return outputURL
        } else {
            // iOS 15 回退：exportAsynchronously + 状态检查
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
            guard session.status == .completed else { throw TrashError.exportFailed }
            return outputURL
        }
    }

    // MARK: - Core Data 行 → 记录

    private nonisolated static func record(from object: NSManagedObject) -> TrashRecord {
        let metaJSON = object.value(forKey: "metaJSON") as? String ?? "{}"
        let meta = (metaJSON.data(using: .utf8)).flatMap { try? JSONDecoder().decode(TrashMeta.self, from: $0) }
            ?? TrashMeta(creationDate: nil, latitude: nil, longitude: nil,
                         pixelWidth: 0, pixelHeight: 0, utType: nil)
        return TrashRecord(id: object.value(forKey: "id") as? UUID ?? UUID(),
                           originLocalID: object.value(forKey: "originLocalID") as? String ?? "",
                           fileRelativePath: object.value(forKey: "fileRelativePath") as? String ?? "",
                           mediaType: object.value(forKey: "mediaType") as? Int16 ?? 0,
                           byteSize: object.value(forKey: "byteSize") as? Int64 ?? 0,
                           meta: meta,
                           createdAt: object.value(forKey: "createdAt") as? Date ?? Date())
    }
}
