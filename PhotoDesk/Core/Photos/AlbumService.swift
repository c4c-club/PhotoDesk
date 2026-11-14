// MARK: - 职责说明：相簿列表服务（M17 T08 X01/X02，docs/31 §3）——
// PHAssetCollection 查询/计数/封面全部收口于此（AGENTS §3.1：Feature 层零 PhotoKit 类型）。
// 主线程零枚举（服务队列）；计数读 fetchResult.count 不逐个加载对象；封面 fetchLimit 1；
// PHPhotoLibraryChangeObserver 增量刷新（X01：新增/删除相簿、加入照片后列表自动更新）。

import Foundation
import Photos

/// 相簿列表口径（Feature 层唯一消费枚举；不含 PhotoKit 类型）
enum AlbumListKind {
    case user      // 用户相簿
    case smart     // 智能相簿
}

/// 相簿摘要（Feature 层唯一消费类型；零 PhotoKit 类型）
struct AlbumSummary: Identifiable, Equatable {
    let id: String       // localIdentifier
    let title: String
    let count: Int
    /// 相簿首张照片的 assetID（封面缩略图；空相簿为 nil）
    var coverAssetID: String?
}

protocol AlbumServiceProtocol: AnyObject {
    /// 取相簿摘要（后台枚举，主线程零查询）
    func summaries(kind: AlbumListKind) async -> [AlbumSummary]
    /// 库变化回调（PhotoKit 变更监听桥接；主线程交付）
    var onLibraryChanged: (() -> Void)? { get set }
}

final class AlbumService: NSObject, AlbumServiceProtocol {
    var onLibraryChanged: (() -> Void)?

    private let queue = DispatchQueue(label: "photosdesk.albumservice", qos: .userInitiated)
    private var observing = false

    /// 注册库变化监听（幂等；AppContainer 持有本服务为 App 生命周期单例）
    func startObservingChanges() {
        guard !observing else { return }
        observing = true
        PHPhotoLibrary.shared().register(self)
    }

    /// 主线程零 PhotoKit 枚举：查询与计数全部在服务队列，结果 async 交付
    func summaries(kind: AlbumListKind) async -> [AlbumSummary] {
        let type: PHAssetCollectionType = (kind == .user) ? .album : .smartAlbum
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.fetchSummaries(type: type) ?? [])
            }
        }
    }

    /// 查询/计数/封面收口。计数读 fetchResult.count（PhotoKit 维护，不加载对象）；
    /// 封面 fetchLimit 1（大相簿免全量枚举）；wantsIncrementalChangeDetails=false 免监听开销。
    private func fetchSummaries(type: PHAssetCollectionType) -> [AlbumSummary] {
        let result = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
        var summaries: [AlbumSummary] = []
        result.enumerateObjects { collection, _, _ in
            let countOptions = PHFetchOptions()
            countOptions.wantsIncrementalChangeDetails = false
            let count = PHAsset.fetchAssets(in: collection, options: countOptions).count
            let firstOptions = PHFetchOptions()
            firstOptions.fetchLimit = 1
            firstOptions.wantsIncrementalChangeDetails = false
            let cover = PHAsset.fetchAssets(in: collection, options: firstOptions).firstObject
            summaries.append(AlbumSummary(id: collection.localIdentifier,
                                          title: collection.localizedTitle ?? "未命名",
                                          count: count,
                                          coverAssetID: cover?.localIdentifier))
        }
        return summaries
    }
}

extension AlbumService: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.onLibraryChanged?()
        }
    }
}