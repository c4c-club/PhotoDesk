// MARK: - PositionStoreV6Tests：位置记忆 v6 存储契约（docs/28 §5.3/§5.7 / M16 T03）——
// anchors-v6.json 原子读写、全字段往返、损坏 JSON 备份、容量 64 淘汰、queryKey 隔离、
// v5 文件只读迁移（迁移后 v5 原样保留）、v6 存在时跳过迁移、v1–v4 UserDefaults 迁移、
// isSane 字段有效性（visualY ∈ [0, viewport)、columns ∈ 2...5）。

import XCTest
@testable import PhotoDesk

@MainActor
final class PositionStoreV6Tests: XCTestCase {
    private var dir: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("psv6-test-\(UUID().uuidString)", isDirectory: true)
        suiteName = "PositionStoreV6-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        if !suiteName.isEmpty { defaults.removePersistentDomain(forName: suiteName) }
        super.tearDown()
    }

    private func makeV6(anchor: String = "asset-6",
                        globalIndex: Int? = 512,
                        savedAt: Date = Date(),
                        queryKey: String = "scope.all") -> LibraryPositionV6 {
        LibraryPositionV6(queryKey: queryKey,
                          anchorAssetID: anchor,
                          anchorGlobalIndex: globalIndex,
                          anchorSectionID: "2024-05",
                          anchorSectionItemIndex: 3,
                          anchorVisualY: 42,
                          anchorContentOffsetY: 1_000,
                          gridColumns: 3,
                          contentInsetTop: 104,
                          contentHeight: 12_000,
                          viewportHeight: 844,
                          savedAt: savedAt)
    }

    /// v5 旧文件构造（迁移源）：按 v5 FileModel 结构手写 JSON
    private func writeLegacyV5File(anchor: String, queryKey: String) throws {
        let v5 = LibraryPosition(anchorAssetID: anchor,
                                 anchorVisualY: 55,
                                 anchorContentOffsetY: 1_200,
                                 assetID: anchor,
                                 sectionID: "2024-05",
                                 itemIndexInSection: 7,
                                 offsetRatio: 0.3,
                                 contentHeight: 8_000,
                                 viewportHeight: 844,
                                 savedAt: Date(timeIntervalSince1970: 700_000_000),
                                 schemaVersion: 5,
                                 queryKey: queryKey)
        let entryData = try JSONEncoder().encode(v5)
        let entry = try JSONSerialization.jsonObject(with: entryData) as? [String: Any] ?? [:]
        let fileModel: [String: Any] = ["schemaVersion": 5, "entries": [queryKey: entry]]
        let data = try JSONSerialization.data(withJSONObject: fileModel)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("anchors-v5.json"), options: .atomic)
    }

    // MARK: - 往返与落盘

    func testRoundTripPreservesAllV6Fields() {
        let store = PositionFileStore(directory: dir)
        let position = makeV6()
        store.save(position, queryKey: "scope.all")
        let loaded = store.load(queryKey: "scope.all")
        XCTAssertEqual(loaded, position, "v6 全字段必须往返一致（含 anchorGlobalIndex/gridColumns/inset）")
        XCTAssertEqual(loaded?.anchorGlobalIndex, 512)
        XCTAssertEqual(loaded?.gridColumns, 3)
        XCTAssertEqual(loaded?.queryKey, "scope.all", "存储键必须盖进结构体")
    }

    func testPersistsAcrossInstancesInAnchorsV6File() {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "k1")
        store.save(makeV6(anchor: "a2", queryKey: "k2"), queryKey: "k2")
        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("anchors-v6.json").path))
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertEqual(reloaded.load(queryKey: "k1")?.anchorAssetID, "a1")
        XCTAssertEqual(reloaded.load(queryKey: "k2")?.anchorAssetID, "a2")
    }

    func testSchemaVersionIsSixOnDisk() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(), queryKey: "scope.all")
        store.flush()
        let data = try Data(contentsOf: dir.appendingPathComponent("anchors-v6.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 6)
        let entry = (object?["entries"] as? [String: Any])?["scope.all"] as? [String: Any]
        XCTAssertEqual(entry?["gridColumns"] as? Int, 3, "v6 条目必须携带列数取证字段")
        XCTAssertEqual(entry?["anchorGlobalIndex"] as? Int, 512)
    }

    // MARK: - 损坏 / 容量 / 隔离

    func testCorruptV6JSONIsBackedUpAndStartsEmpty() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "k1")
        store.flush()
        try Data("{{{not json".utf8).write(to: dir.appendingPathComponent("anchors-v6.json"))
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertNil(reloaded.load(queryKey: "k1"), "损坏文件必须按空字典开始")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".corrupt-") }
        XCTAssertEqual(backups.count, 1, "损坏 JSON 必须留 .corrupt-<timestamp> 取证备份")
    }

    func testCapacityEvictsOldestBySavedAt() {
        let store = PositionFileStore(directory: dir)
        let base = Date(timeIntervalSince1970: 2_000_000)
        for index in 0..<PositionFileStore.capacity {
            store.save(makeV6(anchor: "k\(index)",
                              savedAt: base.addingTimeInterval(TimeInterval(index)),
                              queryKey: "key-\(index)"),
                       queryKey: "key-\(index)")
        }
        store.save(makeV6(anchor: "newest", savedAt: base.addingTimeInterval(9_999), queryKey: "key-new"),
                   queryKey: "key-new")
        XCTAssertEqual(store.entryCount, PositionFileStore.capacity, "容量不得超过 64")
        XCTAssertNil(store.load(queryKey: "key-0"), "savedAt 最早者被淘汰")
        XCTAssertNotNil(store.load(queryKey: "key-new"))
    }

    func testQueryKeyIsolation() {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1", queryKey: "k1"), queryKey: "k1")
        store.save(makeV6(anchor: "a2", queryKey: "k2"), queryKey: "k2")
        store.remove(queryKey: "k1")
        XCTAssertNil(store.load(queryKey: "k1"))
        XCTAssertEqual(store.load(queryKey: "k2")?.anchorAssetID, "a2", "删除 k1 不得波及 k2")
        XCTAssertNil(store.load(queryKey: "k3"), "未保存的键必须返回 nil")
    }

    // MARK: - v5 → v6 迁移

    func testMigratesV5FileOnFirstInitAndKeepsV5Untouched() throws {
        try writeLegacyV5File(anchor: "legacy-5", queryKey: "scope.all")
        let v5URL = dir.appendingPathComponent("anchors-v5.json")
        let v5DataBefore = try Data(contentsOf: v5URL)
        let store = PositionFileStore(directory: dir, migratedGridColumns: { 4 })
        let migrated = store.load(queryKey: "scope.all")
        XCTAssertNotNil(migrated, "v5 记录必须迁入 v6")
        XCTAssertEqual(migrated?.anchorAssetID, "legacy-5")
        XCTAssertEqual(migrated?.anchorVisualY, 55)
        XCTAssertEqual(migrated?.anchorSectionItemIndex, 7)
        XCTAssertNil(migrated?.anchorGlobalIndex, "v5 无全量索引 → nil（恢复时按 sectionID 兜底）")
        XCTAssertEqual(migrated?.gridColumns, 4, "迁移列数来自注入的当前设置")
        XCTAssertEqual(migrated?.schemaVersion, 6)
        store.flush()
        XCTAssertEqual(try Data(contentsOf: v5URL), v5DataBefore,
                       "红线：v5 文件只读迁移，原文件一个字节都不能动")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("anchors-v6.json").path),
                      "迁移结果必须落 v6 文件")
    }

    func testMigrationSkippedWhenV6FileAlreadyExists() throws {
        try writeLegacyV5File(anchor: "legacy-5", queryKey: "k5")
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "fresh-6", queryKey: "k6"), queryKey: "k6")
        store.flush()
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertNotNil(reloaded.load(queryKey: "k6"))
        XCTAssertNil(reloaded.load(queryKey: "k5"),
                     "v6 文件已存在 → 迁移只执行一次，不得把旧 v5 再灌进来")
    }

    func testLegacyUserDefaultsMigrationProducesV6Entry() {
        let v4 = LibraryPosition(anchorAssetID: "legacy-4",
                                 anchorVisualY: 66,
                                 anchorContentOffsetY: 1_300,
                                 assetID: "legacy-4",
                                 sectionID: "2024-05",
                                 itemIndexInSection: 9,
                                 offsetRatio: 0.4,
                                 contentHeight: 8_000,
                                 viewportHeight: 844,
                                 savedAt: Date(timeIntervalSince1970: 600_000_000),
                                 schemaVersion: 4)
        let encoded = try! JSONEncoder().encode(v4)
        defaults.set(encoded, forKey: "library.lastPosition.v2.q1")
        let appStore = LibraryPositionStore(fileStore: PositionFileStore(directory: dir),
                                            defaults: defaults)
        let migrated = appStore.load(queryKey: "q1")
        XCTAssertEqual(migrated?.anchorAssetID, "legacy-4")
        XCTAssertEqual(migrated?.schemaVersion, 6)
        XCTAssertEqual(migrated?.queryKey, "q1")
    }

    // MARK: - 字段有效性

    func testSanityValidation() {
        XCTAssertTrue(makeV6().isSane)
        var bad = makeV6()
        bad = LibraryPositionV6(queryKey: "k", anchorAssetID: "a", anchorGlobalIndex: nil,
                                anchorSectionID: "2024-05", anchorSectionItemIndex: 0,
                                anchorVisualY: 900, anchorContentOffsetY: 0, gridColumns: 3,
                                contentInsetTop: 0, contentHeight: 1_000, viewportHeight: 844,
                                savedAt: Date())
        XCTAssertFalse(bad.isSane, "visualY ≥ viewport → 无效记录")
        let narrow = LibraryPositionV6(queryKey: "k", anchorAssetID: "a", anchorGlobalIndex: nil,
                                       anchorSectionID: "2024-05", anchorSectionItemIndex: 0,
                                       anchorVisualY: 10, anchorContentOffsetY: 0, gridColumns: 1,
                                       contentInsetTop: 0, contentHeight: 1_000, viewportHeight: 844,
                                       savedAt: Date())
        XCTAssertFalse(narrow.isSane, "columns 越出 2...5 → 无效记录")
        let noAnchor = LibraryPositionV6(queryKey: "k", anchorAssetID: "", anchorGlobalIndex: nil,
                                         anchorSectionID: "2024-05", anchorSectionItemIndex: 0,
                                         anchorVisualY: 10, anchorContentOffsetY: 0, gridColumns: 3,
                                         contentInsetTop: 0, contentHeight: 1_000, viewportHeight: 844,
                                         savedAt: Date())
        XCTAssertFalse(noAnchor.isSane, "空锚点 → 无效记录")
    }

    func testRemoveAllPersistsInV6File() {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "k1")
        store.removeAll()
        store.flush()
        XCTAssertEqual(store.entryCount, 0)
        XCTAssertEqual(PositionFileStore(directory: dir).entryCount, 0, "removeAll 必须落盘")
    }
}