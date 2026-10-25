// MARK: - 职责说明：PhotoKit 写操作封装（docs/05 M3 任务 3.1）——
// 所有写操作必须在 PHPhotoLibrary.shared().performChanges 内并处理 completionHandler 错误（AGENTS.md §4.1）。
// 红线 1：moveToRecentlyDeleted 是全应用唯一删除实现（移入系统「最近删除」，30 天后由系统自动清除，
// 本方法不执行永久擦除）；M3 起调用前置条件 = TrashBin 保险副本已落盘（iCloud-only 未下载原件时拒绝）。
// protocol 化供 Mock（AGENTS.md §3.2）。

import Photos

@MainActor
protocol PhotoWriterProtocol: AnyObject {
    func setFavorite(ids: [String], isFavorite: Bool) async throws
    func setHidden(ids: [String], isHidden: Bool) async throws
    func moveToRecentlyDeleted(ids: [String]) async throws
    func createAlbum(title: String) async throws -> String
    func renameAlbum(localID: String, to title: String) async throws
    func deleteAlbum(localID: String) async throws
    func add(ids: [String], toAlbum albumID: String) async throws
    func remove(ids: [String], fromAlbum albumID: String) async throws
    /// 编辑结果另存为新照片（docs/05 M6 任务 6.1，默认另存不破坏原图）→ 新 localIdentifier
    func saveNewImage(fromFile fileURL: URL, creationDate: Date?) async throws -> String
    /// 编辑结果覆盖原件（PHContentEditingOutput，系统保留可还原；docs/05 M6 任务 6.1）
    func overwriteWithAdjustment(assetID: String, adjustmentData: Data,
                                 render: @escaping (URL) async throws -> Void) async throws
    /// 还原到原始状态（清除本 App 的编辑调整；系统「最近删除」语义不受影响）
    func revertToOriginal(assetID: String) async throws
    /// 分享用原件 URL（iCloud 自动下载；fullSizeImageURL）
    func requestInputURL(assetID: String) async throws -> URL
}

@MainActor
final class PhotoWriter: PhotoWriterProtocol {
    enum PhotoWriterError: LocalizedError {
        case changeRejected
        case albumNotFound
        var errorDescription: String? {
            switch self {
            case .changeRejected: return "照片库写入被系统拒绝，请检查照片访问权限"
            case .albumNotFound:  return "目标相簿不存在或已被删除"
            }
        }
    }

    nonisolated init() {}

    // MARK: - 资源级操作

    /// 批量收藏 / 取消收藏
    func setFavorite(ids: [String], isFavorite: Bool) async throws {
        try await perform(ids: ids) { assets in
            for index in 0..<assets.count {
                PHAssetChangeRequest(for: assets.object(at: index)).isFavorite = isFavorite
            }
        }
    }

    /// 批量隐藏 / 取消隐藏（PHAssetChangeRequest.isHidden 公开 API，iOS 8+，docs/02 §3.4 方案 A）
    func setHidden(ids: [String], isHidden: Bool) async throws {
        try await perform(ids: ids) { assets in
            for index in 0..<assets.count {
                PHAssetChangeRequest(for: assets.object(at: index)).isHidden = isHidden
            }
        }
    }

    /// 移到系统「最近删除」——红线 1 唯一删除实现。
    /// 移入系统最近删除，30 天后由系统自动清除，本方法不执行永久擦除。
    /// 调用前置条件（TrashBin 负责保证）：撤销保险副本已落盘；iCloud-only 未下载原件时不得调用。
    func moveToRecentlyDeleted(ids: [String]) async throws {
        try await perform(ids: ids) { assets in
            let targets = (0..<assets.count).map { assets.object(at: $0) }
            guard !targets.isEmpty else { return }
            PHAssetChangeRequest.deleteAssets(targets as NSArray)
        }
    }

    // MARK: - 相簿操作

    /// 新建用户相簿，返回 localIdentifier
    func createAlbum(title: String) async throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PhotoWriterError.changeRejected }
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: trimmed)
                _ = request.placeholderForCreatedAssetCollection
            } completionHandler: { success, error in
                // placeholder 的 localIdentifier 需在 performChanges 内捕获；completion 后经标题查回
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    Task { @MainActor in
                        let collections = PHAssetCollection.fetchAssetCollections(with: .album,
                                                                                  subtype: .any,
                                                                                  options: nil)
                        var found = ""
                        collections.enumerateObjects { collection, _, _ in
                            if found.isEmpty, collection.localizedTitle == trimmed {
                                found = collection.localIdentifier
                            }
                        }
                        if found.isEmpty {
                            continuation.resume(throwing: PhotoWriterError.changeRejected)
                        } else {
                            continuation.resume(returning: found)
                        }
                    }
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    func renameAlbum(localID: String, to title: String) async throws {
        let collection = try await self.collection(localID: localID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.title = title
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    /// 删除相簿（系统相簿不可删除，PhotoKit 会拒绝；本方法只删用户相簿）
    func deleteAlbum(localID: String) async throws {
        let collection = try await self.collection(localID: localID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    func add(ids: [String], toAlbum albumID: String) async throws {
        let assets = try await self.assets(ids: ids)
        let collection = try await self.collection(localID: albumID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: collection)?.addAssets(assets as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    func remove(ids: [String], fromAlbum albumID: String) async throws {
        let assets = try await self.assets(ids: ids)
        let collection = try await self.collection(localID: albumID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                // 只从相簿移除引用，不删除照片本身（照片仍在照片库）
                PHAssetCollectionChangeRequest(for: collection)?.removeAssets(assets as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    // MARK: - 编辑（M6：另存 / 覆盖 / 还原）

    /// 编辑结果另存为新照片（默认保存方式，不破坏原图）→ 新 localIdentifier
    func saveNewImage(fromFile fileURL: URL, creationDate: Date?) async throws -> String {
        final class IDBox: @unchecked Sendable { var id: String? }
        let box = IDBox()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                request?.creationDate = creationDate
                box.id = request?.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success, let id = box.id {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    /// 编辑结果覆盖原件：PHContentEditingOutput + adjustmentData（系统相册保留「还原」能力，docs/05 M6）
    /// - Parameter render: 在 output.renderedContentURL 写入完整渲染结果（全尺寸像素）
    func overwriteWithAdjustment(assetID: String, adjustmentData: Data,
                                 render: @escaping (URL) async throws -> Void) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { throw PhotoWriterError.albumNotFound }
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                if let input {
                    continuation.resume(returning: input)
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
        guard input.canPerformAdjustment else { throw PhotoWriterError.changeRejected }

        let output = PHContentEditingOutput(contentEditingInput: input)
        try await render(output.renderedContentURL)
        output.adjustmentData = PHAdjustmentData(formatIdentifier: Self.adjustmentFormatIdentifier,
                                                 formatVersion: "1.0",
                                                 data: adjustmentData)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).contentEditingOutput = output
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    /// 还原到原始状态（清除本 App 的编辑调整；不触碰系统「最近删除」语义）
    func revertToOriginal(assetID: String) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { throw PhotoWriterError.albumNotFound }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).revertAssetContentToOriginal()
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    static let adjustmentFormatIdentifier = "com.example.PhotoDesk.editor"

    /// 分享用原件 URL（iCloud 自动下载；fullSizeImageURL）
    func requestInputURL(assetID: String) async throws -> URL {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { throw PhotoWriterError.albumNotFound }
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, info in
                if let input, let url = input.fullSizeImageURL {
                    continuation.resume(returning: input)
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
        guard let url = input.fullSizeImageURL else { throw PhotoWriterError.cannotLoadImage }
        return url
    }

    // MARK: - 私有

    private func perform(ids: [String], change: @escaping (PHFetchResult<PHAsset>) -> Void) async throws {
        guard !ids.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                change(assets)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoWriterError.changeRejected)
                }
            }
        }
    }

    private func collection(localID: String) async throws -> PHAssetCollection {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localID],
                                                                       options: nil).firstObject else {
            throw PhotoWriterError.albumNotFound
        }
        return collection
    }

    private func assets(ids: [String]) async throws -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard result.count > 0 else { throw PhotoWriterError.albumNotFound }
        return (0..<result.count).map { result.object(at: $0) }
    }
}
