// MARK: - 职责说明：上次整理位置存取 v4（docs/22 §4.4.1）——
// v4 = 视觉锚点 assetID + 视口内视觉 y + contentOffset / contentHeight / viewportHeight +
// 旧字段 fallback + schemaVersion=4；键空间仍沿用 library.lastPosition.v2.*（兼容 v1/v2/v3），
// 读取损坏 JSON 返回 nil，不崩溃。编码/UserDefaults 写在由 LibraryPositionCoordinator 的串行队列驱动。

import Foundation
import PhotoDeskCore

/// 一条位置记忆（v4；旧构造参数保留默认值，旧字段只作 fallback）
struct LibraryPosition: Codable, Equatable {
    /// 视觉锚点 assetID（v1/v2 解码时回退 assetID）
    let anchorAssetID: String
    /// 锚点 cell 的未变换 frame.minY - 保存时 contentOffset.y（视口内 y）
    let anchorVisualY: Double
    /// 保存时的 contentOffset.y（取证与旧数据兜底）
    let anchorContentOffsetY: Double
    let assetID: String
    let sectionID: String
    /// 该 section 内的 item 序号（sectionID fallback 时钳制）
    let itemIndexInSection: Int
    /// contentOffset.y / 可滚动高度（最后一级 fallback）
    let offsetRatio: Double
    /// v4：保存时的内容总高与视口高（恢复目标钳制 + 诊断）
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
         schemaVersion: Int = PositionAnchorPolicy.schemaVersion) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case anchorAssetID, anchorVisualY, anchorContentOffsetY
        case assetID, sectionID, itemIndexInSection, offsetRatio
        case contentHeight, viewportHeight, savedAt, schemaVersion
    }

    /// v1/v2 兼容解码：新增字段缺失时补默认值，anchorAssetID 回退 assetID。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
    private let defaults: UserDefaults
    /// v3 仍写 v2 键空间（结构向后兼容，避免遗留键失效）
    private static let positionPrefixV2 = "library.lastPosition.v2."
    /// v1 遗留键空间（只读兼容，docs/13 S04）
    private static let positionPrefixV1 = "library.lastPosition."

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
        guard isEnabled else { return }
        do {
            let data = try JSONEncoder().encode(position)
            defaults.set(data, forKey: Self.positionPrefixV2 + queryKey)
        } catch {
            return
        }
    }

    /// 读取：v3/v2 键优先；v1 遗留键兼容（decodeIfPresent 补默认）；损坏 JSON → nil（不崩）
    func load(queryKey: String) -> LibraryPosition? {
        guard isEnabled else { return nil }
        if let data = defaults.data(forKey: Self.positionPrefixV2 + queryKey) {
            do {
                return try JSONDecoder().decode(LibraryPosition.self, from: data)
            } catch {
                return nil
            }
        }
        if let data = defaults.data(forKey: Self.positionPrefixV1 + queryKey) {
            do {
                return try JSONDecoder().decode(LibraryPosition.self, from: data)
            } catch {
                return nil
            }
        }
        return nil
    }

    func clear(queryKey: String) {
        defaults.removeObject(forKey: Self.positionPrefixV2 + queryKey)
        defaults.removeObject(forKey: Self.positionPrefixV1 + queryKey)
    }

    /// 设置页「清除位置记忆」：网格位置（v1+v2/v3 共用键）清空
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.positionPrefixV1) || key.hasPrefix(Self.positionPrefixV2) {
            defaults.removeObject(forKey: key)
        }
    }
}
