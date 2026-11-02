// MARK: - 职责说明：存储统计页状态机（docs/09 D07）——idle/computing/done(partial?)/cancelled；
// 90 秒软超时（watchdog cancel → 返回部分结果）；取消立即停止；pending 项排除；
// 缓存命中 < 1s；-uiTestingStorageMock 注入 mock provider 与固定数据（5 秒内出结果）。

import Foundation
import Photos
import PhotoDeskCore

@MainActor
final class StorageStatsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case computing
        case done(partial: Bool)
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: (done: Int, total: Int) = (0, 0)
    @Published private(set) var summary = StorageSummary()
    @Published private(set) var itemCount = 0
    @Published private(set) var partialCount = 0   // 未完成时已统计的项数（脚注用）

    private let service: StorageStatsService
    private let provider: AssetSizeProviding
    private let itemsProvider: () async -> [PhotoItem]
    private var computeTask: Task<Void, Never>?
    /// 软超时（docs/09 D07：90 秒）
    private let timeoutSeconds: TimeInterval
    /// watchdog 触发的软超时（区别于用户取消：超时要展示部分结果）
    private var didTimeout = false
    private let cacheProvider: () -> AssetSizeCache?

    init(service: StorageStatsService,
         provider: AssetSizeProviding,
         itemsProvider: @escaping () async -> [PhotoItem],
         cacheProvider: @escaping () -> AssetSizeCache? = { nil },
         timeoutSeconds: TimeInterval = 90) {
        self.service = service
        self.provider = provider
        self.itemsProvider = itemsProvider
        self.cacheProvider = cacheProvider
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - 启动 / 取消

    /// - Parameter forceRefresh: true = 忽略缓存重算（下拉刷新）
    func start(forceRefresh: Bool = false) async {
        guard phase != .computing else { return }
        phase = .computing
        progress = (done: 0, total: 0)
        partialCount = 0
        didTimeout = false

        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(forceRefresh: forceRefresh)
        }
        computeTask = task
        // 软超时 watchdog（docs/09 D07：到点 cancel → compute 返回部分结果，不永久转圈）
        Task { [weak self, weak task] in
            try? await Task.sleep(nanoseconds: UInt64((self?.timeoutSeconds ?? 90) * 1_000_000_000))
            guard let task, !task.isCancelled else { return }
            self?.didTimeout = true
            task.cancel()
        }
        await task.value
    }

    private func run(forceRefresh: Bool) async {
        var items = await itemsProvider()
        // 排除 pending 项（docs/09 D16 §6：统计不包含待删除/待隐藏）
        let session = AppContainer.shared.reviewSession
        let pending = Set(session.session.pendingDeleteIDs).union(session.session.pendingHideIDs)
        if !pending.isEmpty {
            items = items.filter { !pending.contains($0.id) }
        }
        guard !items.isEmpty else {
            summary = StorageSummary()
            itemCount = 0
            phase = .done(partial: false)
            return
        }
        itemCount = items.count
        let service = forceRefresh ? StorageStatsService(cache: nil) : StorageStatsService(cache: cacheProvider())
        let output = await service.compute(items: items,
                                           provider: provider,
                                           progress: { [weak self] done, total in
            self?.progress = (done: done, total: total)
        })
        // 用户主动取消 → cancelled 态（不更新结果）；软超时 → 部分结果展示
        if Task.isCancelled && !didTimeout {
            phase = .cancelled
            return
        }
        summary = output.summary
        partialCount = output.completed ? 0 : progress.done
        phase = .done(partial: !output.completed)
    }

    func cancel() {
        computeTask?.cancel()
        phase = .cancelled
    }

    /// 继续统计（超时后的部分结果 → 重跑，缓存让已完成的秒回）
    func resume() async {
        await start()
    }

    // MARK: - mock（UI 测试）

    #if DEBUG
    static func mockItems(count: Int = 100) -> [PhotoItem] {
        (0..<count).map { index in
            PhotoItem(id: "mock-\(index)",
                      mediaType: index % 4 == 3 ? .video : .image,
                      mediaSubtypes: [],
                      creationDate: Date(timeIntervalSince1970: 1_600_000_000 + TimeInterval(index * 86_400 * 7)),
                      modificationDate: nil,
                      pixelWidth: 100, pixelHeight: 100, duration: 0,
                      isFavorite: false, isHidden: false,
                      location: nil, burstIdentifier: nil, isCloudOnly: false)
        }
    }
    #endif
}
