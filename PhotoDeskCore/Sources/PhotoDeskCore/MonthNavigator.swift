// MARK: - 职责说明：月份导航纯函数（docs/13 S09）——
// 月份描述（id/year/month/count/title）、按年分组、最近月份索引（月份面板跳转 + 索引条兜底）。
// 全部纯 Foundation（红线 2）；App 侧 MonthJumpSheet / MonthIndexBar 只做展示适配。
// id 口径与 DateSectionizer 一致："2024-05"；"unknown"（无创建日期）不产出月份卡片。

import Foundation

/// 月份分组信息（App 侧 MonthSection 的核心镜像：id/title/count）
public struct MonthSectionInfo: Equatable {
    public let id: String
    public let title: String
    public let count: Int

    public init(id: String, title: String, count: Int) {
        self.id = id
        self.title = title
        self.count = count
    }
}

/// 月份卡片描述（MonthJumpSheet 一张卡片）
public struct MonthDescriptor: Equatable {
    /// "2024-05"
    public let id: String
    public let year: Int
    public let month: Int
    public let count: Int
    /// 展示标题："2024年5月"
    public let title: String

    public init(id: String, year: Int, month: Int, count: Int, title: String) {
        self.id = id
        self.year = year
        self.month = month
        self.count = count
        self.title = title
    }
}

/// 按年份聚合（MonthJumpSheet 分组头）
public struct YearGroup: Equatable {
    public let year: Int
    public let months: [MonthDescriptor]

    public init(year: Int, months: [MonthDescriptor]) {
        self.year = year
        self.months = months
    }
}

public enum MonthNavigator {
    /// 未知日期分组的 section id（与 DateSectionizer 对齐）
    public static let unknownIdentifier = "unknown"

    /// "2024-05"；month 钳制 1...12，year < 1 视为未知（返回 unknownIdentifier）
    public static func monthID(year: Int, month: Int) -> String {
        guard year >= 1 else { return unknownIdentifier }
        let clamped = Swift.min(Swift.max(month, 1), 12)
        return String(format: "%04d-%02d", year, clamped)
    }

    /// 从 section 列表抽取月份卡片：无法解析的 id（unknown/畸形）跳过，顺序保持输入序。
    public static func descriptors(from sections: [MonthSectionInfo]) -> [MonthDescriptor] {
        var result: [MonthDescriptor] = []
        var seen = Set<String>()
        for section in sections {
            guard let (year, month) = parse(section.id) else { continue }
            let id = section.id
            guard seen.insert(id).inserted else { continue }   // 重复 section 去重
            let title = section.title.isEmpty ? displayTitle(year: year, month: month) : section.title
            result.append(MonthDescriptor(id: id, year: year, month: month,
                                          count: section.count, title: title))
        }
        return result
    }

    /// 按年份分组（保持输入顺序；输入通常是时间倒序 → 组序 2026, 2025…）
    public static func yearGroups(_ descriptors: [MonthDescriptor]) -> [YearGroup] {
        var order: [Int] = []
        var buckets: [Int: [MonthDescriptor]] = [:]
        for descriptor in descriptors {
            if buckets[descriptor.year] == nil {
                order.append(descriptor.year)
            }
            buckets[descriptor.year, default: []].append(descriptor)
        }
        return order.map { YearGroup(year: $0, months: buckets[$0] ?? []) }
    }

    /// 月份 id → sections 中的最近索引：精确命中优先；否则按 (year*12+month) 距离取最近（并列取先出现者）。
    /// 跳过无法解析的 id（unknown）；空列表 → nil。
    public static func nearestIndex(for monthID: String, in ids: [String]) -> Int? {
        guard let target = parse(monthID).map({ linear($0.year, $0.month) }) else { return nil }
        var bestIndex: Int?
        var bestDistance = Int.max
        for (index, candidate) in ids.enumerated() {
            guard let (year, month) = parse(candidate) else { continue }
            let distance = abs(linear(year, month) - target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
                if distance == 0 { break }
            }
        }
        return bestIndex
    }

    /// 展示标题："2024年5月"
    public static func displayTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    // MARK: - 私有

    /// "2024-05" → (2024, 5)；"unknown"/畸形 → nil
    private static func parse(_ id: String) -> (year: Int, month: Int)? {
        guard id != unknownIdentifier, id.count == 7 else { return nil }
        let parts = id.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]), year >= 1,
              let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        return (year, month)
    }

    private static func linear(_ year: Int, _ month: Int) -> Int {
        year * 12 + month
    }
}
