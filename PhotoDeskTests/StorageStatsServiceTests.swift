// MARK: - 职责说明：存储统计服务/缓存单元测试（docs/09 Phase 6）——mock provider：
// 聚合正确、进度回调、取消返回部分结果、缓存命中跳过查询、modificationDate 失效重算。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

@MainActor
private final class ScriptedSizeProvider: AssetSizeProviding {
    let sizesToReturn: [String: Int64]
    private(set) var callCount = 0

    init(sizes: [String: Int64]) {
        sizesToReturn = sizes
    }

    func sizes(for ids: [String],
               progress: @MainActor @escaping (Int, Int) -> Void) async -> [String: Int64] {
        callCount += 1
        var result: [String: Int64] = [:]
        var done = 0
        for id in ids {
            if Task.isCancelled { break }
            result[id] = sizesToReturn[id] ?? 1_000
            done += 1
            progress(done, ids.count)
        }
        return result
    }
}

@MainActor
final class StorageStatsServiceTests: XCTestCase {
    private func item(_ id: String, type: MediaType = .image, year: Int) -> PhotoItem {
        var components = DateComponents()
        components.year = year
        components.month = 6
        components.day = 1
        let date = Calendar.current.date(from: components)
        return PhotoItem(id: id,
                         mediaType: type,
                         mediaSubtypes: [],
                         creationDate: date,
                         modificationDate: nil,
                         pixelWidth: 1, pixelHeight: 1, duration: 0,
                         isFavorite: false, isHidden: false,
                         location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    func testAggregationWithMockProvider() async {
        let items = [item("a", year: 2024), item("b", type: .video, year: 2024), item("c", year: 2023)]
        let provider = ScriptedSizeProvider(sizes: ["a": 100, "b": 300, "c": 50])
        let service = StorageStatsService(cache: nil)
        var progressCalls: [(Int, Int)] = []
        let output = await service.compute(items: items, provider: provider) { done, total in
            progressCalls.append((done, total))
        }
        XCTAssertTrue(output.completed)
        XCTAssertEqual(output.itemCount, 3)
        XCTAssertEqual(output.summary.totalBytes, 450)
        XCTAssertEqual(output.summary.photoBytes, 150)
        XCTAssertEqual(output.summary.videoBytes, 300)
        XCTAssertEqual(output.summary.byYear[2024], 400)
        XCTAssertEqual(output.summary.byYear[2023], 50)
        XCTAssertFalse(progressCalls.isEmpty, "进度有回调")
    }

    func testUnknownSizesCounted() async {
        let items = [item("known", year: 2024), item("unknown", year: 2024)]
        // provider 只返回一半（模拟 iCloud-only 取不到）
        let provider = ScriptedSizeProvider(sizes: ["known": 100])
        let service = StorageStatsService(cache: nil)
        let output = await service.compute(items: items, provider: provider) { _, _ in }
        XCTAssertEqual(output.summary.unknownCount, 1, "取不到字节 → 未知计数")
        XCTAssertEqual(output.summary.totalBytes, 100)
    }

    func testCancellationReturnsPartial() async {
        let items = (0..<10).map { item("id-\($0)", year: 2024) }
        // 取消任务的 provider：立刻取消 → 返回空/部分
        let provider = ScriptedSizeProvider(sizes: [:])
        let service = StorageStatsService(cache: nil)
        let task = Task {
            await service.compute(items: items, provider: provider) { _, _ in }
        }
        task.cancel()
        let output = await task.value
        XCTAssertFalse(output.completed, "取消 → completed=false（部分结果）")
    }

    func testCacheHitSkipsProvider() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatsCacheTests-\(UUID().uuidString)", isDirectory: true)
        let cache = AssetSizeCache(directoryOverride: tmp)
        let items = [item("a", year: 2024)]
        cache.update(entries: [("a", items[0].modificationDate, 777)])
        cache.save()

        let provider = ScriptedSizeProvider(sizes: [:])
        let service = StorageStatsService(cache: cache)
        let output = await service.compute(items: items, provider: provider) { _, _ in }
        XCTAssertEqual(provider.callCount, 0, "缓存全命中 → 不查 PhotoKit（<1s）")
        XCTAssertEqual(output.summary.totalBytes, 777)
    }

    func testCacheInvalidatedByModificationDate() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatsCacheTests-\(UUID().uuidString)", isDirectory: true)
        let cache = AssetSizeCache(directoryOverride: tmp)
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        cache.update(entries: [("a", oldDate, 100)])
        // modificationDate 变化 → 重算
        let changed = PhotoItem(id: "a",
                                mediaType: .image,
                                mediaSubtypes: [],
                                creationDate: nil,
                                modificationDate: Date(timeIntervalSince1970: 2_000_000),
                                pixelWidth: 1, pixelHeight: 1, duration: 0,
                                isFavorite: false, isHidden: false,
                                location: nil, burstIdentifier: nil, isCloudOnly: false)
        let provider = ScriptedSizeProvider(sizes: ["a": 999])
        let service = StorageStatsService(cache: cache)
        let output = await service.compute(items: [changed], provider: provider) { _, _ in }
        XCTAssertEqual(provider.callCount, 1, "modificationDate 变化 → 重算")
        XCTAssertEqual(output.summary.totalBytes, 999)
        // 重算后缓存更新
        cache.update(entries: [("a", changed.modificationDate, 999)])
        XCTAssertEqual(cache.bytes(for: [("a", changed.modificationDate)])["a"], 999)
    }
}
