// MARK: - 职责说明：筛选引擎（docs/05 M5 任务 5.1）——SearchPredicate → [PhotoItem] 纯函数匹配。
/// 性能预算：10,000 张组合筛选 < 500ms（docs/05 §7 验收；SearchPredicateTests 以万级合成数据实测）。
/// 设计：单次遍历 + Calendar 组件比较（按需惰性取件日期组件）；谓词不活跃时原样返回。

import Foundation

enum PhotoFilter {
    /// - Parameters:
    ///   - items: 已加载条目（任意顺序）
    ///   - predicate: 组合筛选条件
    ///   - calendar: 日历/时区注入（默认当前；测试可固定）
    static func apply(_ items: [PhotoItem],
                      predicate: SearchPredicate,
                      calendar: Calendar = .current) -> [PhotoItem] {
        guard predicate.isActive else { return items }
        // 日期组件映射按需缓存（同一年月的条目复用 components 结果成本可忽略）
        return items.filter { matches($0, predicate: predicate, calendar: calendar) }
    }

    static func matches(_ item: PhotoItem,
                         predicate: SearchPredicate,
                         calendar: Calendar) -> Bool {
        // 日期下钻：设置了的每一级都必须匹配
        if let year = predicate.year {
            guard let date = item.creationDate,
                  calendar.component(.year, from: date) == year else { return false }
            if let month = predicate.month {
                guard calendar.component(.month, from: date) == month else { return false }
            }
            if let day = predicate.day {
                guard calendar.component(.day, from: date) == day else { return false }
            }
        } else if predicate.month != nil || predicate.day != nil {
            // 只有月/日没有年：按绝对值匹配月（与日）
            guard let date = item.creationDate else { return false }
            if let month = predicate.month,
               calendar.component(.month, from: date) != month { return false }
            if let day = predicate.day,
               calendar.component(.day, from: date) != day { return false }
        }

        // 媒体多选：任一命中即可（OR）
        if !predicate.media.isEmpty {
            guard predicate.media.contains(where: { matchesMedia(item, filter: $0) }) else { return false }
        }

        // 状态：全部满足（AND）
        for status in predicate.status {
            switch status {
            case .favorite:
                guard item.isFavorite else { return false }
            case .unorganized:
                guard !item.isFavorite else { return false }
            }
        }
        return true
    }

    static func matchesMedia(_ item: PhotoItem, filter: SearchPredicate.MediaFilter) -> Bool {
        switch filter {
        case .photo:      return item.mediaType == .image
        case .video:      return item.mediaType == .video
        case .live:       return item.mediaSubtypes.contains(.photoLive)
        case .screenshot: return item.mediaSubtypes.contains(.photoScreenshot)
        case .portrait:   return item.mediaSubtypes.contains(.photoDepthEffect)
        case .panorama:   return item.mediaSubtypes.contains(.photoPanorama)
        case .slowMotion: return item.mediaSubtypes.contains(.videoSlowMo)
        case .timeLapse:  return item.mediaSubtypes.contains(.videoTimelapse)
        }
    }

    // MARK: - 维度取值（筛选拾取器选项源）

    /// 全部条目里出现过的年份（降序）
    static func availableYears(_ items: [PhotoItem], calendar: Calendar = .current) -> [Int] {
        var years = Set<Int>()
        for item in items {
            guard let date = item.creationDate else { continue }
            years.insert(calendar.component(.year, from: date))
        }
        return years.sorted(by: >)
    }

    /// 指定年份下出现过的月份（降序）
    static func availableMonths(_ items: [PhotoItem], year: Int, calendar: Calendar = .current) -> [Int] {
        var months = Set<Int>()
        for item in items {
            guard let date = item.creationDate,
                  calendar.component(.year, from: date) == year else { continue }
            months.insert(calendar.component(.month, from: date))
        }
        return months.sorted(by: >)
    }

    /// 指定年月下出现过的日（降序）
    static func availableDays(_ items: [PhotoItem], year: Int, month: Int,
                              calendar: Calendar = .current) -> [Int] {
        var days = Set<Int>()
        for item in items {
            guard let date = item.creationDate,
                  calendar.component(.year, from: date) == year,
                  calendar.component(.month, from: date) == month else { continue }
            days.insert(calendar.component(.day, from: date))
        }
        return days.sorted(by: >)
    }
}
