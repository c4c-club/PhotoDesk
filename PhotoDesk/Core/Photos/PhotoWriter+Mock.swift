// MARK: - 职责说明：PhotoWriter 假实现（仅 DEBUG；docs/09 Phase 0 测试钩子 -uiTestingSessionMock）——
// UI 测试用：记录调用次数与参数，不触碰 PhotoKit（滑动 20 张 0 次系统弹窗 / 提交 1 次的断言信号源）。
// Release 构建不编译；普通启动（无测试参数）绝不实例化（AppContainer 控制）。

import Foundation

#if DEBUG
@MainActor
final class MockPhotoWriter: PhotoWriterProtocol {
    private(set) var moveToRecentlyDeletedCalls: [[String]] = []
    private(set) var setHiddenCalls: [(ids: [String], isHidden: Bool)] = []
    private(set) var setFavoriteCalls: [(ids: [String], isFavorite: Bool)] = []
    /// 模拟「系统确认取消」/ 写失败：抛错但记录调用（调用本身代表一次系统确认）
    var shouldFailMoveToRecentlyDeleted = false
    var shouldFailSetHidden = false

    var moveToRecentlyDeletedCallCount: Int { moveToRecentlyDeletedCalls.count }
    var setHiddenCallCount: Int { setHiddenCalls.count }
    var setFavoriteCallCount: Int { setFavoriteCalls.count }

    func setFavorite(ids: [String], isFavorite: Bool) async throws {
        setFavoriteCalls.append((ids, isFavorite))
    }

    func setHidden(ids: [String], isHidden: Bool) async throws {
        setHiddenCalls.append((ids, isHidden))
        if shouldFailSetHidden { throw MockWriterError.rejected }
    }

    func moveToRecentlyDeleted(ids: [String]) async throws {
        moveToRecentlyDeletedCalls.append(ids)
        if shouldFailMoveToRecentlyDeleted { throw MockWriterError.rejected }
    }

    enum MockWriterError: Error { case rejected }

    func createAlbum(title: String) async throws -> String { "mock-album" }
    func renameAlbum(localID: String, to title: String) async throws {}
    func deleteAlbum(localID: String) async throws {}
    func add(ids: [String], toAlbum albumID: String) async throws {}
    func remove(ids: [String], fromAlbum albumID: String) async throws {}
    func saveNewImage(fromFile fileURL: URL, creationDate: Date?) async throws -> String { "mock-asset" }
    func overwriteWithAdjustment(assetID: String, adjustmentData: Data,
                                 render: @escaping (URL) async throws -> Void) async throws {}
    func revertToOriginal(assetID: String) async throws {}
    func requestInputURL(assetID: String) async throws -> URL { URL(fileURLWithPath: "/dev/null") }
}
#endif
