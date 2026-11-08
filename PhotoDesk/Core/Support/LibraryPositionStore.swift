// MARK: - 职责说明：上次整理位置存取 v5（docs/25 §5.2–5.3 / M15 P0-2）——
// v5 = 视觉锚点 assetID + 视口内视觉 y + queryKey + schemaVersion=5；v1–v4 字段保留解码兼容。
// 存储换成 PositionFileStore 原子文件（Application Support/LibraryPosition/anchors-v5.json），
// 不再写 UserDefaults；init 时把 v1–v4 的 UserDefaults 键一次性迁移进 v5 文件（迁移失败保留旧键）。
// 对外接口 save/load/isEnabled/clear/clearAll 保持不变，调用方（VM/VC/协调器）零改动。

import Foundation
import PhotoDeskCore

/// 一条位置记忆（v5；v1–v4 字段只作迁移/兜底）
struct LibraryPosition: Codable, Equatable {
    /// 本条归属的查询键（v5 起落盘自带；v4 解码补 ""，由调用方按 load(queryKey:) 归位）
    var queryKey: String
    /// 视觉锚点 assetID（v1/v2 解码时回退 assetID）
    let anchorAssetID: String
    /// 锚点 cell 的未变换 frame.minY - 保存时 contentOffset.y（视口内 y，允许为负）
    let anchorVisualY: Double
    /// 保存时的 contentOffset.y（取证与旧数据兜底）
    let anchorContentOffsetY: Double
    let assetID: String
    let sectionID: String
    /// 该 section 内的 item 序号（sectionID fallback 时钳制）
    let itemIndexInSection: Int
    /// contentOffset.y / 可滚动高度（最后一级 fallback）
    let offsetRatio: Double
    /// 保存时的内容总高与视口高（恢复目标钳制 + 诊断）
    let contentHeight: Double
    let viewportHeight: Double
    let savedAt: Date
    let schemaVersion: Int

    init(anchorAssetID: String? = nil,
         anchorVisualY: Double = 0,
         anchorContentOffsetY: Double = 0,
         assetID: String,
         sectionID: String,
         itemIndexInSection: Int = 0,
         offsetRatio: Double = 0,
         contentHeight: Double = 0,
         viewportHeight: Double = 0,
         savedAt: Date = Date(),
         schemaVersion: Int = PositionAnchorPolicy.schemaVersion,
         queryKey: String = "") {
        self.anchorAssetID = anchorAssetID ?? assetID
        self.anchorVisualY = anchorVisualY
        self.anchorContentOffsetY = anchorContentOffsetY
        self.assetID = assetID
        self.sectionID = sectionID
        self.itemIndexInSection = itemIndexInSection
        self.offsetRatio = offsetRatio
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
        self.savedAt = savedAt
        self.schemaVersion = schemaVersion
        self.queryKey = queryKey
    }

    private enum CodingKeys: String, CodingKey {
        case queryKey
        case anchorAssetID, anchorVisualY, anchorContentOffsetY
        case assetID, sectionID, itemIndexInSection, offsetRatio
        case contentHeight, viewportHeight, savedAt, schemaVersion
    }

    /// v1–v4 兼容解码：queryKey 缺失补 ""；anchorAssetID 回退 assetID；新增字段补默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queryKey = try c.decodeIfPresent(String.self, forKey: .queryKey) ?? ""
        let oldAssetID = try c.decodeIfPresent(String.self, forKey: .assetID) ?? ""
        let anchor = try c.decodeIfPresent(String.self, forKey: .anchorAssetID)
        anchorAssetID = anchor ?? oldAssetID
        anchorVisualY = try c.decodeIfPresent(Double.self, forKey: .anchorVisualY) ?? 0
        anchorContentOffsetY = try c.decodeIfPresent(Double.self, forKey: .anchorContentOffsetY) ?? 0
        assetID = oldAssetID
        sectionID = try c.decodeIfPresent(String.self, forKey: .sectionID) ?? ""
        itemIndexInSection = try c.decodeIfPresent(Int.self, forKey: .itemIndexInSection) ?? 0
        offsetRatio = try c.decodeIfPresent(Double.self, forKey: .offsetRatio) ?? 0
        contentHeight = try c.decodeIfPresent(Double.self, forKey: .contentHeight) ?? 0
        viewportHeight = try c.decodeIfPresent(Double.self, forKey: .viewportHeight) ?? 0
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date(timeIntervalSince1970: 0)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(queryKey, forKey: .queryKey)
        try c.encode(anchorAssetID, forKey: .anchorAssetID)
        try c.encode(anchorVisualY, forKey: .anchorVisualY)
        try c.encode(anchorContentOffsetY, forKey: .anchorContentOffsetY)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(sectionID, forKey: .sectionID)
        try c.encode(itemIndexInSection, forKey: .itemIndexInSection)
        try c.encode(offsetRatio, forKey: .offsetRatio)
        try c.encode(contentHeight, forKey: .contentHeight)
        try c.encode(viewportHeight, forKey: .viewportHeight)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion)
    }

    /// App 侧 UIKit 值 → Core 纯模型（恢复策略只吃 Foundation / Double）。
    var toCoreAnchor: PositionAnchorV3 {
        PositionAnchorV3(anchorAssetID: anchorAssetID,
                         anchorVisualY: anchorVisualY,
                         anchorContentOffsetY: anchorContentOffsetY,
                         assetID: assetID,
                         sectionID: sectionID,
                         itemIndexInSection: itemIndexInSection,
                         offsetRatio: offsetRatio,
                         contentHeight: contentHeight,
                         viewportHeight: viewportHeight,
                         savedAt: savedAt,
                         schemaVersion: schemaVersion)
    }
}

final class LibraryPositionStore {
    /// v5 原子文件存储（主线程读写）
    private let fileStore: PositionFileStore
    private let defaults: UserDefaults
    /// v1–v4 遗留键空间（只读迁移源，不再写入）
    private static let legacyPrefixes = ["library.lastPosition.v2.", "library.lastPosition."]

    /// 位置记忆总开关（设置页「记住上次整理位置」，默认开）
    var isEnabled: Bool {
        get { defaults.object(forKey: "library.rememberPosition") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "library.rememberPosition") }
    }

    var entryCount: Int { fileStore.entryCount }

    init(fileStore: PositionFileStore? = nil,
         defaults: UserDefaults = .standard) {
        self.fileStore = fileStore ?? PositionFileStore()
        self.defaults = defaults
        migrateLegacyUserDefaultsIfNeeded()
    }

    // MARK: - 网格位置（对外接口与 v4 完全一致）

    func save(_ position: LibraryPosition, queryKey: String) {
        guard isEnabled else { return }
        var migrated = position
        migrated.queryKey = queryKey
        fileStore.save(migrated, queryKey: queryKey)
    }

    func load(queryKey: String) -> LibraryPosition? {
        guard isEnabled else { return nil }
        return fileStore.load(queryKey: queryKey)
    }

    /// 切后台/杀进程前的最后落盘保证。
    func flush() {
        fileStore.flush()
    }

    func clear(queryKey: String) {
        fileStore.remove(queryKey: queryKey)
        for prefix in Self.legacyPrefixes {
            defaults.removeObject(forKey: prefix + queryKey)
        }
    }

    /// 设置页「清除位置记忆」：v5 文件全部清空 + v1–v4 遗留键清空
    func clearAll() {
        fileStore.removeAll()
        for key in defaults.dictionaryRepresentation().keys
        where Self.legacyPrefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - v1–v4 UserDefaults 迁移

    /// 首次启动把 UserDefaults 里的 v1–v4 位置搬进 v5 文件；单条解码失败跳过（保留旧键，不删）。
    private func migrateLegacyUserDefaultsIfNeeded() {
        var migrated = 0
        for (key, value) in defaults.dictionaryRepresentation() {
            guard let data = value as? Data,
                  let prefix = Self.legacyPrefixes.first(where: key.hasPrefix) else { continue }
            let queryKey = String(key.dropFirst(prefix.count))
            guard !queryKey.isEmpty,
                  fileStore.load(queryKey: queryKey) == nil,
                  let legacy = try? JSONDecoder().decode(LibraryPosition.self, from: data) else { continue }
            var position = legacy
            position.queryKey = queryKey
            fileStore.save(position, queryKey: queryKey)
            migrated += 1
        }
        if migrated > 0 {
            ViewerTrace.log("position.migrate v1-v4 → v5 count=\(migrated)")
        }
    }
}
