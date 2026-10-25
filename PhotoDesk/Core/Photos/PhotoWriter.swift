// MARK: - 职责说明：PhotoKit 写操作封装（docs/05 M3 任务 3.1，M2 先落收藏/隐藏）——
// 所有写操作必须在 PHPhotoLibrary.shared().performChanges 内并处理 completionHandler 错误（AGENTS.md §4.1）。
// 红线 1：deleteAssets 是全应用唯一删除实现（移入系统「最近删除」30 天）；M3 将在 TrashBin 保险副本落盘后
// 才允许经本类调用，调用方必须先走副本流程，不得绕过。

import Photos

@MainActor
final class PhotoWriter {
    enum PhotoWriterError: LocalizedError {
        case changeRejected
        var errorDescription: String? { "照片库写入被系统拒绝，请检查照片访问权限" }
    }

    nonisolated init() {}

    /// 批量收藏 / 取消收藏
    func setFavorite(ids: [String], isFavorite: Bool) async throws {
        try await perform(ids: ids) { assets in
            for index in 0..<assets.count {
                PHAssetChangeRequest(for: assets.object(at: index)).isFavorite = isFavorite
            }
        }
    }

    /// 批量隐藏 / 取消隐藏（PHAssetChangeRequest.isHidden 为公开 API，iOS 8+，docs/02 §3.4 方案 A）
    func setHidden(ids: [String], isHidden: Bool) async throws {
        try await perform(ids: ids) { assets in
            for index in 0..<assets.count {
                PHAssetChangeRequest(for: assets.object(at: index)).isHidden = isHidden
            }
        }
    }

    /// 移到系统「最近删除」——红线 1 唯一删除实现。
    /// ⚠️ 调用前置条件（M3 落地）：必须先经 TrashBin 落撤销保险副本；iCloud-only 未下载原件时拒绝执行。
    func deleteAssets(ids: [String]) async throws {
        try await perform(ids: ids) { assets in
            let targets = (0..<assets.count).map { assets.object(at: $0) }
            guard !targets.isEmpty else { return }
            PHAssetChangeRequest.deleteAssets(targets as NSArray)
        }
    }

    // MARK: - performChanges → async 适配

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
}
