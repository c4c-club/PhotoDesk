// MARK: - 职责说明：DI 组合根（docs/03 §3 App/AppContainer）——服务装配唯一入口。
// 装配约定（AGENTS.md §3）：Service 全部 protocol 化，ViewModel 经构造器注入；纯逻辑来自 PhotoDeskCore（红线 2）。
// 依赖方向：Features → Domain(ViewModel) → Core(Service) → System（docs/03 §1），本容器是组合根。
// @MainActor：App/UI 侧组合发生在主线程。

import Foundation

@MainActor
final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    let settings = SettingsStore()
    let libraryService = PhotoLibraryService()
    let assetRepository: AssetRepositoryProtocol
    let imagePipeline: ImagePipelineProtocol
    let photoWriter = PhotoWriter()
    /// 撤销倒计时唯一时钟（docs/16 M12 R04：DSToast 环 + UndoCenter 到期共用）
    let undoCountdownDriver = UndoCountdownDriver()
    let undoCenter: UndoCenter
    let trashBin: TrashBin
    let vaultService = VaultService()
    let fingerprintService: FingerprintService
    let scanCoordinator: ScanCoordinator
    /// 会话整理（docs/09 D16）：滑动入队 → 结尾一次批量提交
    let reviewSession: ReviewSessionController
    /// 位置记忆（docs/09 D08）
    let positionStore = LibraryPositionStore()
    /// 存储统计字节缓存（docs/09 D07；JSON 磁盘缓存，按 assetID + modificationDate）
    let statsCache = AssetSizeCache()
    /// 存储统计页每次打开新建（docs/09 D07：批量取字节 + 进度/取消/90s 软超时）
    func makeStorageStatsViewModel() -> StorageStatsViewModel {
        #if DEBUG
        if UITestHooks.enabled("-uiTestingStorageMock") {
            return StorageStatsViewModel(service: StorageStatsService(cache: nil),
                                         provider: MockAssetSizeProvider(),
                                         itemsProvider: { StorageStatsViewModel.mockItems() },
                                         cacheProvider: { nil },
                                         timeoutSeconds: 30)
        }
        #endif
        return StorageStatsViewModel(service: StorageStatsService(cache: statsCache),
                                     provider: PhotoKitAssetSizeProvider(),
                                     itemsProvider: { [weak self] in
            await self?.fetchAllItemsForStats() ?? []
        },
                                     cacheProvider: { [weak self] in self?.statsCache })
    }

    /// 全量条目（统计用；prepare + 500/批补齐，不进主库 VM 状态）
    private func fetchAllItemsForStats() async -> [PhotoItem] {
        let total = await assetRepository.prepare(scope: .all)
        guard total > 0 else { return [] }
        var items: [PhotoItem] = []
        var cursor = 0
        while cursor < total {
            let batch = await assetRepository.fetch(scope: .all, offset: cursor, limit: AssetRepository.batchSize)
            guard !batch.isEmpty else { break }
            items.append(contentsOf: batch)
            cursor += batch.count
        }
        return items
    }
    #if DEBUG
    /// -uiTestingSessionMock：mock writer 调用计数（UI 测试断言「提交恰好 1 次」的信号源）
    let mockPhotoWriter: MockPhotoWriter?
    #endif

    lazy var libraryViewModel = LibraryViewModel(service: libraryService,
                                                 repository: assetRepository,
                                                 pipeline: imagePipeline,
                                                 writer: photoWriter,
                                                 trashBin: trashBin,
                                                 undoCenter: undoCenter,
                                                 settings: settings,
                                                 reviewSession: reviewSession,
                                                 positionStore: positionStore)

    /// 浏览页每次打开新建：按 assetID 定位（docs/09 D01）
    func makeViewerViewModel(context: ViewerContext) -> ViewerViewModel {
        ViewerViewModel(context: context,
                        settings: settings,
                        writer: photoWriter,
                        trashBin: trashBin,
                        undoCenter: undoCenter,
                        reviewSession: reviewSession)
    }

    /// 清理页每次打开新建（扫描结果在 coordinator 单例上，重进不丢）
    func makeCleanupViewModel() -> CleanupViewModel {
        CleanupViewModel(coordinator: scanCoordinator,
                         reviewSession: reviewSession)
    }

    /// 已隐藏页每次打开新建（docs/09 D05：门禁状态 + 合并 pendingHide + observer）
    func makeVaultViewModel() -> VaultViewModel {
        VaultViewModel(vault: vaultService,
                       repository: assetRepository,
                       writer: photoWriter,
                       reviewSession: reviewSession,
                       undoCenter: undoCenter,
                       settings: settings)
    }

    /// App 启动锁（docs/09 D06；独立门禁实例，与保险箱门禁互不干扰）
    let appLock: AppLockController

    /// 导出页每次打开新建
    func makeExportViewModel(item: PhotoItem) -> ExportViewModel {
        ExportViewModel(item: item,
                        pipeline: imagePipeline,
                        writer: photoWriter,
                        settings: settings)
    }

    /// 编辑页每次打开新建
    func makeEditorViewModel(item: PhotoItem) -> EditorViewModel {
        EditorViewModel(item: item, writer: photoWriter, settings: settings)
    }

    private init() {
        let persistence = PersistenceController.shared
        assetRepository = AssetRepository()
        // 捕获 settings 实例本身（不能引用 AppContainer.shared：静态 let 初始化进行中会死锁）
        let settingsRef = settings
        let writerRef = photoWriter
        imagePipeline = ImagePipeline(allowsNetworkAccess: { settingsRef.autoDownloadOriginal })
        trashBin = TrashBin(persistence: persistence, settings: settingsRef)
        undoCenter = UndoCenter(writer: writerRef, trashBin: trashBin, persistence: persistence,
                                countdownDriver: undoCountdownDriver)
        fingerprintService = FingerprintService(persistence: persistence)
        scanCoordinator = ScanCoordinator(repository: assetRepository,
                                          fingerprintService: fingerprintService,
                                          persistence: persistence,
                                          settings: settingsRef)
        appLock = AppLockController(gate: BiometricGate())
        #if DEBUG
        // UI 测试钩子（docs/09 Phase 0）：-uiTestingSessionMock 用 mock writer + 临时目录 store，
        // 避免测试真的删照片；普通启动（无参数）绝不走 mock。
        // mock store 每次启动清空：跨用例/跨重启的持久队列会让计数断言漂移（CI 实测 20+4=24）
        if UITestHooks.enabled("-uiTestingSessionMock") {
            let mock = MockPhotoWriter()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("PendingActions-UITest", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            reviewSession = ReviewSessionController(store: PendingActionStore(directoryOverride: tmp),
                                                    writer: mock,
                                                    trashBin: nil,
                                                    settings: settingsRef)
            mockPhotoWriter = mock
        } else {
            reviewSession = ReviewSessionController(writer: writerRef, trashBin: trashBin, settings: settingsRef)
            mockPhotoWriter = nil
        }
        #else
        reviewSession = ReviewSessionController(writer: writerRef, trashBin: trashBin, settings: settingsRef)
        #endif
    }
}
