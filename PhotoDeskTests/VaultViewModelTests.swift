// MARK: - 职责说明：保险箱 ViewModel 测试（M17 T08 X04，docs/31 §3）——
// 收藏后本地 item 状态同步 + onItemsChanged 回调（菜单/角标旧值缺陷的回归锁）。
// 模拟器测试宿主走 simulatorBypass（无 Face ID 硬件，AGENTS 陷阱表口径）。

import XCTest
@testable import PhotoDesk

@MainActor
final class VaultViewModelTests: XCTestCase {

    private final class FakeHiddenRepository: AssetRepositoryProtocol {
        let store: [PhotoItem]
        init(_ store: [PhotoItem]) { self.store = store }
        func prepare(scope: PhotoScope) async -> Int { store.count }
        func prepare(scope: PhotoScope, sortAscending: Bool) async -> Int { store.count }
        func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem] {
            Array(store.dropFirst(offset).prefix(limit))
        }
        func fetch(ids: [String]) async -> [PhotoItem] {
            let set = Set(ids)
            return store.filter { set.contains($0.id) }
        }
        func globalIndex(of assetID: String, scope: PhotoScope) async -> Int? {
            store.firstIndex { $0.id == assetID }
        }
        func count(scope: PhotoScope) async -> Int { store.count }
        var latestResult: PHFetchResult<PHAsset>? { nil }
        func latestResult(for scope: PhotoScope) -> PHFetchResult<PHAsset>? { nil }
        func replaceResult(_ result: PHFetchResult<PHAsset>, for scope: PhotoScope) {}
        func map(_ asset: PHAsset) -> PhotoItem { store.first ?? Self.emptyItem }

        private static let emptyItem = PhotoItem(id: "empty",
                                                 mediaType: .image, mediaSubtypes: [],
                                                 creationDate: nil, modificationDate: nil,
                                                 pixelWidth: 1, pixelHeight: 1, duration: 0,
                                                 isFavorite: false, isHidden: false,
                                                 location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    private func item(_ index: Int, favorite: Bool = false) -> PhotoItem {
        PhotoItem(id: "hidden-\(index)",
                  mediaType: .image, mediaSubtypes: [],
                  creationDate: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index * 86_400)),
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: favorite, isHidden: true,
                  location: nil, burstIdentifier: nil, isCloudOnly: false)
    }

    func testFavoriteUpdatesLocalItemsAndFiresOnItemsChanged() async throws {
        let items = [item(0), item(1)]
        let vm = VaultViewModel(vault: VaultService(),
                                repository: FakeHiddenRepository(items),
                                writer: MockPhotoWriter(),
                                reviewSession: ReviewSessionController(
                                    store: PendingActionStore(directoryOverride:
                                        FileManager.default.temporaryDirectory
                                            .appendingPathComponent("VaultTests-\(UUID().uuidString)", isDirectory: true)),
                                    writer: MockPhotoWriter(),
                                    trashBin: nil,
                                    settings: SettingsStore()),
                                undoCenter: UndoCenter(writer: MockPhotoWriter(),
                                                       trashBin: nil,
                                                       persistence: PersistenceController(inMemory: true)),
                                settings: SettingsStore())
        // 模拟器无 Face ID 硬件：测试钩子直接装载（AGENTS 陷阱表口径）
        await vm.simulatorBypass()
        XCTAssertEqual(vm.items.count, 2, "前置：Fake 仓库装载已隐藏项")

        var fired = false
        vm.onItemsChanged = { fired = true }
        let error = await vm.favorite(ids: ["hidden-0"])
        XCTAssertNil(error, "收藏写库应成功（MockPhotoWriter）")
        XCTAssertTrue(vm.items.first(where: { $0.id == "hidden-0" })?.isFavorite ?? false,
                      "收藏后本地 item.isFavorite 必须同步（X04：菜单/角标旧值缺陷）")
        XCTAssertTrue(fired, "收藏后必须回调 onItemsChanged（X04）")
    }
}