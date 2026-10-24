// MARK: - 职责说明：日 / 月 / 年分组（docs/05 M1 任务 1.5，docs/04 §3.1 月份分组粘性头 + 索引条）。
// 纯函数：输入 id + 日期，输出有序分组；时区/日历由调用方注入以便跨时区单测（docs/03 §8）。
// TODO(P1): 分组实现（含无日期 asset 归入「未知」组、跨年/跨月边界）。

import Foundation

/// 分组粒度
public enum SectionGranularity {
    case day
    case month
    case year
}

/// 一个分组：identifier 用于 Diffable 差异化，title 为中文展示文案（如「2026年10月」）
public struct DateSection {
    public let identifier: String
    public let title: String
    public let itemIDs: [String]

    public init(identifier: String, title: String, itemIDs: [String]) {
        self.identifier = identifier
        self.title = title
        self.itemIDs = itemIDs
    }
}

public enum DateSectionizer {
    /// - Parameters:
    ///   - ids: 与 dates 一一对应的条目标识
    ///   - dates: 拍摄日期（可为 nil → 归入「未知」组）
    ///   - granularity: 日 / 月 / 年
    public static func sections(ids: [String],
                                dates: [Date?],
                                granularity: SectionGranularity) -> [DateSection] {
        precondition(ids.count == dates.count, "ids 与 dates 必须一一对应")
        // TODO(P1): 按粒度分组并保持时间倒序
        return []
    }
}
