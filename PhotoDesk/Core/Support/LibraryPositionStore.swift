// MARK: - 职责说明：上次整理位置存取 v2（docs/13 §3.5 S04/S11）——
// v2 结构：assetID + sectionID + itemIndexInSection + offsetRatio + savedAt + schemaVersion；
// 键空间 library.lastPosition.v2.<queryKey>；读取兼容 v1（decodeIfPresent 补默认值，损坏 JSON 不崩）。
// 恢复策略由 LibraryViewController 执行：assetID → sectionID + itemIndex → offsetRatio。
// 查看器记忆 lastAssetID 一并管理；「清除位置记忆」清空全部键。

import Foundation

/// 一条位置记忆（v2）
struct LibraryPosition: Codable, Equatable {
    let assetID: String
    let sectionID: String
    /// 该 section 内的 item 序号（sectionID 恢复时钳制）
    let itemIndexInSection: Int
    /// contentOffset.y / contentSize.height（恢复兜底）
    let offsetRatio: Double
    let savedAt: Date
    /// 结构版本（v1 遗留数据按 1 解）
    let schemaVersion: Int

    init(assetID: String,
         sectionID: String,
         itemIndexInSection: Int = 0,
         offsetRatio: Double,
         savedAt: Date,
         schemaVersion: Int = 2) {
        self.assetID = assetID
        self.sectionID = sectionID
        self.itemIndexInSection = itemIndexInSection
        self.offsetRatio = offsetRatio
        self.savedAt = savedAt
        self.schemaVersion = schemaVersion
    }

    /// v1 兼容解码：缺字段补默认值（v1 只有 assetID/sectionID/offsetRatio/savedAt）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try container.decode(String.self, forKey: .assetID)
        sectionID = try container.decode(String.self, forKey: .sectionID)
        itemIndexInSection = try container.decodeIfPresent(Int.self, forKey: .itemIndexInSection) ?? 0
        offsetRatio = try container.decodeIfPresent(Double.self, forKey: .offsetRatio) ?? 0
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

final class LibraryPositionStore {
    private let defaults: UserDefaults
    /// v2 键空间（写入只走这里）
    private static let positionPrefixV2 = "library.lastPosition.v2."
    /// v1 遗留键空间（只读兼容，docs/13 S04）
    private static let positionPrefixV1 = "library.lastPosition."
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
        defaults.set(data, forKey: Self.positionPrefixV2 + queryKey)
    }

    /// 读取：v2 优先；v1 遗留键兼容（decodeIfPresent 补默认）；损坏 JSON → nil（不崩）
    func load(queryKey: String) -> LibraryPosition? {
        guard isEnabled else { return nil }
        if let data = defaults.data(forKey: Self.positionPrefixV2 + queryKey),
           let position = try? JSONDecoder().decode(LibraryPosition.self, from: data) {
            return position
        }
        if let data = defaults.data(forKey: Self.positionPrefixV1 + queryKey),
           let position = try? JSONDecoder().decode(LibraryPosition.self, from: data) {
            return position
        }
        return nil
    }

    func clear(queryKey: String) {
        defaults.removeObject(forKey: Self.positionPrefixV2 + queryKey)
        defaults.removeObject(forKey: Self.positionPrefixV1 + queryKey)
    }

    /// 设置页「清除位置记忆」：网格位置（v1+v2）+ 查看器记忆全部清空
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.positionPrefixV1) || key.hasPrefix(Self.positionPrefixV2) || key.hasPrefix(Self.viewerPrefix) {
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
