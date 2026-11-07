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

    func testSchemaVersionAlwaysWrittenAsThree() {
        let (store, defaults) = makeStore()
        store.save(makePosition(), queryKey: "q1")
        guard let data = defaults.data(forKey: "library.lastPosition.v2.q1"),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return XCTFail("位置 JSON 应可解码")
        }
        XCTAssertEqual(json["schemaVersion"] as? Int ?? -1, 3,
                       "M13 P2：默认 schemaVersion 必须抬到 3（HEAD 仍写 2）")
        XCTAssertNotNil(json["anchorAssetID"], "M13 P2：v3 必须写视觉锚点 anchorAssetID")
        XCTAssertNotNil(json["anchorVisualY"], "M13 P2：v3 必须写 anchorVisualY")
        XCTAssertNotNil(json["anchorContentOffsetY"], "M13 P2：v3 必须写 anchorContentOffsetY")
    }

    func testV2LegacyDecodeFallsBackToLegacyAssetFields() throws {
        let (store, defaults) = makeStore()
        let v2JSON = """
        {"assetID":"legacy-1","sectionID":"2023-08","itemIndexInSection":4,"offsetRatio":0.5,"savedAt":700000000.0,"schemaVersion":2}
        """
        defaults.set(Data(v2JSON.utf8), forKey: "library.lastPosition.v2.q1")
        guard let position = store.load(queryKey: "q1") else {
            return XCTFail("v2 数据应可读取")
        }
        XCTAssertEqual(position.schemaVersion, 2)
        XCTAssertEqual(position.itemIndexInSection, 4)
        let mirror = Mirror(reflecting: position)
        let anchor = mirror.children.first { $0.label == "anchorAssetID" }?.value as? String
        let visualY = mirror.children.first { $0.label == "anchorVisualY" }?.value as? Double
        XCTAssertEqual(anchor ?? "", "legacy-1",
                       "M13 P2：v2 缺 anchorAssetID 时必须回退旧 assetID（HEAD 无该字段）")
        XCTAssertEqual(visualY ?? -1, 0,
                       "M13 P2：v2 缺 anchorVisualY 时必须补 0（HEAD 无该字段）")
    }
}