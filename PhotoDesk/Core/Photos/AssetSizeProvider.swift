// MARK: - 职责说明：资产字节批量提供（docs/09 D07 ★）——
// 每 500 个 id 一次 PHAsset.fetchAssets（禁止逐张查询）；每批在 detached utility 任务里枚举
// PHAssetResource 取字节；批间并发上限 4；逐批进度回调；Task.checkCancellation 支持取消。
// 协议化供 StorageStatsService 单测（mock）。iCloud-only 取不到字节 → 缺失（视为未知大小）。

import Foundation
import Photos

protocol AssetSizeProviding: AnyObject {
    /// - Parameter progress: (已统计数, 总数)——@MainActor 闭包
    func sizes(for ids: [String],
               progress: @MainActor @escaping (Int, Int) -> Void) async -> [String: Int64]
}

@MainActor
final class PhotoKitAssetSizeProvider: AssetSizeProviding {
    static let batchSize = 500
    static let maxConcurrentBatches = 4

    func sizes(for ids: [String],
               progress: @MainActor @escaping (Int, Int) -> Void) async -> [String: Int64] {
        guard !ids.isEmpty else { return [:] }
        let batches = stride(from: 0, to: ids.count, by: Self.batchSize).map {
            Array(ids[$0..<Swift.min($0 + Self.batchSize, ids.count)])
        }
        var result: [String: Int64] = [:]
        var done = 0

        // 批间并发上限 4（滑动窗口）
        var index = 0
        while index < batches.count && !Task.isCancelled {
            let window = Array(batches[index..<Swift.min(index + Self.maxConcurrentBatches, batches.count)])
            let windowResults = await withTaskGroup(of: [String: Int64].self) { group -> [[String: Int64]] in
                for batch in window {
                    group.addTask(priority: .utility) {
                        Self.batchSizes(ids: batch)
                    }
                }
                var collected: [[String: Int64]] = []
                for await batchResult in group {
                    collected.append(batchResult)
                }
                return collected
            }
            for batchResult in windowResults {
                result.merge(batchResult) { _, new in new }
                done += batchResult.count
            }
            progress(min(done, ids.count), ids.count)
            index += Self.maxConcurrentBatches
        }
        return result
    }

    /// 单批：一次 fetch + detached 枚举 PHAssetResource（photos 中已含 KVC fileSize 封装）
    private nonisolated static func batchSizes(ids: [String]) -> [String: Int64] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var out: [String: Int64] = [:]
        out.reserveCapacity(assets.count)
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            out[asset.localIdentifier] = asset.fileSizeBytes
        }
        return out
    }
}

#if DEBUG
/// mock（UI 测试 -uiTestingStorageMock / 单测）：确定性 100 项，每项 1MB × (i+1)
@MainActor
final class MockAssetSizeProvider: AssetSizeProviding {
    let delayPerBatch: UInt64

    init(delayPerBatch: UInt64 = 100_000_000) {
        self.delayPerBatch = delayPerBatch
    }

    func sizes(for ids: [String],
               progress: @MainActor @escaping (Int, Int) -> Void) async -> [String: Int64] {
        var result: [String: Int64] = [:]
        var done = 0
        for (index, id) in ids.enumerated() {
            if index > 0, index % PhotoKitAssetSizeProvider.batchSize == 0 {
                try? await Task.sleep(nanoseconds: delayPerBatch)
                if Task.isCancelled { break }
            }
            // 确定性大小：id 哈希稳定源用索引（调用方 ids 顺序稳定）
            result[id] = Int64(1_000_000 + index % 9 * 250_000)
            done += 1
            progress(done, ids.count)
        }
        return result
    }
}
#endif
