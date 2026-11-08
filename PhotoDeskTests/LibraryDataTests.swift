// MARK: - 职责说明：数据层单元测试（docs/09 Phase 1）——LibraryQuery 跨进程稳定键（禁 hashValue）、
// PhotoItem 身份语义只按 id、DateSectionizerAdapter 升序透传、LibraryPositionStore 存取与清理。

import XCTest
import CoreLocation
import PhotoDeskCore
@testable import PhotoDesk

final class LibraryDataTests: XCTestCase {

    // MARK: - LibraryQuery 稳定键

    func testQueryKeyStableAcrossInstantiations() {
        let a = LibraryQuery(scope: .all, filter: .default, sortAscending: false)
        let b = LibraryQuery(scope: .all, filter: .default, sortAscending: false)
        XCTAssertEqual(a.key, b.key, "同输入同键——重启后位置记忆不丢")
        XCTAssertNotEqual(a.key, "")
    }

    func testQueryKeyDiffersBySort() {
        let desc = LibraryQuery(scope: .all, filter: .default, sortAscending: false)
        let asc = LibraryQuery(scope: .all, filter: .default, sortAscending: true)
        XCTAssertNotEqual(desc.key, asc.key)
    }

    func testQueryKeyDiffersByScope() {
        let all = LibraryQuery(scope: .all, filter: .default, sortAscending: false)
        let fav = LibraryQuery(scope: .favorites, filter: .default, sortAscending: false)
        XCTAssertNotEqual(all.key, fav.key)
    }

    func testQueryKeyDiffersByFilter() {
        var filter = SearchPredicate.default
        filter.year = 2023
        let withFilter = LibraryQuery(scope: .all, filter: filter, sortAscending: false)
        let without = LibraryQuery(scope: .all, filter: .default, sortAscending: false)
        XCTAssertNotEqual(withFilter.key, without.key)
    }

    func testQueryKeyDiffersByLocationFilter() {
        var near = SearchPredicate.default
        near.location = .near(GeoRegion(center: GeoPoint(latitude: 31.2, longitude: 121.5), radiusKm: 25))
        let withLocation = LibraryQuery(scope: .all, filter: near, sortAscending: false)
        let without = LibraryQuery(scope: .all, filter: .default, sortAscending: false)
        XCTAssertNotEqual(withLocation.key, without.key)
    }

    func testPredicateCodableRoundTripPreservesKey() throws {
        var filter = SearchPredicate.default
        filter.year = 2023
        filter.month = 5
        filter.media = [.video, .live]
        filter.location = .withLocation
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(filter)
        let decoded = try JSONDecoder().decode(SearchPredicate.self, from: data)
        let keyA = LibraryQuery.stableKey(scope: .all, filter: filter, sortAscending: false)
        let keyB = LibraryQuery.stableKey(scope: .all, filter: decoded, sortAscending: false)
        XCTAssertEqual(keyA, keyB, "canonical JSON 编解码后键不变")
    }

    // MARK: - PhotoItem 身份语义（docs/09 Phase 1：只按 id）

    private func makeItem(id: String, favorite: Bool = false) -> PhotoItem {
        PhotoItem(id: id,
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                  modificationDate: nil,
                  pixelWidth: 100,
                  pixelHeight: 100,
                  duration: 0,
                  isFavorite: favorite,
                  isHidden: false,
                  location: nil,
                  burstIdentifier: nil,
                  isCloudOnly: false)
    }

    func testPhotoItemEqualityByIdOnly() {
        let a = makeItem(id: "x", favorite: false)
        let b = makeItem(id: "x", favorite: true)   // 收藏标志不同
        XCTAssertEqual(a, b, "收藏/隐藏变化不应产生「删除+插入」diff")
        XCTAssertEqual(a.hashValue, b.hashValue, "hash 只按 id")
    }

    func testPhotoItemInequalityById() {
        XCTAssertNotEqual(makeItem(id: "x"), makeItem(id: "y"))
    }

    func testPhotoItemSetDeduplicatesById() {
        let set = Set([makeItem(id: "x"), makeItem(id: "x", favorite: true), makeItem(id: "y")])
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - DateSectionizerAdapter 升序透传

    func testAdapterAscending() {
        let ids = ["new", "old"]
        let dates: [Date?] = [Date(timeIntervalSince1970: 1_800_000_000),
                              Date(timeIntervalSince1970: 1_600_000_000)]
        let descending = DateSectionizerAdapter.monthSections(ids: ids, dates: dates, ascending: false)
        let ascending = DateSectionizerAdapter.monthSections(ids: ids, dates: dates, ascending: true)
        XCTAssertNotEqual(descending.sections.first?.id, ascending.sections.first?.id,
                          "升序分组最早月份在前")
    }

    // MARK: - LibraryPositionStore（docs/09 D08）

    private func makeStore() -> LibraryPositionStore {
        let suite = "LibraryDataTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return LibraryPositionStore(defaults: defaults)
    }

    func testPositionStoreSaveLoad() {
        let store = makeStore()
        let position = LibraryPosition(assetID: "asset-1",
                                       sectionID: "2024-05",
                                       offsetRatio: 0.42,
                                       savedAt: Date())
        store.save(position, queryKey: "abc123")
        // I5：load 出的条目 queryKey 必须等于存储键（save 负责盖章，与传入对象无关）
        var expected = position
        expected.queryKey = "abc123"
        XCTAssertEqual(store.load(queryKey: "abc123"), expected)
    }

    func testPositionStorePerQueryKeys() {
        let store = makeStore()
        let p1 = LibraryPosition(assetID: "a", sectionID: "s", offsetRatio: 0.1, savedAt: Date())
        let p2 = LibraryPosition(assetID: "b", sectionID: "s", offsetRatio: 0.2, savedAt: Date())
        store.save(p1, queryKey: "key1")
        store.save(p2, queryKey: "key2")
        var e1 = p1
        e1.queryKey = "key1"
        var e2 = p2
        e2.queryKey = "key2"
        XCTAssertEqual(store.load(queryKey: "key1"), e1, "不同筛选各自记住位置")
        store.clear(queryKey: "key1")
        XCTAssertNil(store.load(queryKey: "key1"))
        XCTAssertEqual(store.load(queryKey: "key2"), e2)
    }

    func testPositionStoreDisabledBySwitch() {
        let store = makeStore()
        store.isEnabled = false
        let position = LibraryPosition(assetID: "a", sectionID: "s", offsetRatio: 0, savedAt: Date())
        store.save(position, queryKey: "k")
        XCTAssertNil(store.load(queryKey: "k"), "「记住上次整理位置」关闭后不读写")
    }

    func testPositionStoreClearAll() {
        let store = makeStore()
        let position = LibraryPosition(assetID: "a", sectionID: "s", offsetRatio: 0, savedAt: Date())
        store.save(position, queryKey: "k1")
        store.save(position, queryKey: "k2")
        store.clearAll()
        XCTAssertNil(store.load(queryKey: "k1"))
        XCTAssertNil(store.load(queryKey: "k2"))
    }
}
