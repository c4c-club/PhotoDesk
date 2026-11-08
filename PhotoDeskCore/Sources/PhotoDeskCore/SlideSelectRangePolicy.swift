// MARK: - 职责说明：滑动多选「整行区间」纯逻辑（docs/22 §5.4）——
// 官方相册语义：从起手 cell 到当前 cell，按行带选中整行所有列；跨 section 时中间 section 整段。
// 只用 Int / Set，零 UIKit / IndexPath / CGRect。

import Foundation

public struct SlideGridMetrics: Equatable, Sendable {
    public let columns: Int
    public let sectionItemCounts: [Int]

    public init(columns: Int, sectionItemCounts: [Int]) {
        self.columns = max(1, columns)
        self.sectionItemCounts = sectionItemCounts
    }
}

public enum SlideSelectRangePolicy {
    /// 行号：item / columns（负 item 防御为 0）。
    public static func row(of cell: SlideSelectCell, columns: Int) -> Int {
        guard columns > 0 else { return 0 }
        return max(0, cell.item) / columns
    }

    /// 某一 section 的行区间 [rows] 展开为存在的 item 集合；最后一行按 itemCount 截断。
    public static func items(inSection section: Int,
                             rows: ClosedRange<Int>,
                             itemCount: Int,
                             columns: Int) -> Set<SlideSelectCell> {
        guard section >= 0, columns > 0, itemCount > 0 else { return [] }
        let maxRow = (itemCount - 1) / columns
        let lower = max(0, min(rows.lowerBound, rows.upperBound))
        let upper = min(maxRow, max(rows.lowerBound, rows.upperBound))
        guard lower <= upper else { return [] }
        var result = Set<SlideSelectCell>()
        for row in lower...upper {
            let start = row * columns
            let end = min(start + columns, itemCount)
            guard start < end else { continue }
            for item in start..<end {
                result.insert(SlideSelectCell(section: section, item: item))
            }
        }
        return result
    }

    /// 行带：anchor 与 current 之间每个 section 按行区间取整行。
    /// - anchor 所在 section 的起始行 = anchor.item / columns；
    /// - current 所在 section 的结束行 = current.item / columns；
    /// - 中间 section 整段（第一行到实际最后一行）。
    public static func cells(anchor: SlideSelectCell,
                             current: SlideSelectCell,
                             metrics: SlideGridMetrics) -> Set<SlideSelectCell> {
        guard metrics.columns > 0, !metrics.sectionItemCounts.isEmpty else { return [] }
        // 回到起点（没有位移）→ 空区间：拖动新增的 anchor cell 在下一次 apply 时恢复快照；
        // 控制器在激活帧会单独把 anchor 加入目标，保证起手 cell 立即可见选中。
        if anchor == current { return [] }
        let lastSection = metrics.sectionItemCounts.count - 1
        let startSection = max(0, min(anchor.section, current.section, lastSection))
        let endSection = max(0, min(max(anchor.section, current.section), lastSection))
        guard startSection <= endSection else { return [] }

        var result = Set<SlideSelectCell>()
        for section in startSection...endSection {
            let itemCount = metrics.sectionItemCounts[section]
            guard itemCount > 0 else { continue }
            let startRow = section == anchor.section
                ? row(of: anchor, columns: metrics.columns)
                : 0
            let endRow = section == current.section
                ? row(of: current, columns: metrics.columns)
                : (itemCount - 1) / metrics.columns
            let lower = min(startRow, endRow)
            let upper = max(startRow, endRow)
            result.formUnion(items(inSection: section,
                                   rows: lower...upper,
                                   itemCount: itemCount,
                                   columns: metrics.columns))
        }
        return result
    }
}
