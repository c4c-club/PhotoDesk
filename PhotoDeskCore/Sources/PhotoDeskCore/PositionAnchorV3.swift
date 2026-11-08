// MARK: - 职责说明：位置锚点 v4 纯模型与恢复策略（类型名保留 V3 以兼容既有引用）——
// v4 = 视觉锚点 + contentHeight/viewportHeight（恢复目标钳制与诊断）；v1/v2/v3 解码兼容；
// fallback 顺序、恢复期写回门禁全部下沉 Core；仅 Foundation / Double / String / Date，零 UIKit。

import Foundation

/// v4 位置：视觉锚点优先；旧字段只作 fallback，schemaVersion 缺省按 v1/v2/v3 兼容解码。
public struct PositionAnchorV3: Codable, Equatable, Sendable {
    public let anchorAssetID: String
    public let anchorVisualY: Double
    public let anchorContentOffsetY: Double
    public let assetID: String
    public let sectionID: String
    public let itemIndexInSection: Int
    public let offsetRatio: Double
    public let contentHeight: Double
    public let viewportHeight: Double
    public let savedAt: Date
    public let schemaVersion: Int

    public init(
        anchorAssetID: String,
        anchorVisualY: Double,
        anchorContentOffsetY: Double,
        assetID: String,
        sectionID: String,
        itemIndexInSection: Int = 0,
        offsetRatio: Double = 0,
        contentHeight: Double = 0,
        viewportHeight: Double = 0,
        savedAt: Date = Date(),
        schemaVersion: Int = PositionAnchorPolicy.schemaVersion
    ) {
        self.anchorAssetID = anchorAssetID
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let oldAssetID = try c.decodeIfPresent(String.self, forKey: .assetID) ?? ""
        let anchor = try c.decodeIfPresent(String.self, forKey: .anchorAssetID)
        let visualY = try c.decodeIfPresent(Double.self, forKey: .anchorVisualY) ?? 0
        let offsetY = try c.decodeIfPresent(Double.self, forKey: .anchorContentOffsetY) ?? 0
        let section = try c.decodeIfPresent(String.self, forKey: .sectionID) ?? ""
        let index = try c.decodeIfPresent(Int.self, forKey: .itemIndexInSection) ?? 0
        let ratio = try c.decodeIfPresent(Double.self, forKey: .offsetRatio) ?? 0
        let content = try c.decodeIfPresent(Double.self, forKey: .contentHeight) ?? 0
        let viewport = try c.decodeIfPresent(Double.self, forKey: .viewportHeight) ?? 0
        let date = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date(timeIntervalSince1970: 0)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        self.anchorAssetID = anchor ?? oldAssetID
        self.anchorVisualY = visualY
        self.anchorContentOffsetY = offsetY
        self.assetID = oldAssetID
        self.sectionID = section
        self.itemIndexInSection = index
        self.offsetRatio = ratio
        self.contentHeight = content
        self.viewportHeight = viewport
        self.savedAt = date
        self.schemaVersion = version
    }

    public func encode(to encoder: Encoder) throws {
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
}

public enum PositionRestoreStrategy: String, Equatable, Sendable {
    case asset
    case section
    case ratio
    case none
}

public enum PositionAnchorPolicy {
    public static let schemaVersion: Int = 5

    /// 视觉锚点视口内 y：cell 未变换 frame.minY - contentOffset.y。
    public static func visualY(cellMinY: Double, contentOffsetY: Double) -> Double {
        guard cellMinY.isFinite, contentOffsetY.isFinite else { return 0 }
        let value = cellMinY - contentOffsetY
        return value.isFinite ? value : 0
    }

    /// 精确像素落地：新快照同一 asset 的 frame.minY - 保存时的视觉 y；禁止 .centeredVertically 作主路径。
    public static func targetOffsetY(cellMinY: Double, anchorVisualY: Double) -> Double {
        guard cellMinY.isFinite else { return 0 }
        // 视觉 y 损坏时退化为「该 cell 顶边对齐视口顶」的有限像素值，绝不写 NaN / 不回退到 0 造成跨月跳变。
        guard anchorVisualY.isFinite else { return cellMinY }
        let value = cellMinY - anchorVisualY
        return value.isFinite ? value : cellMinY
    }

    /// 钳制到合法 contentOffset.y 区间：上界 -adjustedTop，下界 contentHeight + bottomInset - viewportHeight。
    public static func clampedTargetOffsetY(
        _ target: Double,
        contentHeight: Double,
        viewportHeight: Double,
        adjustedTop: Double,
        bottomInset: Double
    ) -> Double {
        guard target.isFinite, contentHeight.isFinite, viewportHeight.isFinite,
              adjustedTop.isFinite, bottomInset.isFinite, contentHeight > 0, viewportHeight > 0 else { return 0 }
        let lower = -Swift.abs(adjustedTop)
        let upper = Swift.max(lower, contentHeight + bottomInset - viewportHeight)
        return Swift.min(Swift.max(target, lower), upper)
    }

    /// 最后一级 fallback：旧版 offsetRatio。
    public static func ratioOffsetY(
        ratio: Double,
        contentHeight: Double,
        viewportHeight: Double,
        adjustedTop: Double,
        bottomInset: Double
    ) -> Double {
        guard ratio.isFinite else { return 0 }
        let r = Swift.min(1, Swift.max(0, ratio))
        let scrollable = Swift.max(0, contentHeight + bottomInset - viewportHeight)
        return clampedTargetOffsetY(
            -Swift.abs(adjustedTop) + scrollable * r,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            adjustedTop: adjustedTop,
            bottomInset: bottomInset
        )
    }

    /// 严格按 anchorAssetID → sectionID+itemIndex → offsetRatio 逐级退化；每级由调用方写 PositionTrace。
    public static func resolve(
        anchor: PositionAnchorV3,
        assetCellMinY: Double?,
        sectionCellMinY: Double?,
        contentHeight: Double,
        viewportHeight: Double,
        adjustedTop: Double,
        bottomInset: Double
    ) -> (strategy: PositionRestoreStrategy, offsetY: Double) {
        if !anchor.anchorAssetID.isEmpty, let minY = assetCellMinY, minY.isFinite {
            let target = targetOffsetY(cellMinY: minY, anchorVisualY: anchor.anchorVisualY)
            let offset = clampedTargetOffsetY(
                target,
                contentHeight: contentHeight,
                viewportHeight: viewportHeight,
                adjustedTop: adjustedTop,
                bottomInset: bottomInset
            )
            return (.asset, offset)
        }
        if !anchor.sectionID.isEmpty, let minY = sectionCellMinY, minY.isFinite {
            let offset = clampedTargetOffsetY(
                minY,
                contentHeight: contentHeight,
                viewportHeight: viewportHeight,
                adjustedTop: adjustedTop,
                bottomInset: bottomInset
            )
            return (.section, offset)
        }
        // 完全空的旧位置没有可恢复对象：既不走 ratio，也不把 contentOffset 改成 -adjustedTop。
        let hasNoAnchor = anchor.anchorAssetID.isEmpty
            && anchor.assetID.isEmpty
            && anchor.sectionID.isEmpty
            && anchor.offsetRatio == 0
        if hasNoAnchor { return (.none, 0) }

        let offset = ratioOffsetY(
            ratio: anchor.offsetRatio,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            adjustedTop: adjustedTop,
            bottomInset: bottomInset
        )
        return (.ratio, offset)
    }

    /// 恢复完成门禁：bounds > 0 + 有 section + 快照 drain 完成 + 精确 offset 已应用（App 侧随后再 layoutIfNeeded）。
    public static func canFinish(
        boundsWidth: Double,
        boundsHeight: Double,
        numberOfSections: Int,
        snapshotDrained: Bool,
        offsetApplied: Bool
    ) -> Bool {
        boundsWidth > 0 && boundsHeight > 0 && numberOfSections > 0 && snapshotDrained && offsetApplied
    }

    /// 恢复期零回写：in-flight 未解除前任何 savePositionNow 直接 return。
    public static func allowsWriteback(isRestoreInFlight: Bool) -> Bool {
        !isRestoreInFlight
    }
}
