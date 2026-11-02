// MARK: - 职责说明：照片库 ViewModel（docs/09 Phase 1 重写：query-driven 完整索引）——
// LibraryQuery（scope+filter+sort）→ 首屏 500 先 ready → 后台 500/批补齐全量索引 → PhotoFilter 应用
// → filteredItems（单一事实来源：网格 / 全选 / 查看器 / 位置记忆 / 搜索共用）。
// pending 过滤：ReviewSession 的待删除/待隐藏项在网格立即消失（仅 SessionReview 可恢复）。
// 变更增量：PhotoChangeObserver → allItems 增删改 → 重新应用 filter + pending → Diffable 快照推送。

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
    @Published private(set) var query = LibraryQuery()
    /// 完整索引（分批加载，含 pending 项）
    @Published private(set) var allItems: [PhotoItem] = []
    /// 可见项 = allItems − pendingDelete/pendingHide
    @Published private(set) var visibleItems: [PhotoItem] = []
    /// 当前筛选结果（基于 visibleItems；网格/全选/查看器共用）
    @Published private(set) var filteredItems: [PhotoItem] = []
    @Published private(set) var sections: [MonthSection] = []
    @Published private(set) var itemsBySection: [[PhotoItem]] = []
    /// 完整索引进度（后台补齐）
    @Published private(set) var indexProgress: (loaded: Int, total: Int) = (0, 0)
    @Published private(set) var isIndexing = false
    @Published private(set) var isLimitedAccess = false
    @Published private(set) var isLoadingMore = false

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
    private let settings: SettingsStore
    private let reviewSession: ReviewSessionController
    private let batchSize = AssetRepository.batchSize

    // MARK: - 内部状态

    private var totalCount = 0
    private var changeObserver: PhotoChangeObserver?
    private var hasLoadedOnce = false
    private var indexingTask: Task<Void, Never>?

    init(service: PhotoLibraryService,
         repository: AssetRepositoryProtocol,
         pipeline: ImagePipelineProtocol,
         writer: PhotoWriterProtocol,
         trashBin: TrashBin,
         undoCenter: UndoCenter,
         settings: SettingsStore,
         reviewSession: ReviewSessionController) {
        self.service = service
        self.repository = repository
        self.pipeline = pipeline
        self.writer = writer
        self.trashBin = trashBin
        self.undoCenter = undoCenter
        self.settings = settings
        self.reviewSession = reviewSession
        reviewSession.onSessionChanged = { [weak self] session in
            self?.applyPendingChanges(session)
        }
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
        "state=\(viewState) all=\(allItems.count)/\(totalCount) filtered=\(filteredItems.count) " +
            "sections=\(sections.count) indexing=\(isIndexing) " +
            "del=\(reviewSession.pendingDeleteCount) hide=\(reviewSession.pendingHideCount)"
    }

    /// 浏览页/搜索快照入口：当前筛选结果（docs/09 §2.1 单一事实来源）
    var itemsSnapshot: [PhotoItem] { filteredItems }
    var itemsSnapshotForViewer: [PhotoItem] { filteredItems }

    /// 库侧撤销（批量操作 Toast / 重启恢复横幅共用）：PhotoKit 反向写后经 observer 增量同步网格
    func undoLatest() async {
        _ = await undoCenter.undo()
    }

    // MARK: - 查询更新（D10）

    /// 顶部五段切换（全部/收藏/视频/截图/已隐藏走 Vault，不经此）
    func setScope(_ scope: PhotoScope) async {
        guard scope != query.scope else { return }
        query.scope = scope
        await reloadForQuery()
    }

    /// 筛选变化：内存全集上应用（不重查 PhotoKit，<500ms 预算内）
    func setFilter(_ filter: SearchPredicate) {
        guard filter != query.filter else { return }
        query.filter = filter
        rebuildDerived(animated: false)
    }

    /// 排序（docs/09 D10：sortAscending 下推 fetch + 分组顺序）
    func setSort(ascending: Bool) async {
        guard ascending != query.sortAscending else { return }
        query.sortAscending = ascending
        await reloadForQuery()
    }

    /// 下拉刷新（Phase 2）：保留筛选与排序，重查当前 scope
    func reload() async {
        await reloadForQuery()
    }

    /// 全选前确保完整索引就绪（docs/09 D11）
    func ensureIndexComplete() async {
        await indexingTask?.value
    }

    // MARK: - 批量操作（收藏 / 相簿；删除与隐藏已改走 ReviewSession，D16）

    enum BatchAction {
        case setFavorite(Bool)
        case setHidden(Bool)
        case addToAlbum(albumID: String)
    }

    struct BatchOutcome {
        let succeeded: Int
        let failed: Int
        var message: String {
            failed > 0 ? "已完成 \(succeeded) 项；\(failed) 项失败" : "已完成 \(succeeded) 项"
        }
    }

    func performBatch(_ action: BatchAction, ids: [String]) async -> BatchOutcome {
        guard !ids.isEmpty else { return BatchOutcome(succeeded: 0, failed: 0) }
        do {
            switch action {
            case .setFavorite(let favorite):
                try await writer.setFavorite(ids: ids, isFavorite: favorite)
                undoCenter.push(kind: favorite ? .favorite : .unfavorite,
                                assetIDs: ids,
                                toastText: favorite ? "已收藏" : "已取消收藏",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: ids.count, failed: 0)

            case .setHidden(let hidden):
                try await writer.setHidden(ids: ids, isHidden: hidden)
                undoCenter.push(kind: hidden ? .hide : .unhide,
                                assetIDs: ids,
                                toastText: hidden ? "已隐藏" : "已取消隐藏",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: ids.count, failed: 0)

            case .addToAlbum(let albumID):
                try await writer.add(ids: ids, toAlbum: albumID)
                undoCenter.push(kind: .addToAlbum,
                                assetIDs: ids,
                                albumID: albumID,
                                toastText: "已加入相簿",
                                window: settings.undoWindow)
                return BatchOutcome(succeeded: ids.count, failed: 0)
            }
        } catch {
            return BatchOutcome(succeeded: 0, failed: ids.count)
        }
    }

    // MARK: - 加载与完整索引

    private func loadIfNeeded() async {
        guard !hasLoadedOnce else {
            viewState = allItems.isEmpty ? .empty : .ready
            return
        }
        viewState = .loading
        isLimitedAccess = (service.access == .limited)
        totalCount = await repository.prepare(scope: query.scope, sortAscending: query.sortAscending)
        hasLoadedOnce = true
        // 空库也要监听变更：第一张照片加入时增量同步并切出空态
        startObservingChanges()
        guard totalCount > 0 else {
            rebuildDerived(animated: false)
            viewState = .empty
            return
        }
        allItems = await repository.fetch(scope: query.scope,
                                          offset: 0,
                                          limit: min(batchSize, totalCount))
        indexProgress = (allItems.count, totalCount)
        rebuildDerived(animated: false)
        viewState = .ready
        startIndexCompletion()
    }

    /// 后台补齐全量索引（500/批；每 2,000 条合并一次重建，docs/09 §2.2）
    private func startIndexCompletion() {
        indexingTask?.cancel()
        indexingTask = Task { [weak self] in
            guard let self else { return }
            await self.runIndexCompletion()
        }
    }

    private func runIndexCompletion() async {
        guard allItems.count < totalCount else { return }
        isIndexing = true
        var sinceRebuild = 0
        defer {
            isIndexing = false
            indexProgress = (min(allItems.count, totalCount), totalCount)
        }
        while !Task.isCancelled, allItems.count < totalCount {
            let page = await repository.fetch(scope: query.scope,
                                              offset: allItems.count,
                                              limit: batchSize)
            guard !page.isEmpty, !Task.isCancelled else { break }
            allItems += page
            sinceRebuild += page.count
            indexProgress = (allItems.count, totalCount)
            if sinceRebuild >= 2_000 {
                rebuildDerived(animated: false)
                sinceRebuild = 0
            }
        }
        if !Task.isCancelled {
            rebuildDerived(animated: true)
        }
    }

    /// 预取（VC prefetchRowsAt 触发）
    func prefetch(ids: [String], cellPixelSize: CGSize) {
        pipeline.prefetch(ids: ids, size: CGSize(width: cellPixelSize.width, height: cellPixelSize.height))
    }

    // MARK: - 变更增量（系统相册增删 / limited 选择 / 收藏隐藏同步）

    private func startObservingChanges() {
        guard changeObserver == nil,
              let result = repository.latestResult(for: query.scope) else { return }
        let observer = PhotoChangeObserver { [weak self] changeSet in
            self?.applyChange(changeSet)
        }
        observer.startMonitoring(result: result)
        changeObserver = observer
    }

    private func restartObserving() {
        changeObserver = nil
        startObservingChanges()
    }

    private func applyChange(_ changeSet: PhotoChangeObserver.ChangeSet) {
        // 1. 数据层增量：allItems 镜像 fetchResult（移除（旧索引，倒序）→ 变更（旧索引原位替换）→ 插入（新索引，升序））
        var updated = allItems

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

        allItems = updated
        totalCount = changeSet.resultAfterChanges?.count ?? totalCount
        indexProgress = (min(allItems.count, totalCount), totalCount)
        // docs/09 §2.2.5：变更后重新应用 filter + pending，再推快照（不允许混数组）
        rebuildDerived(animated: true)

        // 库清空 / 从空到非空时同步视图状态
        if viewState == .empty && !filteredItems.isEmpty { viewState = .ready }
        if viewState == .ready && filteredItems.isEmpty && totalCount == 0 { viewState = .empty }

        // 2. 底层结果换新并续听（旧 result 不再推送）
        if let newResult = changeSet.resultAfterChanges {
            repository.replaceResult(newResult, for: query.scope)
            changeObserver?.startMonitoring(result: newResult)
        }
    }

    // MARK: - pending 过滤（D16）

    /// ReviewSessionController.onSessionChanged 回调：pending 集合变化 → 立即重算可见集
    func applyPendingChanges(_ session: ReviewSession) {
        guard hasLoadedOnce else { return }
        rebuildDerived(animated: false)
    }

    // MARK: - 派生计算（visible → filtered → sections）

    private func rebuildDerived(animated: Bool) {
        let pendingDeletes = Set(reviewSession.session.pendingDeleteIDs)
        let pendingHides = Set(reviewSession.session.pendingHideIDs)
        let pending = pendingDeletes.union(pendingHides)
        visibleItems = pending.isEmpty ? allItems : allItems.filter { !pending.contains($0.id) }
        filteredItems = PhotoFilter.apply(visibleItems, predicate: query.filter)
        rebuildSections(animated: animated)
    }

    private func rebuildSections(animated: Bool) {
        let (newSections, orderedIDs) = DateSectionizerAdapter.monthSections(
            ids: filteredItems.map(\.id),
            dates: filteredItems.map(\.creationDate),
            ascending: query.sortAscending
        )
        let byID = Dictionary(filteredItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sections = newSections
        itemsBySection = orderedIDs.groupedBy(sections: newSections, lookup: byID)
        onSnapshotUpdate?(newSections, itemsBySection, animated)
    }

    private func reloadForQuery() async {
        guard hasLoadedOnce else { return }
        indexingTask?.cancel()
        totalCount = await repository.prepare(scope: query.scope, sortAscending: query.sortAscending)
        restartObserving()
        guard totalCount > 0 else {
            allItems = []
            rebuildDerived(animated: false)
            viewState = .empty
            return
        }
        allItems = await repository.fetch(scope: query.scope,
                                          offset: 0,
                                          limit: min(batchSize, totalCount))
        indexProgress = (allItems.count, totalCount)
        rebuildDerived(animated: false)
        viewState = .ready
        startIndexCompletion()
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
