// MARK: - 职责说明：矩形框选纯策略（docs/25 §6.2 / M15 P0-3/4，替换 SlideSelectRangePolicy 整行带）——
// 语义：start→current 构成矩形，与矩形相交的 cell 进入目标集合；起手 cell 已选 → deselect 模式，
// 未选 → select 模式；回拖自然收缩。几何：cell x = col*(itemWidth+spacing)，
// y = sectionOriginY + headerHeight + row*(itemHeight+spacing)；矩形宽/高为 0 扩展 1pt；
// 非有限输入返回空集合。只用 Double / Int / Set，零 UIKit。

import Foundation

public struct GridMetrics: Equatable, Sendable {
    public let columns: Int
    public let itemWidth: Double
    public let itemHeight: Double
    public let interItemSpacing: Double
    public let sectionHeaderHeight: Double
    public let sectionItemCounts: [Int]

    public init(columns: Int,
                itemWidth: Double,
                itemHeight: Double,
                interItemSpacing: Double,
                sectionHeaderHeight: Double,
                sectionItemCounts: [Int]) {
        self.columns = columns
        self.itemWidth = itemWidth
        self.itemHeight = itemHeight
        self.interItemSpacing = interItemSpacing
        self.sectionHeaderHeight = sectionHeaderHeight
        self.sectionItemCounts = sectionItemCounts
    }
}

public struct MarqueeRect: Equatable, Sendable {
    public let startX: Double
    public let startY: Double
    public let currentX: Double
    public let currentY: Double

    public init(startX: Double, startY: Double, currentX: Double, currentY: Double) {
        self.startX = startX
        self.startY = startY
        self.currentX = currentX
        self.currentY = currentY
    }
}

public enum MarqueeMode: Equatable, Sendable {
    case select
    case deselect
}

public enum MarqueeSelectionPolicy {
    /// 起手 cell 已选中 → 取消模式；未选中 → 选择模式（docs/25 §6.1）。
    public static func mode(baseIDs: Set<String>, anchorID: String) -> MarqueeMode {
        baseIDs.contains(anchorID) ? .deselect : .select
    }

    /// select → base ∪ hit；deselect → base − hit。提供 scope 时 hit 先按 scope 过滤
    /// （月份 scope 等子集选择下，矩形跨出 scope 的 cell 不参与）。
    public static func resolved(base: Set<String>,
                                hitIDs: Set<String>,
                                mode: MarqueeMode,
                                scope: Set<String>? = nil) -> Set<String> {
        let effective = scope.map { hitIDs.intersection($0) } ?? hitIDs
        switch mode {
        case .select:
            return base.union(effective)
        case .deselect:
            return base.subtracting(effective)
        }
    }

    /// 计算矩形与网格相交的 cell 集合；O(矩形覆盖行数 × 列数)。
    public static func cells(in rect: MarqueeRect,
                             metrics: GridMetrics,
                             sectionOriginY: [Double]) -> Set<SlideSelectCell> {
        guard metrics.columns >= 1,
              isUsable(metrics.itemWidth), isUsable(metrics.itemHeight),
              metrics.interItemSpacing.isFinite, metrics.interItemSpacing >= 0,
              metrics.sectionHeaderHeight.isFinite, metrics.sectionHeaderHeight >= 0,
              !metrics.sectionItemCounts.isEmpty,
              sectionOriginY.count == metrics.sectionItemCounts.count,
              rect.startX.isFinite, rect.startY.isFinite,
              rect.currentX.isFinite, rect.currentY.isFinite else {
            return []
        }
        var minX = min(rect.startX, rect.currentX)
        var minY = min(rect.startY, rect.currentY)
        var maxX = max(rect.startX, rect.currentX)
        var maxY = max(rect.startY, rect.currentY)
        // 宽/高为 0 → 扩展 1pt：竖直/水平拖动至少命中手指下的 cell
        if maxX - minX < 1 { maxX = minX + 1 }
        if maxY - minY < 1 { maxY = minY + 1 }

        let pitchX = metrics.itemWidth + metrics.interItemSpacing
        let pitchY = metrics.itemHeight + metrics.interItemSpacing
        var result = Set<SlideSelectCell>()
        for section in 0..<metrics.sectionItemCounts.count {
            let itemCount = metrics.sectionItemCounts[section]
            guard itemCount > 0, section < sectionOriginY.count else { continue }
            let origin = sectionOriginY[section]
            guard origin.isFinite else { continue }
            let top = origin + metrics.sectionHeaderHeight
            let maxRow = (itemCount - 1) / metrics.columns
            // 行候选：起点行向前回退一行防浮点误差，逐行精确相交测试，越过矩形底边即停
            var row = Int(Foundation.floor((minY - top) / pitchY)) - 1
            if row < 0 { row = 0 }
            while row <= maxRow {
                let cellTop = top + Double(row) * pitchY
                if cellTop > maxY { break }
                let cellBottom = cellTop + metrics.itemHeight
                guard cellBottom >= minY else {
                    row += 1
                    continue
                }
                // 列候选：同样向前回退一行列防误差
                var column = Int(Foundation.floor(minX / pitchX)) - 1
                if column < 0 { column = 0 }
                while column < metrics.columns {
                    let cellLeft = Double(column) * pitchX
                    if cellLeft > maxX { break }
                    let cellRight = cellLeft + metrics.itemWidth
                    if cellRight >= minX,
                       cellRight.isFinite, cellLeft.isFinite {
                        let item = row * metrics.columns + column
                        if item < itemCount {
                            result.insert(SlideSelectCell(section: section, item: item))
                        }
                    }
                    column += 1
                }
                row += 1
            }
        }
        return result
    }

    private static func isUsable(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
