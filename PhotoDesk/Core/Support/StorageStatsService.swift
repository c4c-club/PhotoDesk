// MARK: - 职责说明：存储统计编排（docs/09 D07）——缓存命中 → 缺失批量取字节（PhotoKitAssetSizeProvider，
// 500/批并发 4 + 进度 + 取消）→ PhotoDeskCore.StorageMath 聚合。取消/超时返回已完成部分（completed=false），
// 绝不永久转圈。聚合纯逻辑在 PhotoDeskCore（红线 2），本类只做编排与缓存读写。

import Foundation
import PhotoDeskCore

@MainActor
final class StorageStatsService: ObservableObject {
    struct Output {
        let summary: StorageSummary
        let itemCount: Int
        /// false = 超时/取消的部分结果（UI 显示「部分 iCloud 资源大小未知」+ 继续统计）
        let completed: Bool
    }

    private let cache: AssetSizeCache?

    init(cache: AssetSizeCache? = AssetSizeCache()) {
        self.cache = cache
    }

    /// - Parameters:
    ///   - items: 全量条目（调用方负责排除 pending 项）
    ///   - provider: 字节来源（真实 PhotoKit / mock）
    ///   - progress: (已统计数, 总数)
    ///   - timeout: 软超时（秒）；到点返回部分结果（由调用方用 watchdog cancel）
    func compute(items: [PhotoItem],
                 provider: AssetSizeProviding,
                 progress: @MainActor @escaping (Int, Int) -> Void) async -> Output {
        // 1. 缓存命中（按 modificationDate 校验）
        var sizes: [String: Int64] = [:]
        var misses: [(id: String, modificationDate: Date?)] = []
        if let cache {
            let cached = cache.bytes(for: items.map { ($0.id, $0.modificationDate) })
            sizes.merge(cached) { _, new in new }
        }
        for item in items where sizes[item.id] == nil {
            misses.append((item.id, item.modificationDate))
        }
        progress(sizes.count, items.count)

        // 2. 缺失批量取（取消 → 已有部分也返回）
        if !misses.isEmpty {
            let fetched = await provider.sizes(for: misses.map(\.id)) { done, total in
                progress(sizes.count + done, items.count)
            }
            for (id, bytes) in fetched {
                sizes[id] = bytes
            }
            // 3. 缓存回写
            if let cache {
                let updates = fetched.compactMap { (id: String, bytes: Int64) -> (String, Date?, Int64)? in
                    guard let item = items.first(where: { $0.id == id }) else { return nil }
                    return (id, item.modificationDate, bytes)
                }
                cache.update(entries: updates)
                cache.save()
            }
        }
        let cancelled = Task.isCancelled

        // 4. 聚合（纯逻辑在 PhotoDeskCore.StorageMath）
        let calendar = Calendar.current
        let entries = items.map { item -> StorageEntry in
            let year = item.creationDate.map { calendar.component(.year, from: $0) }
            return StorageEntry(mediaType: Self.mediaTypeCode(item.mediaType),
                                year: year,
                                bytes: sizes[item.id])
        }
        let summary = StorageMath.summarize(entries)
        return Output(summary: summary,
                      itemCount: items.count,
                      completed: !cancelled)
    }

    private static func mediaTypeCode(_ type: MediaType) -> Int {
        switch type {
        case .image: return 0
        case .video: return 1
        case .unknown: return 2
        }
    }
}
