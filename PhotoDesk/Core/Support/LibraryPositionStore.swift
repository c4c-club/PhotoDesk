// MARK: - 职责说明：上次整理位置存取（docs/09 D08）——按 queryKey（LibraryQuery.key）保存
// 首个可见 assetID + 分组 + 偏移比例；UserDefaults JSON。查看器记忆 lastAssetID 一并管理。
// 位置恢复失败时用 offsetRatio 兜底；「清除位置记忆」清空全部键。

import Foundation

/// 一条位置记忆
struct LibraryPosition: Codable, Equatable {
    let assetID: String
    let sectionID: String
    /// contentOffset.y / contentSize.height（恢复兜底）
    let offsetRatio: Double
    let savedAt: Date
}

final class LibraryPositionStore {
    private let defaults: UserDefaults
    private static let positionPrefix = "library.lastPosition."
    private static let viewerPrefix = "library.viewer.lastAssetID."

    /// 位置记忆总开关（设置页「记住上次整理位置」，默认开）
    var isEnabled: Bool {
        get { defaults.object(forKey: "library.rememberPosition") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "library.rememberPosition") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 网格位置

    func save(_ position: LibraryPosition, queryKey: String) {
        guard isEnabled, let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: Self.positionPrefix + queryKey)
    }

    func load(queryKey: String) -> LibraryPosition? {
        guard isEnabled, let data = defaults.data(forKey: Self.positionPrefix + queryKey) else { return nil }
        return try? JSONDecoder().decode(LibraryPosition.self, from: data)
    }

    func clear(queryKey: String) {
        defaults.removeObject(forKey: Self.positionPrefix + queryKey)
    }

    /// 设置页「清除位置记忆」：网格位置 + 查看器记忆全部清空
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.positionPrefix) || key.hasPrefix(Self.viewerPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - 查看器记忆

    func saveViewerAssetID(_ id: String, queryKey: String) {
        defaults.set(id, forKey: Self.viewerPrefix + queryKey)
    }

    func loadViewerAssetID(queryKey: String) -> String? {
        defaults.string(forKey: Self.viewerPrefix + queryKey)
    }
}
