// MARK: - 职责说明：相簿列表 ViewModel（M17 T08 X01/X02，docs/31 §3）——
// 消费 AlbumServiceProtocol（构造器注入）；智能相簿过滤（0 张与最近删除）；
// 库变化自动重载。View 只读 [AlbumSummary]，零 PhotoKit 类型。

import Foundation

@MainActor
final class AlbumsViewModel: ObservableObject {
    @Published private(set) var userAlbums: [AlbumSummary] = []
    @Published private(set) var smartAlbums: [AlbumSummary] = []
    @Published private(set) var isLoading = false
    /// 新建/重命名/删除失败的中文提示（禁止 try? 静默吞掉写操作错误）
    @Published var errorMessage: String?

    private let service: AlbumServiceProtocol

    init(service: AlbumServiceProtocol) {
        self.service = service
        service.onLibraryChanged = { [weak self] in
            Task { await self?.reload() }
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        userAlbums = await service.summaries(kind: .user)
        // 系统空智能相簿（如「个人收藏」空时）PhotoKit 仍返回——count 为 0 的过滤掉；
        // 最近删除相簿不展示（红线 1：App 内不提供回收站入口）
        smartAlbums = await service.summaries(kind: .smart)
            .filter { $0.count > 0 && $0.title != "Recently Deleted" && $0.title != "最近删除" }
    }
}