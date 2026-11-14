// MARK: - 职责说明：相簿列表 ViewModel 测试（M17 T08 X01/X02，docs/31 §3）——
// Fake 相簿服务驱动，不触碰 PhotoKit。验证：service 摘要透传、智能相簿过滤（0 张与最近删除）、
// 库变化自动重载（X01：无 ChangeObserver 缺陷的回归锁）。

import XCTest
import Photos
@testable import PhotoDesk

@MainActor
final class AlbumsViewModelTests: XCTestCase {

    /// Fake 相簿服务：canned 摘要 + 可手触发的库变化回调
    private final class FakeAlbumService: AlbumServiceProtocol {
        var userSummaries: [AlbumSummary]
        var smartSummaries: [AlbumSummary]
        var onLibraryChanged: (() -> Void)?
        private(set) var reloadCount = 0

        init(user: [AlbumSummary], smart: [AlbumSummary]) {
            userSummaries = user
            smartSummaries = smart
        }

        func summaries(kind: AlbumListKind) async -> [AlbumSummary] {
            reloadCount += 1
            return kind == .user ? userSummaries : smartSummaries
        }
    }

    private func summary(_ id: String, count: Int, title: String? = nil) -> AlbumSummary {
        AlbumSummary(id: id, title: title ?? id, count: count, coverAssetID: nil)
    }

    func testConsumesServiceSummariesAndFiltersEmptySmartAlbums() async {
        let service = FakeAlbumService(
            user: [summary("u1", count: 12), summary("u2", count: 0)],
            smart: [summary("s1", count: 3), summary("s2", count: 0),
                    summary("s3", count: 9, title: "Recently Deleted"),
                    summary("s4", count: 9, title: "最近删除")])
        let vm = AlbumsViewModel(service: service)
        await vm.reload()
        XCTAssertEqual(vm.userAlbums.map(\.id), ["u1", "u2"], "用户相簿原样透传（0 张也保留）")
        XCTAssertEqual(vm.smartAlbums.map(\.id), ["s1"], "智能相簿滤 0 张与最近删除")
    }

    func testLibraryChangeTriggersReload() async {
        let service = FakeAlbumService(user: [summary("u1", count: 1)], smart: [])
        let vm = AlbumsViewModel(service: service)
        await vm.reload()
        XCTAssertGreaterThanOrEqual(service.reloadCount, 2)
        service.userSummaries = [summary("u1", count: 5)]
        service.onLibraryChanged?()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, vm.userAlbums.first?.count != 5 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(vm.userAlbums.first?.count, 5, "库变化必须触发列表自动刷新（X01：无 ChangeObserver 缺陷）")
    }
}