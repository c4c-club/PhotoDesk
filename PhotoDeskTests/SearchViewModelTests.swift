// MARK: - 职责说明：搜索 ViewModel 测试（M17 T08 X03，docs/31 §3）——
// 数据源改为实时快照（provider 闭包）：打开/激活刷新取最新快照；apply 后台代际令牌。

import XCTest
@testable import PhotoDesk

@MainActor
final class SearchViewModelTests: XCTestCase {

    private func item(_ index: Int) -> PhotoItem {
        PhotoItem(id: "id-\(index)",
                  mediaType: .image, mediaSubtypes: [],
                  creationDate: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index * 86_400)),
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: false, isHidden: false,
                  location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    /// 等待后台 apply 落地（代际令牌异步路径）
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testRefreshPullsLatestSnapshot() async {
        var source = [item(0), item(1)]
        let vm = SearchViewModel(itemsProvider: { source })
        XCTAssertEqual(vm.results.count, 2)
        source.append(item(2))   // 搜索页打开后库发生变化（拍照/删除/隐藏）
        vm.refresh()
        await waitUntil { vm.results.count == 3 }
        XCTAssertEqual(vm.results.count, 3, "激活刷新必须取最新快照（X03：快照滞留缺陷）")
    }

    func testApplyOffMainLandsFilteredResults() async {
        let source = (0..<2_000).map { item($0) }
        let vm = SearchViewModel(itemsProvider: { source })
        vm.predicate.year = 2023   // 2000 张跨度约 5.5 年：2023 年仅覆盖开头一段
        vm.apply()                 // 后台代际令牌重算
        let expected = PhotoFilter.apply(source, predicate: vm.predicate)
        XCTAssertLessThan(expected.count, 2_000, "前置：年份筛选须真的裁剪")
        await waitUntil { vm.results.count == expected.count }
        XCTAssertEqual(vm.results.count, expected.count, "后台 apply 结果必须与主线程口径一致")
    }
}