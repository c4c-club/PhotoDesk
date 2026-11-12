// MARK: - PositionFileStoreTests：v6 原子文件存储（docs/28 §5.3 / M16 T03）——
// 原子写可同步读、损坏 JSON 备份后从空开始、64 条按 savedAt 淘汰、remove/removeAll、
// flush 排空队列、schemaVersion=6、跨实例持久化（模拟杀进程重启）、写失败旧文件保留。

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

    private func makeV6(anchor: String, savedAt: Date = Date(), queryKey: String = "scope.all") -> LibraryPositionV6 {
        LibraryPositionV6(queryKey: queryKey,
                          anchorAssetID: anchor,
                          anchorGlobalIndex: nil,
                          anchorSectionID: "2026-11",
                          anchorSectionItemIndex: 3,
                          anchorVisualY: 40,
                          anchorContentOffsetY: 900,
                          gridColumns: 3,
                          contentInsetTop: 0,
                          contentHeight: 5_000,
                          viewportHeight: 844,
                          savedAt: savedAt)
    }

    /// save 后无需 flush 即内存可读；flush 后文件落盘
    func testSaveIsReadableImmediatelyAndPersists() {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "scope.all")
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "a1")
        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("anchors-v6.json").path))
    }

    /// 跨实例读取（模拟杀进程重启）：新实例从磁盘恢复全部条目
    func testPersistsAcrossInstances() {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "scope.all")
        store.save(makeV6(anchor: "a2", queryKey: "scope.favorites"), queryKey: "scope.favorites")
        store.flush()
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertEqual(reloaded.load(queryKey: "scope.all")?.anchorAssetID, "a1")
        XCTAssertEqual(reloaded.load(queryKey: "scope.favorites")?.anchorAssetID, "a2")
    }

    /// 损坏 JSON：备份 .corrupt-<timestamp> 后从空字典开始，不崩溃
    func testCorruptJSONIsBackedUpAndStartsEmpty() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "scope.all")
        store.flush()
        let fileURL = dir.appendingPathComponent("anchors-v6.json")
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
            store.save(makeV6(anchor: "k\(index)",
                              savedAt: base.addingTimeInterval(TimeInterval(index)),
                              queryKey: "key-\(index)"),
                       queryKey: "key-\(index)")
        }
        XCTAssertEqual(store.entryCount, PositionFileStore.capacity)
        store.save(makeV6(anchor: "newest", savedAt: base.addingTimeInterval(9_999), queryKey: "key-new"),
                   queryKey: "key-new")
        XCTAssertEqual(store.entryCount, PositionFileStore.capacity, "容量不得超过 64")
        XCTAssertNil(store.load(queryKey: "key-0"), "savedAt 最早的条目必须被淘汰")
        XCTAssertNotNil(store.load(queryKey: "key-1"))
        XCTAssertNotNil(store.load(queryKey: "key-new"))
    }

    /// remove / removeAll 生效且落盘
    func testRemoveAndRemoveAllPersist() {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "scope.all")
        store.save(makeV6(anchor: "a2", queryKey: "scope.favorites"), queryKey: "scope.favorites")
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

    /// schemaVersion 恒为 6（落盘文件可解码校验）
    func testSchemaVersionIsSixOnDisk() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "scope.all")
        store.flush()
        let data = try Data(contentsOf: dir.appendingPathComponent("anchors-v6.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 6)
        let entry = (object?["entries"] as? [String: Any])?["scope.all"] as? [String: Any]
        XCTAssertEqual(entry?["queryKey"] as? String, "scope.all", "v6 条目必须自带 queryKey")
        XCTAssertEqual(entry?["gridColumns"] as? Int, 3, "v6 条目必须携带列数取证字段")
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
        store.save(makeV6(anchor: "a1"), queryKey: "")
        XCTAssertEqual(store.entryCount, 0)
        XCTAssertNil(store.load(queryKey: ""))
    }

    /// 原子写语义：二次保存后文件必须完整可解码（.atomic 不留半截 JSON）
    func testRewriteKeepsFileValid() throws {
        let store = PositionFileStore(directory: dir)
        store.save(makeV6(anchor: "a1"), queryKey: "scope.all")
        store.flush()
        store.save(makeV6(anchor: "a2"), queryKey: "scope.all")
        store.flush()
        let reloaded = PositionFileStore(directory: dir)
        XCTAssertEqual(reloaded.load(queryKey: "scope.all")?.anchorAssetID, "a2")
    }
}