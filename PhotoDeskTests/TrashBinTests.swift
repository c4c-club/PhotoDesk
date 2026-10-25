// MARK: - 职责说明：TrashBin 单元测试（docs/05 M3 验收）——
// 副本索引持久化往返、容量淘汰（最老先删 + 文件清理）、副本文件缺失时 restore 报错。
// storeCopy/restore 的 PhotoKit 全流程需相册授权（单元测试宿主无授权），由真机/P-3 手动验证。

import CoreData
import XCTest
@testable import PhotoDesk

@MainActor
final class TrashBinTests: XCTestCase {
    private func makeBin(limit: Int64? = nil) -> TrashBin {
        TrashBin(persistence: PersistenceController(inMemory: true),
                 settings: SettingsStore(),
                 limitBytesOverride: limit)
    }

    private func makeRecord(id: UUID, path: String, byteSize: Int64, age: TimeInterval) -> TrashRecord {
        TrashRecord(id: id,
                    originLocalID: "asset-\(id.uuidString.prefix(4))",
                    fileRelativePath: path,
                    mediaType: 0,
                    byteSize: byteSize,
                    meta: TrashMeta(creationDate: Date(timeIntervalSinceNow: -age),
                                    latitude: 31.23,
                                    longitude: 121.47,
                                    pixelWidth: 100,
                                    pixelHeight: 100,
                                    utType: "public.jpeg"),
                    createdAt: Date(timeIntervalSinceNow: -age))
    }

    private func writeFile(_ bin: TrashBin, name: String, bytes: Int) throws {
        let url = bin.directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testRecordRoundTrip() {
        let bin = makeBin()
        let record = makeRecord(id: UUID(), path: "test-1.jpg", byteSize: 123, age: 0)
        bin.upsert(record)

        let fetched = bin.record(id: record.id)
        XCTAssertEqual(fetched?.originLocalID, record.originLocalID)
        XCTAssertEqual(fetched?.byteSize, 123)
        XCTAssertEqual(fetched?.meta.latitude ?? 0, 31.23, accuracy: 0.0001)
        XCTAssertEqual(bin.allRecords().count, 1)
    }

    func testEvictionRemovesOldestWithFile() async {
        let bin = makeBin(limit: 1000)
        let old = makeRecord(id: UUID(), path: "old.jpg", byteSize: 600, age: 100)
        let new = makeRecord(id: UUID(), path: "new.jpg", byteSize: 600, age: 10)
        bin.upsert(old)
        bin.upsert(new)
        try? writeFile(bin, name: "old.jpg", bytes: 600)
        try? writeFile(bin, name: "new.jpg", bytes: 600)

        await bin.evictIfNeeded()

        // 总量 1200 > 上限 1000：最老的 old 被淘汰（文件 + 索引），new 保留
        XCTAssertNil(bin.record(id: old.id))
        XCTAssertNotNil(bin.record(id: new.id))
        XCTAssertFalse(bin.directory.appendingPathComponent("old.jpg").exists())
        XCTAssertTrue(bin.directory.appendingPathComponent("new.jpg").exists())
    }

    func testNoEvictionUnderLimit() async {
        let bin = makeBin(limit: 1000)
        let only = makeRecord(id: UUID(), path: "only.jpg", byteSize: 400, age: 100)
        bin.upsert(only)
        try? writeFile(bin, name: "only.jpg", bytes: 400)

        await bin.evictIfNeeded()

        XCTAssertNotNil(bin.record(id: only.id))
    }

    func testRestoreThrowsWhenFileMissing() async {
        let bin = makeBin()
        let record = makeRecord(id: UUID(), path: "missing.jpg", byteSize: 100, age: 0)
        bin.upsert(record)

        do {
            _ = try await bin.restore(recordID: record.id)
            XCTFail("副本文件缺失应抛错")
        } catch {
            // 预期：recordNotFound（副本被淘汰/文件丢失）
        }
    }

    func testPurgeRemovesRowAndFile() {
        let bin = makeBin()
        let record = makeRecord(id: UUID(), path: "purge.jpg", byteSize: 50, age: 0)
        bin.upsert(record)
        try? writeFile(bin, name: "purge.jpg", bytes: 50)

        bin.purge(id: record.id)

        XCTAssertNil(bin.record(id: record.id))
        XCTAssertFalse(bin.directory.appendingPathComponent("purge.jpg").exists())
    }
}

private extension URL {
    func exists() -> Bool { FileManager.default.fileExists(atPath: path) }
}
