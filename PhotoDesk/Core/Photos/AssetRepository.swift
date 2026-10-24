// MARK: - 职责说明：照片库分批查询仓库（docs/05 M1 任务 1.2 / AGENTS.md §4.7）——
// prepare(scope:) 建立懒加载 PHFetchResult 并返回总数；fetch(scope:offset:limit:) 只枚举请求窗口（每批 ≤ 500），
// 禁止一次性 enumerateObjects 全库。映射为 PhotoItem（docs/03 §4.1）；PHAsset 访问全部在后台队列。
// protocol 化供 Mock（AGENTS.md §3.2）；主网格 includeHiddenAssets = false（AGENTS.md §4.2）。

import Photos

protocol AssetRepositoryProtocol: AnyObject {
    /// 建立查询并返回总数（后续 fetch 使用同一 fetchResult 切片）
    func prepare(scope: PhotoScope) async -> Int
    /// 分批取窗口 [offset, offset + limit) 内的条目（映射 PhotoItem）
    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem]
    /// 当前 scope 的底层结果（PhotoChangeObserver 监听用）
    var latestResult: PHFetchResult<PHAsset>? { get }
    /// 变更同步：用 objectAfterChanges 替换当前结果（增量，不重建查询）
    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope)
    /// PHAsset → PhotoItem（变更增量时 ViewModel 复用同一映射）
    func map(_ asset: PHAsset) -> PhotoItem
}

final class AssetRepository: AssetRepositoryProtocol {
    /// 每批上限（AGENTS.md §4.7：每批 500）
    static let batchSize = 500

    /// scope → fetchResult（主线程读写；枚举/映射走后台）
    private var results: [PhotoScope: PHFetchResult<PHAsset>] = [:]

    var latestResult: PHFetchResult<PHAsset>? {
        results[.all]
    }

    func prepare(scope: PhotoScope) async -> Int {
        let result = await Task.detached(priority: .userInitiated) {
            Self.makeFetchResult(scope: scope)
        }.value
        results[scope] = result
        return result.count
    }

    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] {
        let result: PHFetchResult<PHAsset>
        if let cached = results[scope] {
            result = cached
        } else {
            result = await Task.detached(priority: .userInitiated) {
                Self.makeFetchResult(scope: scope)
            }.value
            results[scope] = result
        }
        let count = result.count
        guard offset < count, limit > 0 else { return [] }
        let upper = min(offset + limit, count)
        let indexSet = IndexSet(integersIn: offset..<upper)
        return await Task.detached(priority: .userInitiated) { [weak self] in
            let assets = result.objects(at: indexSet)
            return assets.compactMap { self?.map($0) }
        }.value
    }

    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope) {
        results[scope] = result
    }

    // MARK: - 查询构造

    private static func makeFetchResult(scope: PhotoScope) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = false
        // 仅「已隐藏」scope 可见隐藏资源；主网格一律不含隐藏（AGENTS.md §4.2）
        options.includeHiddenAssets = (scope == .hidden)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        switch scope {
        case .all:
            return PHAsset.fetchAssets(with: options)
        case .favorites:
            options.predicate = NSPredicate(format: "isFavorite == YES")
            return PHAsset.fetchAssets(with: options)
        case .hidden:
            options.predicate = NSPredicate(format: "isHidden == YES")
            return PHAsset.fetchAssets(with: options)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            return PHAsset.fetchAssets(with: options)
        case .screenshots:
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            return PHAsset.fetchAssets(with: options)
        case .album(let localIdentifier):
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
                return PHAsset.fetchAssets(with: FALSE_PREDICATE_OPTIONS)
            }
            return PHAsset.fetchAssets(in: collection, options: options)
        case .smartAlbum(let subtype):
            guard let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil).firstObject else {
                return PHAsset.fetchAssets(with: FALSE_PREDICATE_OPTIONS)
            }
            return PHAsset.fetchAssets(in: collection, options: options)
        case .recentlyDeleted:
            // iOS 无公开 API 枚举「最近删除」资源（docs/02 §3.5）；M3 提供「最近删除」只读入口时按
            // smartAlbum 回退实现。当前返回空集，不视为错误。
            return PHAsset.fetchAssets(with: FALSE_PREDICATE_OPTIONS)
        case .search:
            // TODO(P5): 随筛选维度实现 SearchPredicate → NSPredicate
            return PHAsset.fetchAssets(with: FALSE_PREDICATE_OPTIONS)
        }
    }

    private static let FALSE_PREDICATE_OPTIONS: PHFetchOptions = {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "FALSEPREDICATE")
        return options
    }()

    // MARK: - PHAsset → PhotoItem（docs/03 §4.1）

    func map(_ asset: PHAsset) -> PhotoItem {        PhotoItem(
            id: asset.localIdentifier,
            mediaType: mapMediaType(asset.mediaType),
            mediaSubtypes: mapSubtypes(asset.mediaSubtypes),
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            location: asset.location,
            burstIdentifier: asset.burstIdentifier,
            isCloudOnly: Self.isCloudOnly(asset)
        )
    }

    private func mapMediaType(_ type: PHAssetMediaType) -> MediaType {
        switch type {
        case .image: return .image
        case .video: return .video
        default:     return .unknown
        }
    }

    private func mapSubtypes(_ subtypes: PHAssetMediaSubtypes) -> MediaSubtypes {
        var result: MediaSubtypes = []
        if subtypes.contains(.photoScreenshot) { result.insert(.photoScreenshot) }
        if subtypes.contains(.photoLive)       { result.insert(.photoLive) }
        if subtypes.contains(.photoHDR)        { result.insert(.photoHDR) }
        if subtypes.contains(.videoSlowMo)     { result.insert(.videoSlowMo) }
        if subtypes.contains(.videoTimelapse)  { result.insert(.videoTimelapse) }
        return result
    }

    /// iCloud-only 判定：KVC "locallyAvailable"（非公开键，失败回退 false）。
    /// M2 以 requestImage 失败 + PHImageResultIsInCloudKey 兜底（docs/03 §5.8）。
    private static func isCloudOnly(_ asset: PHAsset) -> Bool {
        (asset.value(forKey: "locallyAvailable") as? Bool) == false
    }
}
