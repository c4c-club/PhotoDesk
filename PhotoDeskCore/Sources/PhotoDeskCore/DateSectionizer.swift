// MARK: - 职责说明：日 / 月 / 年分组（docs/05 M1 任务 1.5，docs/04 §3.1 月份分组粘性头 + 索引条）。
// 纯函数：输入 id + 日期，输出有序分组；日历/时区/语言由调用方注入，保证跨时区可单测（docs/03 §8）。
// 约定：调用方负责按时间倒序传入（App 侧 fetch 已按 creationDate desc）；无日期条目归入「未知时间」组且置于末尾。

import Foundation

/// 分组粒度
public enum SectionGranularity {
    case day
    case month
    case year
}

/// 一个分组：identifier 用于 Diffable 差异化，title 为展示文案（zh_CN 下如「2026年10月」）
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
    /// 无日期条目所在组的固定 identifier
    public static let unknownIdentifier = "unknown"

    /// - Parameters:
    ///   - ids: 与 dates 一一对应的条目标识（约定已按时间倒序）
    ///   - dates: 拍摄日期（可为 nil → 「未知时间」组）
    ///   - granularity: 日 / 月 / 年
    ///   - calendar: 注入日历（含时区），默认 Calendar.current
    ///   - locale: 注入语言，默认 zh_CN（标题如「2026年10月」）
    public static func sections(ids: [String],
                                dates: [Date?],
                                granularity: SectionGranularity,
                                calendar: Calendar = .current,
                                locale: Locale = Locale(identifier: "zh_CN")) -> [DateSection] {
        precondition(ids.count == dates.count, "ids 与 dates 必须一一对应")

        struct Bucket {
            var ids: [String]
            var sample: Date   // 组内第一个日期；输入倒序时即为组内最大日期，用于组间排序
        }

        var buckets: [DateComponents: Bucket] = [:]
        var order: [DateComponents] = []
        var unknownIDs: [String] = []

        for (index, id) in ids.enumerated() {
            guard let date = dates[index] else {
                unknownIDs.append(id)
                continue
            }
            let components: DateComponents
            switch granularity {
            case .year:  components = calendar.dateComponents([.year], from: date)
            case .month: components = calendar.dateComponents([.year, .month], from: date)
            case .day:   components = calendar.dateComponents([.year, .month, .day], from: date)
            }
            if buckets[components] == nil {
                order.append(components)
            }
            buckets[components, default: Bucket(ids: [], sample: date)].ids.append(id)
        }

        var result = order
            .compactMap { components -> (DateComponents, Bucket)? in
                buckets[components].map { (components, $0) }
            }
            .sorted { $0.1.sample > $1.1.sample }
            .map { components, bucket in
                DateSection(identifier: identifier(for: components, granularity: granularity),
                            title: title(for: components, granularity: granularity,
                                         calendar: calendar, locale: locale),
                            itemIDs: bucket.ids)
            }
        if !unknownIDs.isEmpty {
            result.append(DateSection(identifier: unknownIdentifier,
                                      title: "未知时间",
                                      itemIDs: unknownIDs))
        }
        return result
    }

    /// 稳定标识：年 → "2026"；月 → "2026-10"；日 → "2026-10-03"
    static func identifier(for components: DateComponents, granularity: SectionGranularity) -> String {
        guard let year = components.year else { return unknownIdentifier }
        switch granularity {
        case .year:
            return String(format: "%04d", year)
        case .month:
            guard let month = components.month else { return unknownIdentifier }
            return String(format: "%04d-%02d", year, month)
        case .day:
            guard let month = components.month, let day = components.day else { return unknownIdentifier }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    /// 展示标题（zh_CN：年「2026年」/ 月「2026年10月」/ 日「2026年10月3日」）
    static func title(for components: DateComponents, granularity: SectionGranularity,
                      calendar: Calendar, locale: Locale) -> String {
        guard let date = calendar.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        switch granularity {
        case .year:  formatter.setLocalizedDateFormatFromTemplate("y")
        case .month: formatter.setLocalizedDateFormatFromTemplate("yMMM")
        case .day:   formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        }
        return formatter.string(from: date)
    }
}
