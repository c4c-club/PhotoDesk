// MARK: - 职责说明：照片库 ViewModel（docs/05 M1 任务 1.4 / docs/03 §4.1 说明）——
// 状态机（未授权/加载中/就绪/空/拒绝/受限）+ 分页加载（每批 500，AGENTS.md §4.7）+
// 变更增量应用（PhotoChangeObserver → items 数组增删改 → 重新分组 → Diffable 快照推送，非整库 reload）。
// @MainActor：@Published 全在主线程更新；VC 经 onSnapshotUpdate 回调拿到数据（不直接跨层读）。

import Foundation
import Photos
import PhotoDeskCore

@MainActor
final class LibraryViewModel: ObservableObject {
    /// 网格视图状态（驱动 DSEmptyState / 引导页 / 网格）
    enum ViewState {
        case notDetermined
        case loading
        case ready
        case empty
        case denied
        case restricted
    }

    // MARK: - 输出

    @Published private(set) var viewState: ViewState = .notDetermined
    @Published private(set) var sections: [MonthSection] = []
    @Published private(set) var itemsBySection: [[PhotoItem]] = []
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isLimitedAccess = false

    /// VC 注册：快照数据推送（主线程）。已在加载完成的 VC 接入时立即重放当前快照——
    /// 否则 VM 先于 VC 完成加载，回调错过唯一一次推送，网格永远空白（CI 实测的根因）。
    func attachSnapshotHandler(_ handler: @escaping ([MonthSection], [[PhotoItem]], Bool) -> Void) {
        onSnapshotUpdate = handler
        if viewState == .ready {
            handler(sections, itemsBySection, false)
        }
    }
    /// VC 注册：调起系统 limited 选择器（需要 VC 锚点）
    var onManageLimitedPhotos: (() -> Void)?

    // MARK: - 依赖

    private let service: PhotoLibraryService
    private let repository: AssetRepositoryProtocol
    private let pipeline: ImagePipelineProtocol
    private let writer: PhotoWriterProtocol
    private let trashBin: TrashBin
    private let undoCenter: UndoCenter
    private let batchSize = AssetRepository.batchSize

    // MARK: - 内部状态

    private var items: [PhotoItem] = []          // 已加载条目（时间倒序，镜像 fetchResult 前缀）
    private var totalCount = 0
    private var changeObserver: PhotoChangeObserver?
    private var hasLoadedOnce = false

    init(service: PhotoLibraryService,
         repository: AssetRepositoryProtocol,
         pipeline: ImagePipelineProtocol,
         writer: PhotoWriterProtocol,
         trashBin: TrashBin,
         undoCenter: UndoCenter) {
        self.service = service
        self.repository = repository
        self.pipeline = pipeline
        self.writer = writer
        self.trashBin = trashBin
        self.undoCenter = undoCenter
    }

    // MARK: - 生命周期

    /// 进入照片库 / 从设置页返回 / 回前台时调用：按当前授权状态推进
    func start() async {
        guard viewState != .loading else { return }   // 首载进行中不接受状态重入
        switch service.access {
        case .notDetermined:
            viewState = .notDetermined
        case .denied:
            viewState = .denied
        case .restricted:
            viewState = .restricted
        case .limited, .authorized:
            await loadIfNeeded()
        }
    }

    /// 授权引导页按钮：触发系统弹窗；结果经 service.access 驱动
    func requestAccess() async {
        await service.requestAccess()
        await start()
    }

    /// 「管理」按钮：调起系统 limited 选择器（新增/移除由 ChangeObserver 增量同步）
    func requestManageLimitedPhotos() {
        onManageLimitedPhotos?()
    }

    /// DEBUG 诊断摘要（DEBUG 构建的屏幕横幅用；Release 无引用）
    var debugSummary: String {
        "state=\(viewState) items=\(items.count)/\(totalCount) sections=\(sections.count) loadingMore=\(isLoadingMore)"
    }

    /// 浏览页快照入口：当前已加载条目的扁平拷贝（浏览页内自管；关闭后库侧经 observer 增量同步）
    var itemsSnapshot: [PhotoItem] { items }

    /// 库侧撤销（批量操作 Toast / 重启恢复横幅共用）：PhotoKit 反向写后经 observer 增量同步网格
    func undoLatest() async {
        _ = await undoCenter.undo()
    }

    // MARK: - 批量操作（docs/05 M3 任务 5）

    enum BatchAction {
        case setFavorite(Bool)
        case setHidden(Bool)
        case moveToRecentlyDeleted
        case addToAlbum(albumID: String)
    }

    struct BatchOutcome {
        let succeeded: Int
        let needsDownload: Int
        var message: String {
            var text = "已完成 \(succeeded) 项"
            if needsDownload > 0 {
                text += "；\(needsDownload) 张在 iCloud，请先下载原件"
            }
            return text
        }
    }

    /// 批量执行（移到最近删除前逐张落 TrashBin 副本；iCloud-only 计入 needsDownload 不执行）
    func performBatch(_ action: BatchAction, ids: [String]) async -> BatchOutcome {
        guard !ids.isEmpty else { return BatchOutcome(succeeded: 0, needsDownload: 0) }
        do {
            switch action {
            case .setFavorite(let favorite):
                try await writer.setFavorite(ids: ids, isFavorite: favorite)
                undoCenter.push(kind: favorite ? .favorite(ids) : .unfavorite(ids),
                                assetIDs: ids,
                                toastText: favorite ? "已收藏" : "已取消收藏",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: ids.count, needsDownload: 0)

            case .setHidden(let hidden):
                try await writer.setHidden(ids: ids, isHidden: hidden)
                undoCenter.push(kind: hidden ? .hide(ids) : .unhide(ids),
                                assetIDs: ids,
                                toastText: hidden ? "已隐藏" : "已取消隐藏",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: ids.count, needsDownload: 0)

            case .addToAlbum(let albumID):
                try await writer.add(ids: ids, toAlbum: albumID)
                undoCenter.push(kind: .addToAlbum(assetIDs: ids, albumID: albumID),
                                assetIDs: ids,
                                albumID: albumID,
                                toastText: "已加入相簿",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: ids.count, needsDownload: 0)

            case .moveToRecentlyDeleted:
                // 红线 1：逐张落撤销保险副本（iCloud-only 拒绝并计数）→ deleteAssets（唯一删除实现）
                var records: [TrashRecord] = []
                var needsDownload = 0
                for id in ids {
                    do {
                        records.append(try await trashBin.storeCopy(forAssetID: id))
                    } catch TrashError.needsDownload {
                        needsDownload += 1
                    }
                }
                let originIDs = records.map(\.originLocalID)
                guard !originIDs.isEmpty else {
                    return BatchOutcome(succeeded: 0, needsDownload: needsDownload)
                }
                try await writer.moveToRecentlyDeleted(ids: originIDs)
                undoCenter.push(kind: .moveToRecentlyDeleted(trashRecordIDs: records.map(\.id), originIDs: originIDs),
                                assetIDs: originIDs,
                                trashRecordIDs: records.map(\.id),
                                toastText: "已移到最近删除",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: originIDs.count, needsDownload: needsDownload)
            }
        } catch {
            return BatchOutcome(succeeded: 0, needsDownload: 0)
        }
    }

    // MARK: - 加载与分页

    private func loadIfNeeded() async {
        guard !hasLoadedOnce else {
            viewState = items.isEmpty ? .empty : .ready
            return
        }
        viewState = .loading
        totalCount = await repository.prepare(scope: .all)
        hasLoadedOnce = true
        isLimitedAccess = (service.access == .limited)
        // 空库也要监听变更：第一张照片加入时增量同步并切出空态
        startObservingChanges()
        guard totalCount > 0 else {
            viewState = .empty
            return
        }
        items = await repository.fetch(scope: .all, offset: 0, limit: min(batchSize, totalCount))
        rebuildSections(animated: false)
        viewState = .ready
    }

    /// 滚动接近底部时续页（VC scrollViewDidScroll 触发）
    func loadNextPage() async {
        guard hasLoadedOnce, !isLoadingMore, items.count < totalCount else { return }
        isLoadingMore = true
        let page = await repository.fetch(scope: .all, offset: items.count, limit: batchSize)
        guard !page.isEmpty else {
            isLoadingMore = false
            return
        }
        items += page
        rebuildSections(animated: true)
        isLoadingMore = false
    }

    /// 预取（VC prefetchRowsAt 触发）
    func prefetch(ids: [String], cellPixelSize: CGSize) {
        pipeline.prefetch(ids: ids, size: CGSize(width: cellPixelSize.width, height: cellPixelSize.height))
    }

    // MARK: - 变更增量（系统相册增删 / limited 选择 / 收藏隐藏同步）

    private func startObservingChanges() {
        guard changeObserver == nil, let result = repository.latestResult else { return }
        let observer = PhotoChangeObserver { [weak self] changeSet in
            self?.applyChange(changeSet)
        }
        observer.startMonitoring(result: result)
        changeObserver = observer
    }

    private func applyChange(_ changeSet: PhotoChangeObserver.ChangeSet) {
        // 1. 数据层增量：items 数组镜像 fetchResult（移除（旧索引，倒序）→ 变更（旧索引原位替换）→ 插入（新索引，升序））
        var updated = items

        for index in changeSet.removedIndexes.sorted(by: >) where index < updated.count {
            updated.remove(at: index)
        }
        let changed = zip(changeSet.changedIndexes, changeSet.changedObjects)
        for (index, asset) in changed where index < updated.count {
            updated[index] = repository.map(asset)
        }
        if let newResult = changeSet.resultAfterChanges {
            for index in changeSet.insertedIndexes where index <= updated.count {
                updated.insert(repository.map(newResult.object(at: index)), at: index)
            }
        }

        items = updated
        totalCount = changeSet.resultAfterChanges?.count ?? totalCount
        rebuildSections(animated: true)

        // 库清空 / 从空到非空时同步视图状态
        if viewState == .empty && !items.isEmpty { viewState = .ready }
        if viewState == .ready && items.isEmpty && totalCount == 0 { viewState = .empty }

        // 2. 底层结果换新并续听（旧 result 不再推送）
        if let newResult = changeSet.resultAfterChanges {
            repository.replaceResult(newResult, for: .all)
            changeObserver?.startMonitoring(result: newResult)
        }
    }

    // MARK: - 分组与快照

    private func rebuildSections(animated: Bool) {
        let (newSections, orderedIDs) = DateSectionizerAdapter.monthSections(
            ids: items.map(\.id),
            dates: items.map(\.creationDate)
        )
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sections = newSections
        itemsBySection = orderedIDs.groupedBy(sections: newSections, lookup: byID)
        onSnapshotUpdate?(newSections, itemsBySection, animated)
    }

    private var onSnapshotUpdate: ((_ sections: [MonthSection], _ itemsBySection: [[PhotoItem]], _ animated: Bool) -> Void)?
}

private extension Array where Element == String {
    /// 把平铺 id 顺序按 sections 切开（orderedIDs 本就按组序展开）
    func groupedBy(sections: [MonthSection], lookup: [String: PhotoItem]) -> [[PhotoItem]] {
        var result: [[PhotoItem]] = []
        var cursor = 0
        for section in sections {
            let next = cursor + section.count
            // Swift.min：Array 扩展内裸写 min 会命中 Sequence.min() 实例方法（遮蔽全局函数）
            let slice = (cursor..<Swift.min(next, count)).compactMap { lookup[self[$0]] }
            result.append(slice)
            cursor = next
        }
        return result
    }
}
