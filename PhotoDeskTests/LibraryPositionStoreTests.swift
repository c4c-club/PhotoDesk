// MARK: - LibraryPositionStoreTests：v5 存储（docs/25 §5.2–5.3 / M15 P0-2）——
// 文件存储读写、v1–v4 UserDefaults 一次性迁移（失败保留旧键）、开关关闭不读写、
// clear/clearAll 同时清文件与遗留键、schemaVersion=5、写入不再落 UserDefaults。

import XCTest
@testable import PhotoDesk

final class LibraryPositionStoreTests: XCTestCase {
    private var dir: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lps-test-\(UUID().uuidString)", isDirectory: true)
        suiteName = "LibraryPositionStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        if !suiteName.isEmpty {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    private func makeStore() -> LibraryPositionStore {
        LibraryPositionStore(fileStore: PositionFileStore(directory: dir), defaults: defaults)
    }

    private func makePosition(assetID: String = "asset-1",
                              sectionID: String = "2024-05",
                              itemIndex: Int = 3,
                              ratio: Double = 0.42) -> LibraryPosition {
        LibraryPosition(anchorAssetID: assetID,
                        anchorVisualY: 42,
                        anchorContentOffsetY: 1_000,
                        assetID: assetID,
                        sectionID: sectionID,
                        itemIndexInSection: itemIndex,
                        offsetRatio: ratio,
                        contentHeight: 8_000,
                        viewportHeight: 844,
                        savedAt: Date())
    }

    func testRoundTripPreservesAllFields() {
        let store = makeStore()
        let position = makePosition()
        store.save(position, queryKey: "q1")
        XCTAssertEqual(store.load(queryKey: "q1"), position)
        XCTAssertEqual(store.load(queryKey: "q1")?.queryKey, "q1", "v5 条目必须自带 queryKey")
    }

    func testV5DoesNotWriteUserDefaults() {
        let store = makeStore()
        store.save(makePosition(), queryKey: "q1")
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.v2.q1"),
                     "v5 不再写 UserDefaults")
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.q1"))
    }

    func testMigrationFromV4UserDefaults() throws {
        // 预置 v4 结构（schemaVersion 4、无 queryKey）→ 新实例必须迁入 v5 文件
        let v4 = LibraryPosition(anchorAssetID: "legacy-4",
                                 anchorVisualY: 55,
                                 anchorContentOffsetY: 1_200,
                                 assetID: "legacy-4",
                                 sectionID: "2024-05",
                                 itemIndexInSection: 7,
                                 offsetRatio: 0.3,
                                 contentHeight: 8_000,
                                 viewportHeight: 844,
                                 savedAt: Date(timeIntervalSince1970: 700_000_000),
                                 schemaVersion: 4)
        let encoded = try JSONEncoder().encode(v4)
        defaults.set(encoded, forKey: "library.lastPosition.v2.q1")
        let store = makeStore()
        let migrated = store.load(queryKey: "q1")
        XCTAssertEqual(migrated?.anchorAssetID, "legacy-4")
        XCTAssertEqual(migrated?.anchorVisualY, 55)
        XCTAssertEqual(migrated?.itemIndexInSection, 7)
        XCTAssertEqual(migrated?.queryKey, "q1")
        XCTAssertNotNil(FileManager.default.contents(atPath: dir.appendingPathComponent("anchors-v5.json").path),
                        "迁移结果必须落 v5 文件")
        XCTAssertNotNil(defaults.data(forKey: "library.lastPosition.v2.q1"),
                        "迁移成功不删除旧键（只读兼容）")
    }

    func testMigrationKeepsLegacyKeyOnDecodeFailure() {
        // 单条损坏：迁移跳过该条、保留旧键，不影响其它条目
        defaults.set(Data("not-a-json{{".utf8), forKey: "library.lastPosition.v2.bad")
        let store = makeStore()
        XCTAssertNil(store.load(queryKey: "bad"))
        XCTAssertNotNil(defaults.data(forKey: "library.lastPosition.v2.bad"),
                        "迁移失败必须保留旧键，不得静默清除")
    }

    func testDisabledSwitchBlocksReadAndWrite() {
        let store = makeStore()
        store.isEnabled = false
        store.save(makePosition(), queryKey: "k")
        XCTAssertNil(store.load(queryKey: "k"), "「记住上次整理位置」关闭后不读写")
        store.isEnabled = true
        store.save(makePosition(), queryKey: "k")
        XCTAssertNotNil(store.load(queryKey: "k"))
    }

    func testPerQueryKeysIndependentAndClearRemovesLegacy() {
        let store = makeStore()
        let p1 = makePosition(assetID: "a")
        let p2 = makePosition(assetID: "b")
        store.save(p1, queryKey: "key1")
        store.save(p2, queryKey: "key2")
        XCTAssertEqual(store.load(queryKey: "key1"), p1)
        defaults.set(Data("{}".utf8), forKey: "library.lastPosition.key1")
        store.clear(queryKey: "key1")
        XCTAssertNil(store.load(queryKey: "key1"))
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.key1"),
                     "clear 必须同时清 v5 文件与遗留键")
        XCTAssertEqual(store.load(queryKey: "key2"), p2)
    }

    func testClearAllRemovesFileEntriesAndLegacyKeys() {
        let store = makeStore()
        store.save(makePosition(), queryKey: "k1")
        store.save(makePosition(), queryKey: "k2")
        defaults.set(Data("{}".utf8), forKey: "library.lastPosition.v2.k3")
        store.clearAll()
        XCTAssertNil(store.load(queryKey: "k1"))
        XCTAssertNil(store.load(queryKey: "k2"))
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.v2.k3"))
        store.flush()
        let reloaded = LibraryPositionStore(fileStore: PositionFileStore(directory: dir), defaults: defaults)
        XCTAssertEqual(reloaded.entryCount, 0, "clearAll 必须落盘")
    }

    func testFlushGuaranteesDurability() {
        let store = makeStore()
        store.save(makePosition(), queryKey: "q1")
        store.flush()
        let reloaded = LibraryPositionStore(fileStore: PositionFileStore(directory: dir), defaults: defaults)
        XCTAssertEqual(reloaded.load(queryKey: "q1")?.anchorAssetID, "asset-1",
                       "flush 后跨实例必须可读（杀进程不丢最后一笔）")
    }

    func testSchemaVersionAlwaysWrittenAsFive() {
        let store = makeStore()
        store.save(makePosition(), queryKey: "q1")
        let decoded = store.load(queryKey: "q1")
        XCTAssertEqual(decoded?.schemaVersion, 5)
        XCTAssertEqual(decoded?.anchorAssetID, "asset-1")
        XCTAssertEqual(decoded?.anchorVisualY, 42)
        XCTAssertEqual(decoded?.anchorContentOffsetY, 1_000)
        XCTAssertEqual(decoded?.itemIndexInSection, 3)
    }

    func testLegacyV1DecodeStillFallsBack() throws {
        // v1 遗留 JSON（无 anchor/schemaVersion）解码兼容
        let v1JSON = """
        {"assetID":"legacy-1","sectionID":"2023-08","offsetRatio":0.5,"savedAt":700000000.0}
        """
        let position = try JSONDecoder().decode(LibraryPosition.self, from: Data(v1JSON.utf8))
        XCTAssertEqual(position.schemaVersion, 1)
        XCTAssertEqual(position.anchorAssetID, "legacy-1", "v1 无 anchorAssetID 时回退 assetID")
        XCTAssertEqual(position.itemIndexInSection, 0)
        XCTAssertEqual(position.queryKey, "", "v1 无 queryKey 补空串")
    }
}
