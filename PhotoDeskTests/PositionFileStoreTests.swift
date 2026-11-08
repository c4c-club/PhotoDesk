// MARK: - PositionFileStoreTests：v5 原子文件存储（docs/25 §5.3 / M15 P0-2，≥8 条）——
// 原子写可同步读、损坏 JSON 备份后从空开始、64 条按 savedAt 淘汰、remove/removeAll、
// flush 排空队列、schemaVersion=5、跨实例持久化（模拟杀进程重启）。

import XCTest
@testable import PhotoDesk

@MainActor
final class PositionFileStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pfs-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makePosition(anchor: String, savedAt: Date = Date(), queryKey: String = "scope.all") -> LibraryPosition {
        LibraryPosition(anchorAssetID: anchor,
                        anchorVisualY: 40,
                        anchorContentOffsetY: 900,
                        assetID: anchor,
                        sectionID: "2026-11",
                        itemIndexInSection: 3,
                        offsetRatio: 0.2,
                        contentHeight: 5_000,
                        viewportHeight: 844,
                        savedAt: savedAt,
                        queryKey: queryKey)
    }

    /// save 后无需 flush 即内存可读；flush 后文件落盘
    func testSaveIsReadableImmediatelyAndPersists() {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "scope.all")
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "a1")
        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("anchors-v5.json").path))
    }

    /// 跨实例读取（模拟杀进程重启）：新实例从磁盘恢复全部条目
    func testPersistsAcrossInstances() {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "scope.all")
        store.save(makePosition(anchor: "a2", queryKey: "scope.favorites"), queryKey: "scope.favorites")
        store.flush()
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertEqual(reloaded.load(queryKey: "scope.all")?.anchorAssetID, "a1")
        XCTAssertEqual(reloaded.load(queryKey: "scope.favorites")?.anchorAssetID, "a2")
    }

    /// 损坏 JSON：备份 .corrupt-<timestamp> 后从空字典开始，不崩溃
    func testCorruptJSONIsBackedUpAndStartsEmpty() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "scope.all")
        store.flush()
        let fileURL = dir.appendingPathComponent("anchors-v5.json")
        try Data("{{{not json".utf8).write(to: fileURL)
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertNil(reloaded.load(queryKey: "scope.all"), "损坏文件必须按空字典开始")
        XCTAssertNil(reloaded.load(queryKey: "scope.favorites"))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".corrupt-") }
        XCTAssertEqual(backups.count, 1, "损坏 JSON 必须留 .corrupt-<timestamp> 取证备份")
    }

    /// 64 条容量上限：第 65 条写入后按 savedAt 淘汰最旧
    func testCapacityEvictsOldestBySavedAt() {
        let store = PositionFileStore(directory: dir)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<PositionFileStore.capacity {
            store.save(makePosition(anchor: "k\(index)",
                                    savedAt: base.addingTimeInterval(TimeInterval(index)),
                                    queryKey: "key-\(index)"),
                       queryKey: "key-\(index)")
        }
        XCTAssertEqual(store.entryCount, PositionFileStore.capacity)
        // 最旧的 key-0 再保留，写入新条目 → 淘汰 savedAt 最早的
        store.save(makePosition(anchor: "newest", savedAt: base.addingTimeInterval(9_999), queryKey: "key-new"),
                   queryKey: "key-new")
        XCTAssertEqual(store.entryCount, PositionFileStore.capacity, "容量不得超过 64")
        XCTAssertNil(store.load(queryKey: "key-0"), "savedAt 最早的条目必须被淘汰")
        XCTAssertNotNil(store.load(queryKey: "key-1"))
        XCTAssertNotNil(store.load(queryKey: "key-new"))
    }

    /// remove / removeAll 生效且落盘
    func testRemoveAndRemoveAllPersist() {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "scope.all")
        store.save(makePosition(anchor: "a2", queryKey: "scope.favorites"), queryKey: "scope.favorites")
        store.remove(queryKey: "scope.all")
        store.flush()
        XCTAssertNil(store.load(queryKey: "scope.all"))
        XCTAssertNotNil(store.load(queryKey: "scope.favorites"))
        store.removeAll()
        store.flush()
        XCTAssertEqual(store.entryCount, 0)
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertEqual(reloaded.entryCount, 0, "removeAll 必须落盘")
    }

    /// schemaVersion 恒为 5（落盘文件可解码校验）
    func testSchemaVersionIsFiveOnDisk() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "scope.all")
        store.flush()
        let data = try Data(contentsOf: dir.appendingPathComponent("anchors-v5.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 5)
        let entries = object?["entries"] as? [String: Any]
        let entry = entries?["scope.all"] as? [String: Any]
        XCTAssertEqual(entry?["queryKey"] as? String, "scope.all", "v5 条目必须自带 queryKey")
    }

    /// flush 在无写入时安全（幂等）
    func testFlushIsIdempotent() {
        let store = PositionFileStore(directory: dir)
        store.flush()
        store.flush()
        XCTAssertEqual(store.entryCount, 0)
    }

    /// 空 queryKey 拒绝写入（防御）
    func testEmptyQueryKeyIsRejected() {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "")
        XCTAssertEqual(store.entryCount, 0)
        XCTAssertNil(store.load(queryKey: ""))
    }

    /// 原子写语义：写入过程被中断不留半截文件（用覆盖已有合法文件后的再次保存校验内容完整）
    func testRewriteKeepsFileValid() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makePosition(anchor: "a1"), queryKey: "scope.all")
        store.flush()
        store.save(makePosition(anchor: "a2"), queryKey: "scope.all")
        store.flush()
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertEqual(reloaded.load(queryKey: "scope.all")?.anchorAssetID, "a2",
                       "二次写入后文件必须完整可解码（.atomic 不留半截 JSON）")
    }
}
