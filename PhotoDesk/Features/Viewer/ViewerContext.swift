// MARK: - 职责说明：查看器打开上下文（docs/09 D01 ★）——网格点击时直接传「当前筛选结果 + 被点的
// assetID」，替代旧扁平 index（分组/筛选变化会让 index 错位 → 永远停在第 1 张的根因）。
// queryKey 供查看器记忆（library.viewer.lastAssetID.<queryKey>，docs/09 D08）。

import Foundation

struct ViewerContext: Identifiable {
    let id = UUID()
    /// 当前筛选结果快照（与网格一致）
    let items: [PhotoItem]
    /// 被点击的条目（按 assetID 定位，不按 index）
    let startItemID: String
    /// 来源查询键（位置记忆 / 查看器记忆命名空间）
    let queryKey: String

    init(items: [PhotoItem], startItemID: String, queryKey: String = "") {
        self.items = items
        self.startItemID = startItemID
        self.queryKey = queryKey
    }
}
