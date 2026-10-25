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
