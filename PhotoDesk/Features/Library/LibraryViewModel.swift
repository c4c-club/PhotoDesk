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

    /// VC 注册：快照数据推送（主线程）
    var onSnapshotUpdate: ((_ sections: [MonthSection], _ itemsBySection: [[PhotoItem]], _ animated: Bool) -> Void)?
    /// VC 注册：调起系统 limited 选择器（需要 VC 锚点）
    var onManageLimitedPhotos: (() -> Void)?

    // MARK: - 依赖

    private let service: PhotoLibraryService
    private let repository: AssetRepositoryProtocol
    private let pipeline: ImagePipelineProtocol
    private let batchSize = AssetRepository.batchSize

    // MARK: - 内部状态

    private var items: [PhotoItem] = []          // 已加载条目（时间倒序，镜像 fetchResult 前缀）
    private var totalCount = 0
    private var changeObserver: PhotoChangeObserver?
    private var hasLoadedOnce = false

    init(service: PhotoLibraryService,
         repository: AssetRepositoryProtocol,
         pipeline: ImagePipelineProtocol) {
        self.service = service
        self.repository = repository
        self.pipeline = pipeline
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
