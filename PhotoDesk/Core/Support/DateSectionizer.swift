// MARK: - 职责说明：App 侧日期分组适配层（docs/05 M1 任务 1.5）——
// 纯逻辑在 PhotoDeskCore.DateSectionizer（红线 2：App 不重复实现）；本文件只做类型适配：
// 把网格的 (id, creationDate) 列表转为核心分组，再产出 Diffable 需要的 MonthSection 与按组排序的 id 列表。

import Foundation
import PhotoDeskCore

/// 网格月份分组（Diffable Section 标识）：id = 核心组 identifier（"2026-10"/"unknown"）
struct MonthSection: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int

    /// 粘性头展示文案：docs/04 §3.1「2026年10月 · 128 张」
    var headerTitle: String {
        "\(title) · \(count) 张"
    }
}

enum DateSectionizerAdapter {
    /// - Parameters:
    ///   - items: (id, creationDate) 列表，约定已按时间倒序（fetch 排序保证）
    /// - Returns: sections 与按组展开的 id 顺序（供快照逐组 appendItems）
    static func monthSections(ids: [String], dates: [Date?]) -> (sections: [MonthSection], orderedIDs: [String]) {
        let core = DateSectionizer.sections(ids: ids, dates: dates, granularity: .month)
        let sections = core.map { MonthSection(id: $0.identifier, title: $0.title, count: $0.itemIDs.count) }
        let orderedIDs = core.flatMap(\.itemIDs)
        return (sections, orderedIDs)
    }
}
