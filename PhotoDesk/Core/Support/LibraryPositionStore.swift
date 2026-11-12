// MARK: - 职责说明：上次整理位置存取 v6（docs/28 §5.3 / M16 T03）——
// v6 = 锚点 assetID 最终身份 + anchorGlobalIndex（仅用于首批窗口定位，非身份）
+ gridColumns/contentInsetTop 取证字段；文件 anchors-v6.json（见 PositionFileStore）。
// 视觉 y 语义沿用 v5：anchorVisualY = cell 未变换 frame.minY − contentOffset.y（±2pt 恢复口径），
// 迁移记录因此保持像素级一致；inset 变化由恢复钳制 + 一次重试吸收。
// v5 结构体保留为迁移/旧数据解码源（只读）；v1–v4 UserDefaults 键一次性迁入 v6 文件。

import Foundation
import PhotoDeskCore

/// 一条位置记忆（v6，docs/28 §5.3 字段表）
struct LibraryPositionV6: Codable, Equatable {
    var queryKey: String
    /// 锚点照片 localIdentifier（最终身份）
    let anchorAssetID: String
    /// 全量索引中的位置；未知/已失效为 nil——仅用于首批窗口定位，不作为最终身份
    let anchorGlobalIndex: Int?
    let anchorSectionID: String
    let anchorSectionItemIndex: Int
    /// 锚点 cell 未变换 frame.minY − 保存时 contentOffset.y（沿用 v5 语义）
    let anchorVisualY: Double
    /// 保存时的 contentOffset.y（取证与旧数据兜底）
    let anchorContentOffsetY: Double
    /// 保存时列数（2...5）
    let gridColumns: Int
    /// 保存时 adjustedContentInset.top（取证）
    let contentInsetTop: Double
    /// 保存时的内容总高与视口高（恢复目标钳制 + 诊断）
    let contentHeight: Double
    let viewportHeight: Double
    let savedAt: Date
    let schemaVersion: Int

    init(queryKey: String,
         anchorAssetID: String,
         anchorGlobalIndex: Int? = nil,
         anchorSectionID: String,
         anchorSectionItemIndex: Int,
         anchorVisualY: Double,
         anchorContentOffsetY: Double,
         gridColumns: Int,
         contentInsetTop: Double,
         contentHeight: Double,
         viewportHeight: Double,
         savedAt: Date = Date(),
         schemaVersion: Int = 6) {
        self.queryKey = queryKey
        self.anchorAssetID = anchorAssetID
        self.anchorGlobalIndex = anchorGlobalIndex
        self.anchorSectionID = anchorSectionID
        self.anchorSectionItemIndex = anchorSectionItemIndex
        self.anchorVisualY = anchorVisualY
        self.anchorContentOffsetY = anchorContentOffsetY
        self.gridColumns = gridColumns
        self.contentInsetTop = contentInsetTop
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
        self.savedAt = savedAt
        self.schemaVersion = schemaVersion
    }

    /// 字段有效性（§5.3 约束）：visualY ∈ [0, viewport)、columns ∈ 2...5、非有限值拒绝。
    /// 无效记录由协调器按 sectionID+index → ratio 逐级回退，绝不假恢复。
    var isSane: Bool {
        schemaVersion == 6
            && !anchorAssetID.isEmpty
            && anchorVisualY.isFinite
            && viewportHeight.isFinite && viewportHeight > 0
            && anchorVisualY >= 0 && anchorVisualY < viewportHeight
            && (2...5).contains(gridColumns)
            && anchorContentOffsetY.isFinite
            && contentInsetTop.isFinite
            && contentHeight.isFinite && contentHeight >= 0
    }

    /// Core 纯模型（fallback resolve 只吃 Foundation 类型）。
    var toCoreAnchor: PositionAnchorV3 {
        let scrollable = Swift.max(1, contentHeight - viewportHeight)
        let ratio = anchorContentOffsetY.isFinite
            ? Swift.min(1, Swift.max(0, anchorContentOffsetY / scrollable)) : 0
        return PositionAnchorV3(anchorAssetID: anchorAssetID,
                                anchorVisualY: anchorVisualY,
                                anchorContentOffsetY: anchorContentOffsetY,
                                assetID: anchorAssetID,
                                sectionID: anchorSectionID,
                                itemIndexInSection: anchorSectionItemIndex,
                                offsetRatio: ratio,
                                contentHeight: contentHeight,
                                viewportHeight: viewportHeight,
                                savedAt: savedAt,
                                schemaVersion: schemaVersion)
    }
}

extension LibraryPosition {
    /// v5 → v6 迁移映射：anchorGlobalIndex 未知（nil）；gridColumns 取当前设置、inset 记 0（取证字段）。
    func toV6(gridColumns: Int) -> LibraryPositionV6 {
        LibraryPositionV6(queryKey: queryKey,
                          anchorAssetID: anchorAssetID,
                          anchorGlobalIndex: nil,
                          anchorSectionID: sectionID,
                          anchorSectionItemIndex: itemIndexInSection,
                          anchorVisualY: anchorVisualY,
                          anchorContentOffsetY: anchorContentOffsetY,
                          gridColumns: gridColumns,
                          contentInsetTop: 0,
                          contentHeight: contentHeight,
                          viewportHeight: viewportHeight,
                          savedAt: savedAt,
                          schemaVersion: 6)
    }
}

final class LibraryPositionStore {
    /// v6 原子文件存储（主线程读写）
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

    /// 保存时的网格列数（2...5 钳制；v6 落盘与迁移共用）
    static func currentGridColumns(defaults: UserDefaults) -> Int {
        let raw = defaults.object(forKey: "grid.columns") as? Int ?? 3
        return Swift.min(5, Swift.max(2, raw))
    }

    // MARK: - 网格位置（对外接口与 v5 一致，类型升级 v6）

    func save(_ position: LibraryPositionV6, queryKey: String) {
        guard isEnabled else { return }
        var stamped = position
        stamped.queryKey = queryKey
        fileStore.save(stamped, queryKey: queryKey)
    }

    func load(queryKey: String) -> LibraryPositionV6? {
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

    /// 设置页「清除位置记忆」：v6 文件全部清空 + v1–v4 遗留键清空
    func clearAll() {
        fileStore.removeAll()
        for key in defaults.dictionaryRepresentation().keys
        where Self.legacyPrefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - v1–v4 UserDefaults 迁移

    /// 首次启动把 UserDefaults 里的 v1–v4 位置搬进 v6 文件；单条解码失败跳过（保留旧键，不删）。
    private func migrateLegacyUserDefaultsIfNeeded() {
        var migrated = 0
        for (key, value) in defaults.dictionaryRepresentation() {
            guard let data = value as? Data,
                  let prefix = Self.legacyPrefixes.first(where: key.hasPrefix) else { continue }
            let queryKey = String(key.dropFirst(prefix.count))
            guard !queryKey.isEmpty,
                  fileStore.load(queryKey: queryKey) == nil,
                  let legacy = try? JSONDecoder().decode(LibraryPosition.self, from: data) else { continue }
            let position = legacy.toV6(gridColumns: Self.currentGridColumns(defaults: defaults))
            fileStore.save(position, queryKey: queryKey)
            migrated += 1
        }
        if migrated > 0 {
            ViewerTrace.log("position.migrate v1-v4 → v6 count=\(migrated)")
        }
    }
}