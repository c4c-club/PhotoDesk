// MARK: - 职责说明：LibraryPositionStore v2 单元测试（docs/13 Phase 5 / S04/S11 验收）——
// v2 读写、v1 兼容解码、损坏 JSON 不崩、itemIndexInSection 保留、clearAll、开关关闭不读写。

import XCTest
@testable import PhotoDesk

final class LibraryPositionStoreTests: XCTestCase {
    private func makeStore() -> (LibraryPositionStore, UserDefaults) {
        let suite = "LibraryPositionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (LibraryPositionStore(defaults: defaults), defaults)
    }

    private func makePosition(assetID: String = "asset-1",
                              sectionID: String = "2024-05",
                              itemIndex: Int = 3,
                              ratio: Double = 0.42) -> LibraryPosition {
        LibraryPosition(assetID: assetID,
                        sectionID: sectionID,
                        itemIndexInSection: itemIndex,
                        offsetRatio: ratio,
                        savedAt: Date())
    }

    func testV2RoundTripPreservesAllFields() {
        let (store, _) = makeStore()
        let position = makePosition()
        store.save(position, queryKey: "q1")
        XCTAssertEqual(store.load(queryKey: "q1"), position)
    }

    func testV2KeySpaceIsSeparateFromV1() {
        let (store, defaults) = makeStore()
        store.save(makePosition(), queryKey: "q1")
        XCTAssertNotNil(defaults.data(forKey: "library.lastPosition.v2.q1"),
                        "v2 写入独立键空间")
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.q1"),
                     "不再写入 v1 键空间")
    }

    func testV1LegacyDataStillLoads() throws {
        let (store, defaults) = makeStore()
        // 手工构造 v1 JSON（无 itemIndexInSection/schemaVersion 字段）
        let v1JSON = """
        {"assetID":"legacy-1","sectionID":"2023-08","offsetRatio":0.5,"savedAt":700000000.0}
        """
        defaults.set(Data(v1JSON.utf8), forKey: "library.lastPosition.q1")
        let position = store.load(queryKey: "q1")
        XCTAssertEqual(position?.assetID, "legacy-1")
        XCTAssertEqual(position?.sectionID, "2023-08")
        XCTAssertEqual(position?.schemaVersion, 1, "v1 数据按版本 1 解析")
        XCTAssertEqual(position?.itemIndexInSection, 0, "v1 缺字段补默认值")
        XCTAssertEqual(position?.offsetRatio, 0.5)
    }

    func testCorruptJSONDoesNotCrashAndReturnsNil() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not-a-json{{".utf8), forKey: "library.lastPosition.v2.q1")
        XCTAssertNil(store.load(queryKey: "q1"), "损坏 JSON → nil（不崩）")
        defaults.set(Data("[]".utf8), forKey: "library.lastPosition.v2.q1")
        XCTAssertNil(store.load(queryKey: "q1"), "结构不符（数组）→ nil")
    }

    func testPerQueryKeysIndependent() {
        let (store, _) = makeStore()
        let p1 = makePosition(assetID: "a", ratio: 0.1)
        let p2 = makePosition(assetID: "b", ratio: 0.2)
        store.save(p1, queryKey: "key1")
        store.save(p2, queryKey: "key2")
        XCTAssertEqual(store.load(queryKey: "key1"), p1)
        store.clear(queryKey: "key1")
        XCTAssertNil(store.load(queryKey: "key1"))
        XCTAssertEqual(store.load(queryKey: "key2"), p2)
    }

    func testClearRemovesBothV1AndV2() {
        let (store, defaults) = makeStore()
        store.save(makePosition(), queryKey: "q1")
        defaults.set(Data("{}".utf8), forKey: "library.lastPosition.q1")
        store.clear(queryKey: "q1")
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.v2.q1"))
        XCTAssertNil(defaults.data(forKey: "library.lastPosition.q1"))
    }

    func testDisabledSwitchBlocksReadAndWrite() {
        let (store, _) = makeStore()
        store.isEnabled = false
        store.save(makePosition(), queryKey: "k")
        XCTAssertNil(store.load(queryKey: "k"), "「记住上次整理位置」关闭后不读写")
    }

    func testClearAllRemovesAllPositionKeys() {
        let (store, _) = makeStore()
        store.save(makePosition(), queryKey: "k1")
        store.save(makePosition(), queryKey: "k2")
        store.clearAll()
        XCTAssertNil(store.load(queryKey: "k1"))
        XCTAssertNil(store.load(queryKey: "k2"))
    }

    func testSchemaVersionAlwaysWrittenAsFour() {
        let (store, defaults) = makeStore()
        let position = LibraryPosition(anchorAssetID: "asset-1",
                                       anchorVisualY: 42,
                                       anchorContentOffsetY: 1000,
                                       assetID: "asset-1",
                                       sectionID: "2024-05",
                                       itemIndexInSection: 3,
                                       offsetRatio: 0.42,
                                       savedAt: Date())
        store.save(position, queryKey: "q1")
        guard let data = defaults.data(forKey: "library.lastPosition.v2.q1"),
              let decoded = try? JSONDecoder().decode(LibraryPosition.self, from: data) else {
            return XCTFail("v4 数据应可解码")
        }
        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.anchorAssetID, "asset-1")
        XCTAssertEqual(decoded.anchorVisualY, 42)
        XCTAssertEqual(decoded.anchorContentOffsetY, 1000)
        XCTAssertEqual(decoded.itemIndexInSection, 3)
    }

    func testV2LegacyDecodeFallsBackToLegacyAssetFields() throws {
        let (store, defaults) = makeStore()
        let v2JSON = """
        {"assetID":"legacy-1","sectionID":"2023-08","itemIndexInSection":4,"offsetRatio":0.5,"savedAt":700000000.0,"schemaVersion":2}
        """
        defaults.set(Data(v2JSON.utf8), forKey: "library.lastPosition.v2.q1")
        let position = store.load(queryKey: "q1")
        XCTAssertEqual(position?.schemaVersion, 2)
        XCTAssertEqual(position?.anchorAssetID, "legacy-1", "v2 无 anchorAssetID 时回退旧 assetID")
        XCTAssertEqual(position?.anchorVisualY, 0)
        XCTAssertEqual(position?.anchorContentOffsetY, 0)
        XCTAssertEqual(position?.itemIndexInSection, 4)
    }
}
