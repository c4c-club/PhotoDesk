// MARK: - 职责说明：照片库 ViewModel（docs/09 Phase 1 重写：query-driven 完整索引）——
// LibraryQuery（scope+filter+sort）→ 首屏 500 先 ready → 后台 500/批补齐全量索引 → PhotoFilter 应用
// → filteredItems（单一事实来源：网格 / 全选 / 查看器 / 位置记忆 / 搜索共用）。
// pending 过滤：ReviewSession 的待删除/待隐藏项在网格立即消失（仅 SessionReview 可恢复）。
// 变更增量：PhotoChangeObserver → allItems 增删改 → 重新应用 filter + pending → Diffable 快照推送。

import Foundation
import Photos
import PhotoDeskCore

/// 网格快照（docs/13 §3.4）：sections + itemsBySection + 动画标记 + 查询键。
/// queryKey 随快照走（位置记忆 v2 用「快照时的 key」而非「保存时的 key」）。
struct LibrarySnapshot {
    let sections: [MonthSection]
    let itemsBySection: [[PhotoItem]]
    let animated: Bool
    let queryKey: String
}

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
    /// 完整索引是否就绪（docs/13 S04/S10：位置恢复等待 + 单月全选范围判定）
    @Published private(set) var isIndexComplete = false
    @Published private(set) var isLimitedAccess = false
    @Published private(set) var isLoadingMore = false
    /// head 回填代际（v6 §5.4）：每个 head 批次前插后 +1；恢复状态机据此判定「连续两轮不变」
    @Published private(set) var headInsertGeneration = 0
    /// head 回填进行中（首批窗口 > 0 且头部批次尚未全部插完）
    @Published private(set) var isHeadBackfillActive = false

    /// VC 注册：快照数据推送（主线程）。已在加载完成的 VC 接入时立即重放当前快照——
    /// 否则 VM 先于 VC 完成加载，回调错过唯一一次推送，网格永远空白（CI 实测的根因）。
    func attachSnapshotHandler(_ handler: @escaping (LibrarySnapshot) -> Void) {
        onSnapshotUpdate = handler
        if viewState == .ready {
            handler(LibrarySnapshot(sections: sections, itemsBySection: itemsBySection,
                                    animated: false, queryKey: query.key))
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
    /// 位置记忆（docs/16 M12 R03：锚点窗口首屏；nil = 测试注入缺省，走「最新 500」）
    private let positionStore: LibraryPositionStore?
    private let batchSize = AssetRepository.batchSize

    // MARK: - 内部状态

    private var totalCount = 0
    private var changeObserver: PhotoChangeObserver?
    private var hasLoadedOnce = false
    private var indexingTask: Task<Void, Never>?
    /// 首批窗口在全量结果中的起始 offset（R03：锚点窗口 > 0 时，头部月份延后回填）
    private(set) var firstBatchWindowStart = 0
    /// assetID → 全量索引位置（v6 anchorGlobalIndex 取证用；rebuildDerived 维护）
    private var globalIndexByID: [String: Int] = [:]

    /// 全量索引位置查询（O(1)；未收录/已删除 → nil）
    func globalIndex(ofAssetID id: String) -> Int? { globalIndexByID[id] }

    init(service: PhotoLibraryService,
         repository: AssetRepositoryProtocol,
         pipeline: ImagePipelineProtocol,
         writer: PhotoWriterProtocol,
         trashBin: TrashBin,
         undoCenter: UndoCenter,
         settings: SettingsStore,
         reviewSession: ReviewSessionController,
         positionStore: LibraryPositionStore? = nil) {
        self.service = service
        self.repository = repository
        self.pipeline = pipeline
        self.writer = writer
        self.trashBin = trashBin
        self.undoCenter = undoCenter
        self.settings = settings
        self.reviewSession = reviewSession
        self.positionStore = positionStore
        // 初始排序跟随设置（grid.sortAsc，docs/09 D10 接线）
        query.sortAscending = settings.sortAscending
        // 筛选持久化（docs/09 D10：library.filter.<scope>，各 scope 独立保留）
        query.filter = Self.loadPersistedFilter(for: query.scope)
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
    /// debugRestoreNote：位置恢复状态（restore=ok/pending/ratio，docs/13 S04；VC 写入）
    @Published var debugRestoreNote = ""
    /// debugScrollNote：网格滚动状态（M12 级联取证：CI 失败时从 AX 可读，VC 写入）
    @Published var debugScrollNote = ""
    var debugSummary: String {
        "state=\(viewState) all=\(allItems.count)/\(totalCount) filtered=\(filteredItems.count) " +
            "sections=\(sections.count) indexing=\(isIndexing) done=\(isIndexComplete) " +
            "del=\(reviewSession.pendingDeleteCount) hide=\(reviewSession.pendingHideCount)" +
            (debugRestoreNote.isEmpty ? "" : " \(debugRestoreNote)") + " \(debugScrollNote)"
    }

    /// 浏览页/搜索快照入口：当前筛选结果（docs/09 §2.1 单一事实来源）
    var itemsSnapshot: [PhotoItem] { filteredItems }
    var itemsSnapshotForViewer: [PhotoItem] { filteredItems }

    /// 库侧撤销（批量操作 Toast / 重启恢复横幅共用）：PhotoKit 反向写后经 observer 增量同步网格
    func undoLatest() async {
        _ = await undoCenter.undo()
    }

    /// 分类菜单异步计数（docs/16 M12 R06）：只读、不切换 results；
    /// 仅基于授权可见资产、主库不含隐藏（PhotoFetchOptions.includeHiddenAssets = false）；
    /// hidden 不计数（解锁前不泄露数量，调用方已挡）。
    func count(scope: PhotoScope) async -> Int? {
        guard scope != .hidden else { return nil }
        if scope == query.scope { return filteredItems.count }
        return await repository.count(scope: scope)
    }

    // MARK: - 查询更新（D10）

    /// 顶部五段切换（全部/收藏/视频/截图/已隐藏走 Vault，不经此）
    func setScope(_ scope: PhotoScope) async {
        guard scope != query.scope else { return }
        query.scope = scope
        // 切换 scope：各自记住自己的筛选（docs/09 D10 §6）
        query.filter = Self.loadPersistedFilter(for: scope)
        await reloadForQuery()
    }

    /// 筛选变化：后台全集过滤（docs/13 S03 修复 1：主线程只赋值与推快照）+ 持久化
    func setFilter(_ filter: SearchPredicate) {
        guard filter != query.filter else { return }
        query.filter = filter
        Self.persistFilter(filter, for: query.scope)
        // M13：首载前（viewDidLoad 的 -uiTestingFilterYear 钩子）只记录筛选；
        // 此时 allItems 仍为空，推空快照会让 .ready 永久停在无结果覆盖层。
        guard hasLoadedOnce else { return }
        rebuildDerivedInBackground(animated: false)
    }

    /// 清除筛选（空态「清除筛选」按钮）
    func clearFilter() {
        setFilter(.default)
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

    /// 等待后台筛选计算完成（测试用：setFilter 已异步化，docs/13 S03）
    func waitForFilterComputation() async {
        await filterTask?.value
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
        #if DEBUG
        await UITestDatedPhotoSeeder.seedIfNeeded()
        #endif
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
            // 空索引视同完成（同 reloadForQuery：恢复状态机不得等待不会到来的索引）
            isIndexComplete = true
            rebuildDerived(animated: false)
            viewState = .empty
            return
        }
        // docs/16 M12 R03：锚点窗口优先——首批以锚点为中心（前后各半批），锚点页首帧即位、零可见跳转；
        // 锚点已删除/不在结果中 → 回退「最新 500」（windowStart = 0）
        // M13 绿11 实锤：清位置钩子必须在锚点窗口计算之前执行——VC 恢复期才清的话，
        // 窗口已按旧锚点起步，全量前插补偿后首格不在屏上（AX 零 cell 级联）。
        #if DEBUG
        if UITestHooks.enabled("-uiTestingClearPosition") {
            positionStore?.clear(queryKey: query.key)
        }
        #endif
        allItems = await fetchFirstBatch()
        indexProgress = (allItems.count, totalCount)
        isIndexComplete = allItems.count >= totalCount
        rebuildDerived(animated: false)
        viewState = .ready
        startIndexCompletion()
    }

    /// 首批窗口：有锚点 → 以锚点为中心；无锚点 → 最新 batchSize（每批 ≤ 500，分批 fetch 规则不变）
    private func fetchFirstBatch() async -> [PhotoItem] {
        var windowStart = 0
        if let anchor = positionStore?.load(queryKey: query.key) {
            // v6：优先落盘的 anchorGlobalIndex（仅用于窗口定位，非身份；陈旧值钳制进结果范围），
            // 缺失再回退实时全量查询
            let savedIndex = anchor.anchorGlobalIndex
            let resolved = savedIndex ?? await repository.globalIndex(of: anchor.anchorAssetID, scope: query.scope)
            if let anchorIndex = resolved {
                let clampedIndex = min(max(anchorIndex, 0), max(0, totalCount - 1))
                windowStart = max(0, clampedIndex - batchSize / 2)
                ViewerTrace.log("anchor-window key=\(query.key.prefix(8)) anchorIdx=\(anchorIndex) start=\(windowStart)")
            }
        }
        firstBatchWindowStart = windowStart
        let limit = min(batchSize, totalCount - windowStart)
        guard limit > 0 else { return [] }
        return await repository.fetch(scope: query.scope, offset: windowStart, limit: limit)
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
        guard allItems.count < totalCount else {
            isIndexComplete = true
            return
        }
        isIndexing = true
        var sinceRebuild = 0
        defer {
            isIndexing = false
            indexProgress = (min(allItems.count, totalCount), totalCount)
        }
        // 尾部补齐：从首批窗口末尾继续（R03：窗口 > 0 时 offset 不再等于 allItems.count）
        var tailOffset = firstBatchWindowStart + allItems.count
        while !Task.isCancelled, tailOffset < totalCount {
            let page = await repository.fetch(scope: query.scope,
                                              offset: tailOffset,
                                              limit: batchSize)
            guard !page.isEmpty, !Task.isCancelled else { break }
            // docs/13 S03 修复 5：追加去重（索引期间库变更可能造成 offset 偏移 → 重复 id → Diffable fatal）
            var seen = Set(allItems.map(\.id))
            let fresh = page.filter { seen.insert($0.id).inserted }
            guard !fresh.isEmpty else { break }   // 本批全部重复：索引无法推进，避免死循环
            allItems += fresh
            tailOffset += page.count
            sinceRebuild += fresh.count
            indexProgress = (min(allItems.count, totalCount), totalCount)
            if sinceRebuild >= 2_000 {
                rebuildDerived(animated: false)
                sinceRebuild = 0
            }
        }
        // v6（docs/28 §5.5 步骤 4）：头部回填按批前插，每批 +1 headInsertGeneration 并推送一次快照，
        // 恢复协调器按 contentHeight delta 逐批补偿（不再依赖恢复期禁登记的旧竞态语义）。
        if !Task.isCancelled, firstBatchWindowStart > 0 {
            isHeadBackfillActive = true
            defer { isHeadBackfillActive = false }
            var headOffset = 0
            while !Task.isCancelled, headOffset < firstBatchWindowStart {
                let limit = min(batchSize, firstBatchWindowStart - headOffset)
                let head = await repository.fetch(scope: query.scope, offset: headOffset, limit: limit)
                guard !head.isEmpty else { break }
                let existing = Set(allItems.map(\.id))
                let freshHead = head.filter { !existing.contains($0.id) }
                if !freshHead.isEmpty {
                    allItems = freshHead + allItems
                    headInsertGeneration += 1
                    rebuildDerived(animated: false)
                }
                headOffset += head.count
                if head.count < limit { break }
            }
        }
        if !Task.isCancelled {
            isIndexComplete = allItems.count >= totalCount
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
        derivedRevision += 1
        let pendingDeletes = Set(reviewSession.session.pendingDeleteIDs)
        let pendingHides = Set(reviewSession.session.pendingHideIDs)
        let pending = pendingDeletes.union(pendingHides)
        globalIndexByID = Dictionary(allItems.enumerated().map { ($1.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        visibleItems = pending.isEmpty ? allItems : allItems.filter { !pending.contains($0.id) }
        filteredItems = PhotoFilter.apply(visibleItems, predicate: query.filter)
        rebuildSections(animated: animated)
    }

    /// 后台筛选 + 代际令牌（docs/13 S03 修复 1/4：主线程不再同步重算全库；
    /// 用户连续切年份时旧结果按 generation 丢弃，apply 不会交错）。
    /// derivedRevision 兜底：计算期间若 allItems/pending 变化（索引推进/会话变更），
    /// 过期结果直接丢弃并用当前数据同步重算一次（罕见路径，保证结果永远基于最新数据）。
    private func rebuildDerivedInBackground(animated: Bool) {
        filterGeneration += 1
        let generation = filterGeneration
        let revision = derivedRevision
        let allItems = self.allItems
        let pendingDeletes = Set(reviewSession.session.pendingDeleteIDs)
        let pendingHides = Set(reviewSession.session.pendingHideIDs)
        let predicate = query.filter
        let ascending = query.sortAscending
        filterTask?.cancel()
        filterTask = Task.detached(priority: .userInitiated) {
            // 后台重活：pending 过滤 + PhotoFilter + 分组（全部纯函数，无可变共享状态）
            let pending = pendingDeletes.union(pendingHides)
            let visible = pending.isEmpty ? allItems : allItems.filter { !pending.contains($0.id) }
            let filtered = PhotoFilter.apply(visible, predicate: predicate)
            let (newSections, orderedIDs) = DateSectionizerAdapter.monthSections(
                ids: filtered.map(\.id),
                dates: filtered.map(\.creationDate),
                ascending: ascending
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard generation == self.filterGeneration else { return }   // 代际令牌：丢弃过期结果
                guard revision == self.derivedRevision else {
                    // 计算期间数据已变（索引推进/会话变更）：基于当前数据同步重算一次
                    self.rebuildDerived(animated: animated)
                    return
                }
                self.visibleItems = visible
                self.filteredItems = filtered
                self.pushSections(newSections, orderedIDs: orderedIDs, animated: animated)
            }
        }
    }

    private var filterGeneration = 0
    /// 派生数据版本号：rebuildDerived（数据源/会话变化触发的重算）时自增
    private var derivedRevision = 0
    private var filterTask: Task<Void, Never>?

    /// sections 入库 + 推快照（主线程；去重后的 items 才允许进 Diffable）
    private func rebuildSections(animated: Bool) {
        // docs/13 S03 修复 5：重复 id 会让 Diffable 快照 fatal——按 id 去重（保序）
        let uniqueItems = Self.uniqueByID(filteredItems)
        if uniqueItems.count != filteredItems.count {
            filteredItems = uniqueItems
        }
        let (newSections, orderedIDs) = DateSectionizerAdapter.monthSections(
            ids: uniqueItems.map(\.id),
            dates: uniqueItems.map(\.creationDate),
            ascending: query.sortAscending
        )
        pushSections(newSections, orderedIDs: orderedIDs, animated: animated)
    }

    private func pushSections(_ newSections: [MonthSection], orderedIDs: [String], animated: Bool) {
        let byID = Dictionary(filteredItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sections = newSections
        itemsBySection = orderedIDs.groupedBy(sections: newSections, lookup: byID)
        onSnapshotUpdate?(LibrarySnapshot(sections: newSections,
                                          itemsBySection: itemsBySection,
                                          animated: animated,
                                          queryKey: query.key))
    }

    /// 按 id 去重（保序）。重复 id 是索引期间库变更的**预期产物**（offset 偏移），
    /// 静默去重即可——不得 assert（Debug 下会把可自愈场景变成 SIGTRAP，CI 轮 11 实测）。
    private static func uniqueByID(_ items: [PhotoItem]) -> [PhotoItem] {
        var seen = Set<String>()
        seen.reserveCapacity(items.count)
        return items.filter { seen.insert($0.id).inserted }
    }

    private func reloadForQuery() async {
        guard hasLoadedOnce else { return }
        indexingTask?.cancel()
        isIndexComplete = false   // 换查询：完整索引重新补齐（位置恢复会等待，docs/13 S04）
        totalCount = await repository.prepare(scope: query.scope, sortAscending: query.sortAscending)
        restartObserving()
        guard totalCount > 0 else {
            firstBatchWindowStart = 0
            allItems = []
            // 空索引视同完成：0 ≥ 0 无可等待。否则恢复状态机按 I4 永远等一个
            // 不会到来的索引，恢复遮罩被相位事件反复重显盖住全屏（M15 切空收藏
            // 后顶栏 AX 整体消失的实锤根因）。
            isIndexComplete = true
            rebuildDerived(animated: false)
            viewState = .empty
            return
        }
        // R03：切查询同样锚点优先（每个 scope/filter 的位置键独立，library.filter.<scope> 语义不变）
        allItems = await fetchFirstBatch()
        indexProgress = (allItems.count, totalCount)
        isIndexComplete = allItems.count >= totalCount
        rebuildDerived(animated: false)
        viewState = .ready
        startIndexCompletion()
    }

    private var onSnapshotUpdate: ((LibrarySnapshot) -> Void)?

    #if DEBUG
    /// R03 单测驱动：直接推快照（等价 pushSections 的输出路径，绕开 PhotoKit 依赖；
    /// indexComplete 同步置位以覆盖「两阶段恢复」的各阶段）
    func pushSnapshotForTesting(sections: [MonthSection],
                                itemsBySection: [[PhotoItem]],
                                queryKey: String,
                                indexComplete: Bool) {
        self.isIndexComplete = indexComplete
        self.filteredItems = itemsBySection.flatMap { $0 }
        self.sections = sections
        self.itemsBySection = itemsBySection
        onSnapshotUpdate?(LibrarySnapshot(sections: sections,
                                          itemsBySection: itemsBySection,
                                          animated: false,
                                          queryKey: queryKey))
    }
    #endif

    // MARK: - 筛选持久化（library.filter.<scope>；docs/09 D10）

    private static let filterPrefix = "library.filter."

    private static func loadPersistedFilter(for scope: PhotoScope) -> SearchPredicate {
        let key = filterPrefix + LibraryQuery.scopeKey(scope)
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let filter = try? JSONDecoder().decode(SearchPredicate.self, from: data) else {
            return .default
        }
        return filter
    }

    private static func persistFilter(_ filter: SearchPredicate, for scope: PhotoScope) {
        let key = filterPrefix + LibraryQuery.scopeKey(scope)
        guard !filter.isDefault else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(filter),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: key)
        }
    }
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
