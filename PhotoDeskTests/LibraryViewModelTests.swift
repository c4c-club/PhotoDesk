// MARK: - 职责说明：LibraryViewModel 单元测试（docs/09 Phase 1 §7）——
// Fake 资产仓库 + mock writer：首屏 500 先 ready、后台补齐全量、筛选、pending 过滤、
// 快照推送（itemsBySection 与 filteredItems 同源）。不触碰 PhotoKit。

import XCTest
import AVFoundation
import Photos
import CoreLocation
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
private final class FakeAssetRepository: AssetRepositoryProtocol {
    var store: [PhotoItem]
    private(set) var lastPrepareSortAscending: Bool?

    init(_ store: [PhotoItem]) {
        self.store = store
    }

    func prepare(scope: PhotoScope) async -> Int { store.count }

    func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int {
        lastPrepareSortAscending = sortAscending
        return store.count
    }

    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] {
        // 模拟分批：仅 .all / .favorites 等直接切片（测试只需要 .all）
        guard scope == .all || scope == .favorites || scope == .videos || scope == .screenshots else { return [] }
        return Array(store.dropFirst(offset).prefix(limit))
    }

    func fetch(ids: [String]) async -> [PhotoItem] {
        let set = Set(ids)
        return store.filter { set.contains($0.id) }
    }

    func globalIndex(of assetID: String, scope: PhotoScope) async -> Int? {
        store.firstIndex(where: { $0.id == assetID })
    }

    func count(scope: PhotoScope) async -> Int { store.count }

    var latestResult: PHFetchResult<PHAsset>? { nil }
    func latestResult(for scope: PhotoScope) -> PHFetchResult<PHAsset>? { nil }
    func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope) {}
    func map(_ asset: PHAsset) -> PhotoItem { store.first ?? Self.emptyItem }

    static let emptyItem = PhotoItem(id: "empty",
                                     mediaType: .image, mediaSubtypes: [],
                                     creationDate: nil, modificationDate: nil,
                                     pixelWidth: 1, pixelHeight: 1, duration: 0,
                                     isFavorite: false, isHidden: false,
                                     location: nil, burstIdentifier: nil, isCloudOnly: false)
}

@MainActor
private final class FakeImagePipeline: ImagePipelineProtocol {
    func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage? { nil }
    func prefetch(ids: [String], size: CGSize) {}
    func cancel(id: String) {}
    func cancelAll() {}
    func fullImageWithState(for id: String, progress: @escaping (Double) -> Void,
                            allowNetwork: Bool) async -> FullImageResult {
        FullImageResult(image: nil, isInCloud: false)
    }
    func videoAsset(for id: String) async -> (asset: AVAsset, audioMix: AVAudioMix?)? { nil }
    var diskCacheBytes: Int64 { 0 }
    func clearCaches() {}
}

@MainActor
final class LibraryViewModelTests: XCTestCase {
    private var settings: SettingsStore!
    private var writer: MockPhotoWriter!
    private var session: ReviewSessionController!
    private var persistence: PersistenceController!
    private var snapshots: [(sections: [MonthSection], items: [[PhotoItem]])] = []

    override func setUp() async throws {
        // 测试隔离：清除筛选持久化（library.filter.* 写入 standard UserDefaults，
        // 泄漏会让后续测试/宿主 App 的网格按残留筛选过滤——CI 实测根因）
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("library.filter.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        settings = SettingsStore()
        writer = MockPhotoWriter()
        persistence = PersistenceController(inMemory: true)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibVMTests-\(UUID().uuidString)", isDirectory: true)
        session = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                          writer: writer, trashBin: nil, settings: settings)
    }

    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("library.filter.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeItem(_ index: Int, date: Date? = nil, favorite: Bool = false) -> PhotoItem {
        // 全部照片（媒体类型测试用 testFilterOnlyAppliesToCompleteIndex 内显式替换视频）
        PhotoItem(id: "id-\(index)",
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: date ?? Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index * 86_400)),
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: favorite, isHidden: false,
                  location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    private func makeViewModel(_ repo: FakeAssetRepository) -> LibraryViewModel {
        let service = PhotoLibraryService(initialAccess: .authorized)
        let vm = LibraryViewModel(service: service,
                                  repository: repo,
                                  pipeline: FakeImagePipeline(),
                                  writer: writer,
                                  trashBin: TrashBin(persistence: persistence, settings: settings),
                                  undoCenter: UndoCenter(writer: writer,
                                                         trashBin: nil,
                                                         persistence: persistence),
                                  settings: settings,
                                  reviewSession: session)
        vm.attachSnapshotHandler { [weak self] snapshot in
            self?.snapshots.append((snapshot.sections, snapshot.itemsBySection))
        }
        return vm
    }

    // MARK: - 加载

    func testFirstScreenReadyThenFullIndex() async {
        let items = (0..<1_100).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        XCTAssertEqual(vm.viewState, .ready, "首屏 500 立即 ready")
        XCTAssertEqual(vm.allItems.count, 500)
        await vm.ensureIndexComplete()
        XCTAssertEqual(vm.allItems.count, 1_100, "后台补齐全量")
        XCTAssertEqual(vm.indexProgress.loaded, 1_100)
        XCTAssertEqual(vm.filteredItems.count, 1_100)
    }

    func testEmptyLibraryShowsEmptyState() async {
        let vm = makeViewModel(FakeAssetRepository([]))
        await vm.start()
        XCTAssertEqual(vm.viewState, .empty)
    }

    // MARK: - 筛选

    func testSetFilterNarrowsResults() async {
        let items = (0..<10).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        await vm.ensureIndexComplete()

        var filter = SearchPredicate.default
        filter.year = Calendar.current.component(.year, from: items[0].creationDate!)
        vm.setFilter(filter)
        await vm.waitForFilterComputation()
        XCTAssertEqual(vm.filteredItems.count, 10, "全部 10 张同年")
        XCTAssertEqual(vm.sections.first?.count, 10, "分组头计数与筛选结果一致")

        filter.month = Calendar.current.component(.month, from: items[0].creationDate!) + 7  // 不存在的月
        vm.setFilter(filter)
        await vm.waitForFilterComputation()
        XCTAssertTrue(vm.filteredItems.isEmpty, "无结果筛选 → 空集（网格显示「清除筛选」空态）")
        XCTAssertEqual(vm.viewState, .ready, "筛选无结果不是库空态")
    }

    func testFilterOnlyAppliesToCompleteIndex() async {
        // 1,100 张里只有末尾（第 1,050 张）是视频：筛选视频必须命中「未加载完」的数据
        var items = (0..<1_100).map { makeItem($0) }
        items[1_050] = PhotoItem(id: "id-1050",
                                 mediaType: .video,
                                 mediaSubtypes: [],
                                 creationDate: items[1_050].creationDate,
                                 modificationDate: nil,
                                 pixelWidth: 10, pixelHeight: 10, duration: 3,
                                 isFavorite: false, isHidden: false,
                                 location: nil, burstIdentifier: nil, isCloudOnly: false)
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        var filter = SearchPredicate.default
        filter.media = [.video]
        vm.setFilter(filter)
        await vm.ensureIndexComplete()
        await vm.waitForFilterComputation()
        XCTAssertEqual(vm.filteredItems.count, 1, "筛选作用于完整索引而非首屏 500")
    }

    // MARK: - 后台筛选 / 代际令牌 / 去重（docs/13 S03 验收）

    func testSetFilterIsAsynchronousWithSameResult() async {
        // 后台过滤结果与同步口径一致（docs/13 S03 修复 1）
        let items = (0..<300).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        await vm.ensureIndexComplete()

        var filter = SearchPredicate.default
        filter.media = [.photo]
        vm.setFilter(filter)
        XCTAssertEqual(vm.filteredItems.count, 300, "setFilter 立即返回（未阻塞主线程），结果尚未应用")
        await vm.waitForFilterComputation()
        XCTAssertEqual(vm.filteredItems.count, 300, "后台计算完成后与同步口径一致")
        XCTAssertEqual(vm.sections.count, vm.itemsBySection.count)
    }

    func testStaleFilterResultIsDiscardedByGeneration() async {
        // 连续两次 setFilter：旧计算的过期结果不得覆盖新结果（代际令牌，docs/13 S03 修复 4）
        var items = (0..<100).map { makeItem($0) }
        items[0] = PhotoItem(id: "id-0",
                             mediaType: .video,
                             mediaSubtypes: [],
                             creationDate: items[0].creationDate,
                             modificationDate: nil,
                             pixelWidth: 10, pixelHeight: 10, duration: 2,
                             isFavorite: false, isHidden: false,
                             location: nil, burstIdentifier: nil, isCloudOnly: false)
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        await vm.ensureIndexComplete()

        var videoFilter = SearchPredicate.default
        videoFilter.media = [.video]
        var imageFilter = SearchPredicate.default
        imageFilter.media = [.photo]
        vm.setFilter(videoFilter)   // 旧任务：预期 1
        vm.setFilter(imageFilter)   // 新任务：预期 99（覆盖旧任务的 generation）
        await vm.waitForFilterComputation()
        XCTAssertEqual(vm.filteredItems.count, 99, "过期结果应被代际令牌丢弃")
    }

    func testDuplicateItemIDsAreDedupedBeforeSnapshot() async {
        // 仓库返回重复 id（索引期间库变更模拟）：快照不得 fatal，且去重保序（docs/13 S03 修复 5）
        var items = (0..<10).map { makeItem($0) }
        items.append(items[3])   // 重复 id
        let vm = makeViewModel(FakeAssetRepository(items))
        var snapshotIDs: [[String]] = []
        vm.attachSnapshotHandler { snapshot in
            snapshotIDs.append(snapshot.itemsBySection.flatMap { $0.map(\.id) })
        }
        await vm.start()
        await vm.ensureIndexComplete()
        XCTAssertEqual(vm.filteredItems.count, 10, "重复 id 去重")
        let allIDs = vm.itemsBySection.flatMap { $0.map(\.id) }
        XCTAssertEqual(Set(allIDs).count, allIDs.count, "快照内 id 唯一")
        XCTAssertEqual(snapshotIDs.last?.count, 10, "推送的快照同样去重")
    }

    func testIndexCompleteFlagTurnsTrueAfterFullIndex() async {
        let items = (0..<1_100).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        XCTAssertEqual(vm.isIndexComplete, false, "首屏 500 时索引未完成")
        await vm.ensureIndexComplete()
        XCTAssertEqual(vm.isIndexComplete, true, "补齐后置位（位置恢复/单月全选依赖）")
    }

    // MARK: - pending 过滤（D16）

    func testPendingItemsExcludedFromGrid() async {
        let items = (0..<5).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        await vm.ensureIndexComplete()
        XCTAssertEqual(vm.filteredItems.count, 5)

        session.enqueueDelete(id: "id-1", originIndex: 1)
        session.enqueueHide(id: "id-3", originIndex: 3)
        // onSessionChanged 同步回调 → filteredItems 立即排除
        XCTAssertEqual(vm.filteredItems.map(\.id), ["id-0", "id-2", "id-4"], "待删除/待隐藏立即从网格消失")
        XCTAssertEqual(vm.allItems.count, 5, "allItems 不受 pending 影响")

        // 撤销 → 立即回来
        session.undoPending(id: "id-1", kind: .delete)
        XCTAssertEqual(vm.filteredItems.map(\.id), ["id-0", "id-1", "id-2", "id-4"])
    }

    // MARK: - 排序（D08/D10 接线）

    func testSetSortPushesToRepository() async {
        let items = (0..<5).map { makeItem($0) }
        let repo = FakeAssetRepository(items)
        let vm = makeViewModel(repo)
        await vm.start()
        await vm.ensureIndexComplete()
        await vm.setSort(ascending: true)
        XCTAssertTrue(repo.lastPrepareSortAscending == true, "sortAscending 下推 PHFetchOptions")
        XCTAssertEqual(vm.query.sortAscending, true)
    }

    // MARK: - scope 切换

    func testSetScopeRefetches() async {
        let items = (0..<10).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        await vm.ensureIndexComplete()
        await vm.setScope(.favorites)
        XCTAssertEqual(vm.query.scope, .favorites)
        // Fake 仓库 favorites 仍返回全量（切片实现）——此处验证查询流转不崩、数据源重建
        XCTAssertEqual(vm.viewState, .ready)
    }

    // MARK: - 批量操作（收藏仍即时写；删除/隐藏已走会话）

    func testBatchFavoriteWritesAndPushesUndo() async {
        let items = (0..<3).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        let outcome = await vm.performBatch(.setFavorite(true), ids: ["id-0", "id-1"])
        XCTAssertEqual(outcome.succeeded, 2)
        XCTAssertEqual(writer.setFavoriteCalls.count, 1, "一次批量写")
        XCTAssertEqual(writer.setFavoriteCalls.first?.ids, ["id-0", "id-1"])
    }

    // MARK: - 会话提交联动（20 次滑动 0 次 writer；docs/09 D16 §8）

    func testTwentySwipesProduceZeroWriterCalls() async {
        let items = (0..<30).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        await vm.ensureIndexComplete()
        for (index, item) in items.prefix(20).enumerated() {
            _ = session.enqueueDelete(id: item.id, originIndex: index)
        }
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 0, "滑动路径 0 次 PhotoKit 写")
        XCTAssertEqual(session.pendingDeleteCount, 20)
        XCTAssertEqual(vm.filteredItems.count, 10, "网格只剩未标记项")

        let committed = await session.commitDeletes()
        XCTAssertEqual(committed.committed, 20, "一次批量提交")
        XCTAssertEqual(writer.moveToRecentlyDeletedCallCount, 1, "恰好 1 次 deleteAssets（1 次系统确认）")
        XCTAssertEqual(writer.moveToRecentlyDeletedCalls.first?.count, 20, "一次传入全部 id")
        XCTAssertTrue(session.isEmpty, "提交成功清空队列")
    }

    func testCommitCancellationKeepsQueue() async {
        let items = (0..<3).map { makeItem($0) }
        let vm = makeViewModel(FakeAssetRepository(items))
        await vm.start()
        // mock writer 抛错模拟「系统确认取消」
        writer.shouldFailMoveToRecentlyDeleted = true
        for item in items { _ = session.enqueueDelete(id: item.id, originIndex: 0) }
        let committed = await session.commitDeletes()
        XCTAssertEqual(committed.committed, 0)
        XCTAssertEqual(session.pendingDeleteCount, 3, "失败/取消：队列保留不丢数据")
    }
}
