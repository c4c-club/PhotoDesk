// MARK: - 职责说明：LibraryViewModel 授权状态分支单测（docs/49 T02 §3.2）——
// .limited+0 张 → .limited（不是 .empty）；.authorized+0 张 → .empty；denied→authorized 刷新后
// 重载进 .ready；force 重载取消索引并重置 hasLoadedOnce（行为断言：回到首屏 500 + 索引重跑）。
// 构造口径与 LibraryViewModelTests 相同；fake 在本文件最小实现（原 fake 为 private）。

import XCTest
import AVFoundation
import Photos
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
private final class AccessRepoFake: AssetRepositoryProtocol {
    var store: [PhotoItem]
    /// 完整索引节流（毫秒）：>0 时 offset>0 批次延迟，保证「force 重载后索引未完成」断言稳定
    var completionDelayMs: UInt64 = 0

    init(_ store: [PhotoItem]) {
        self.store = store
    }

    func prepare(scope: PhotoScope) async -> Int { store.count }

    func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int { store.count }

    func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] {
        if completionDelayMs > 0, offset > 0 {
            try? await Task.sleep(nanoseconds: completionDelayMs * 1_000_000)
        }
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
private final class AccessPipelineFake: ImagePipelineProtocol {
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
final class LibraryViewModelAccessTests: XCTestCase {
    private var settings: SettingsStore!
    private var writer: MockPhotoWriter!
    private var session: ReviewSessionController!
    private var persistence: PersistenceController!

    override func setUp() async throws {
        // 测试隔离：清除筛选持久化（同 LibraryViewModelTests，CI 实测根因）
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("library.filter.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        settings = SettingsStore()
        writer = MockPhotoWriter()
        persistence = PersistenceController(inMemory: true)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibVMAccessTests-\(UUID().uuidString)", isDirectory: true)
        session = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                          writer: writer, trashBin: nil, settings: settings)
    }

    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("library.filter.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeItem(_ index: Int) -> PhotoItem {
        PhotoItem(id: "access-\(index)",
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index * 86_400)),
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: false, isHidden: false,
                  location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    private func makeViewModel(repo: AccessRepoFake,
                               service: PhotoLibraryService) -> LibraryViewModel {
        LibraryViewModel(service: service,
                         repository: repo,
                         pipeline: AccessPipelineFake(),
                         writer: writer,
                         trashBin: TrashBin(persistence: persistence, settings: settings),
                         undoCenter: UndoCenter(writer: writer,
                                                trashBin: nil,
                                                persistence: persistence),
                         settings: settings,
                         reviewSession: session)
    }

    // MARK: - .limited 分离（docs/49 T02 §5）

    func testLimitedZeroAssetsShowsLimitedNotEmpty() async {
        let vm = makeViewModel(repo: AccessRepoFake([]),
                               service: PhotoLibraryService(initialAccess: .limited,
                                                            statusProvider: { .limited }))
        await vm.start()
        XCTAssertEqual(vm.viewState, .limited, ".limited + 0 张必须是 .limited，不是 .empty")
        XCTAssertTrue(vm.isLimitedAccess)
    }

    func testLimitedWithAssetsLoadsReadyGrid() async {
        let vm = makeViewModel(repo: AccessRepoFake([makeItem(0), makeItem(1), makeItem(2)]),
                               service: PhotoLibraryService(initialAccess: .limited,
                                                            statusProvider: { .limited }))
        await vm.start()
        XCTAssertEqual(vm.viewState, .ready, ".limited 有可见照片 → 正常网格")
        XCTAssertTrue(vm.isLimitedAccess, "isLimitedAccess 必须正确设置")
    }

    func testAuthorizedZeroAssetsShowsEmpty() async {
        let vm = makeViewModel(repo: AccessRepoFake([]),
                               service: PhotoLibraryService(initialAccess: .authorized,
                                                            statusProvider: { .authorized }))
        await vm.start()
        XCTAssertEqual(vm.viewState, .empty, ".authorized + 0 张必须是 .empty")
        XCTAssertFalse(vm.isLimitedAccess)
    }

    // MARK: - 刷新重载（docs/49 T02 §3.2）

    func testRefreshAccessAndReloadAfterAuthorization() async {
        var status: PHAuthorizationStatus = .denied
        let service = PhotoLibraryService(statusProvider: { status })
        let vm = makeViewModel(repo: AccessRepoFake([makeItem(0)]), service: service)
        await vm.start()
        XCTAssertEqual(vm.viewState, .denied)
        status = .authorized
        await vm.refreshAccessAndReload()
        XCTAssertEqual(vm.viewState, .ready, "denied → authorized 刷新重载后必须进入网格")
        XCTAssertEqual(vm.allItems.count, 1)
    }

    func testForceReloadResetsLoadAndIndexState() async {
        let service = PhotoLibraryService(initialAccess: .authorized,
                                          statusProvider: { .authorized })
        let repo = AccessRepoFake((0..<1_500).map { makeItem($0) })
        repo.completionDelayMs = 150
        let vm = makeViewModel(repo: repo, service: service)
        await vm.start()
        XCTAssertEqual(vm.allItems.count, 500)
        await vm.ensureIndexComplete()
        XCTAssertEqual(vm.isIndexComplete, true)
        await vm.refreshAccessAndReload(force: true)
        XCTAssertEqual(vm.viewState, .ready)
        XCTAssertEqual(vm.allItems.count, 500,
                       "force 重载必须重置 hasLoadedOnce 并回到首屏 500")
        XCTAssertEqual(vm.isIndexComplete, false,
                       "force 重载必须取消旧 indexingTask 并重启完整索引（节流下未完成）")
    }

    func testLimitedPickerNeedsReloadForcesNextRefresh() async {
        let vm = makeViewModel(repo: AccessRepoFake([]),
                               service: PhotoLibraryService(initialAccess: .limited,
                                                            statusProvider: { .limited }))
        await vm.start()
        XCTAssertEqual(vm.viewState, .limited)
        vm.requestManageLimitedPhotos()
        XCTAssertTrue(vm.limitedPickerNeedsReload, "调起 limited 选择器必须置位待重载标志")
        await vm.refreshAccessAndReload()
        XCTAssertFalse(vm.limitedPickerNeedsReload, "标志消费后清零")
        XCTAssertEqual(vm.viewState, .limited, "重载后 0 张仍为 .limited")
    }

    func testRequestAccessReloadsOnlyOnActualChange() async {
        var current: PHAuthorizationStatus = .notDetermined
        let service = PhotoLibraryService(statusProvider: { current },
                                          requestProvider: { current = .authorized; return .authorized })
        let vm = makeViewModel(repo: AccessRepoFake([makeItem(0)]), service: service)
        await vm.start()
        XCTAssertEqual(vm.viewState, .notDetermined)
        await vm.requestAccess()
        XCTAssertEqual(vm.viewState, .ready, "notDetermined → authorized 后必须重载进网格")
        // 再次 requestAccess：授权未变（requestProvider 直接返回 authorized）不重复弹框、不强制重载
        await vm.requestAccess()
        XCTAssertEqual(vm.viewState, .ready)
        XCTAssertEqual(vm.allItems.count, 1)
    }
}
