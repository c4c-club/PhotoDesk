// MARK: - 职责说明：照片库分批查询仓库（docs/05 M1 任务 1.2 / AGENTS.md §4.7）——
// prepare(scope:) 建立懒加载 PHFetchResult 并返回总数；fetch(scope:offset:limit:) 只枚举请求窗口（每批 ≤ 500），
// 禁止一次性 enumerateObjects 全库。映射为 PhotoItem（docs/03 §4.1）；PHAsset 枚举/映射走后台（detached Task）。
// @MainActor：results 字典只在主线程读写（曾存在跨线程读写竞态）；重活全部下沉后台，不在主线程枚举资产。
// protocol 化供 Mock（AGENTS.md §3.2）；主网格 includeHiddenAssets = false（AGENTS.md §4.2）。

import Photos

@MainActor
protocol AssetRepositoryProtocol: AnyObject {
    /// 建立查询并返回总数（后续 fetch 使用同一 fetchResult 切片）
    func prepare(scope: PhotoScope) async -> Int
    /// 建立查询并返回总数（docs/09 Phase 1：sortAscending 下推到 PHFetchOptions，升/降序由 LibraryQuery 决定）
    func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int
    /// 分批取窗口 [offset, offset + limit) 内的条目（映射 PhotoItem）
    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem]
    /// 锚点 assetID 在完整结果中的全局 index（docs/16 M12 R03 锚点窗口用；找不到返回 nil）
    func globalIndex(of assetID: String, scope: PhotoScope) async -> Int?
    /// 按 id 批量取（Vault 合并待隐藏项用；docs/09 D05）
    func fetch(ids: [String]) async -> [PhotoItem]
    /// 当前 scope 的底层结果（PhotoChangeObserver 监听用）
    var latestResult: PHFetchResult<PHAsset>? { get }
    /// 指定 scope 的底层结果（query-driven 模式下监听非 .all 范围，docs/09 Phase 1）
    func latestResult(for scope: PhotoScope) -> PHFetchResult<PHAsset>?
    /// 变更同步：用 fetchResultAfterChanges 替换当前结果（增量，不重建查询）
    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope)
    /// PHAsset → PhotoItem（变更增量时 ViewModel 复用同一映射）
    func map(_ asset: PHAsset) -> PhotoItem
}

@MainActor
final class AssetRepository: AssetRepositoryProtocol {
    /// 每批上限（AGENTS.md §4.7：每批 500）
    static let batchSize = 500

    /// scope → fetchResult（仅主线程读写；重枚举走 detached）
    private var results: [PhotoScope: PHFetchResult<PHAsset>] = [:]

    nonisolated init() {}

    var latestResult: PHFetchResult<PHAsset>? {
        results[.all]
    }

    func latestResult(for scope: PhotoScope) -> PHFetchResult<PHAsset>? {
        results[scope]
    }

    func prepare(scope: PhotoScope) async -> Int {
        await prepare(scope: scope, sortAscending: false)
    }

    func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int {
        let result = await Self.makeResultInBackground(scope: scope, sortAscending: sortAscending)
        results[scope] = result
        return result.count
    }

    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] {
        let result: PHFetchResult<PHAsset>
        if let cached = results[scope] {
            result = cached
        } else {
            result = await Self.makeResultInBackground(scope: scope, sortAscending: false)
            results[scope] = result
        }
        let count = result.count
        guard offset < count, limit > 0 else { return [] }
        let upper = min(offset + limit, count)
        let indexSet = IndexSet(integersIn: offset..<upper)
        let repository = self
        return await Task.detached(priority: .userInitiated) {
            // map 为 nonisolated 纯映射：PHAsset 属性读取线程安全，无需回主线程
            result.objects(at: indexSet).map { repository.map($0) }
        }.value
    }

    /// M12 脚手架：恒 nil（基线行为——无锚点定位能力）→ 锚点窗口断言红锚点
    func globalIndex(of assetID: String, scope: PhotoScope) async -> Int? { nil }

    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope) {
        results[scope] = result
    }

    func fetch(ids: [String]) async -> [PhotoItem] {
        guard !ids.isEmpty else { return [] }
        let repository = self
        return await Task.detached(priority: .userInitiated) { () -> [PhotoItem] in
            let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            return (0..<result.count).map { repository.map(result.object(at: $0)) }
        }.value
    }

    // MARK: - 后台重活（不触碰 results）

    private nonisolated static func makeResultInBackground(scope: PhotoScope,
                                                           sortAscending: Bool) async -> PHFetchResult<PHAsset> {
        await Task.detached(priority: .userInitiated) {
            Self.makeFetchResult(scope: scope, sortAscending: sortAscending)
        }.value
    }

    // MARK: - 查询构造（后台线程调用）

    nonisolated private static func makeFetchResult(scope: PhotoScope,
                                                    sortAscending: Bool) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = false
        // 仅「已隐藏」scope 可见隐藏资源；主网格一律不含隐藏（AGENTS.md §4.2）
        options.includeHiddenAssets = (scope == .hidden)
        // 排序下推（docs/09 Phase 1：LibraryQuery.sortAscending → PHFetchOptions）
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: sortAscending)]

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
            // search 维度不走 PhotoKit fetch：M5 起搜索/筛选在已加载快照上用
            // PhotoFilter 纯函数执行（SearchViewModel），此 case 仅为作用域枚举完整性回退空集。
            return PHAsset.fetchAssets(with: FALSE_PREDICATE_OPTIONS)
        }
    }

    private nonisolated static let FALSE_PREDICATE_OPTIONS: PHFetchOptions = {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "FALSEPREDICATE")
        return options
    }()

    // MARK: - PHAsset → PhotoItem（docs/03 §4.1；nonisolated 纯映射，主线程/后台均可调用）

    nonisolated func map(_ asset: PHAsset) -> PhotoItem {
        PhotoItem(
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

    nonisolated private func mapMediaType(_ type: PHAssetMediaType) -> MediaType {
        switch type {
        case .image: return .image
        case .video: return .video
        default:     return .unknown
        }
    }

    nonisolated private func mapSubtypes(_ subtypes: PHAssetMediaSubtype) -> MediaSubtypes {
        var result: MediaSubtypes = []
        if subtypes.contains(.photoScreenshot) { result.insert(.photoScreenshot) }
        if subtypes.contains(.photoLive)       { result.insert(.photoLive) }
        if subtypes.contains(.photoHDR)        { result.insert(.photoHDR) }
        if subtypes.contains(.photoDepthEffect) { result.insert(.photoDepthEffect) }
        if subtypes.contains(.photoPanorama)   { result.insert(.photoPanorama) }
        // PhotoKit 无独立 slow-mo 常量：慢动作即高帧率视频（docs/03 §4.1 的 videoSlowMo 域概念由此映射）
        if subtypes.contains(.videoHighFrameRate) { result.insert(.videoSlowMo) }
        if subtypes.contains(.videoTimelapse)  { result.insert(.videoTimelapse) }
        return result
    }

    /// iCloud-only 判定：M1 一律 false。
    /// 原因：私有 KVC 键（"locallyAvailable"）在 iOS 17.5 模拟器上直接终止进程（CI 实测）；
    /// P2 改由 ImagePipeline 的 requestImage 失败 + PHImageResultIsInCloudKey 判定后回填（docs/03 §5.8）。
    private nonisolated static func isCloudOnly(_ asset: PHAsset) -> Bool {
        false
    }
}
