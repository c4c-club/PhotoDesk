// MARK: - 职责说明：位置锚点选择纯函数（docs/22 §4.4.2）——
// 在可见 cell 集合里选择「第一条完整可见、且不被粘性月份头遮挡」的 cell；只用 Int / Double，
// 零 UIKit / IndexPath / CGRect。调用方传入 effectiveTop（contentOffset + adjustedInset + 月份头高度）
// 与 viewportBottom，保证保存与恢复共用同一视觉语义。

import Foundation

/// 可见网格 cell 的布局快照（未变换 frame 的 minY / maxY，content 坐标系）。
public struct VisibleGridCell: Equatable, Sendable {
    public let section: Int
    public let item: Int
    public let minY: Double
    public let maxY: Double

    public init(section: Int, item: Int, minY: Double, maxY: Double) {
        self.section = section
        self.item = item
        self.minY = minY
        self.maxY = maxY
    }
}

public enum PositionAnchorSelector {
    /// 选择第一条完整可见且不被粘性头遮挡的 cell：
    /// 1) 按 (section, item) 升序；
    /// 2) 过滤 maxY > effectiveTop 且 minY >= effectiveTop - 0.5 且 minY < viewportBottom；
    /// 3) 取第一条；
    /// 4) 没有完整可见时，取 maxY > effectiveTop 的第一条（部分可见兜底，允许 visualY 为负）。
    /// 任一输入非有限 / viewportBottom <= effectiveTop → nil（调用方不得写位置）。
    public static func select(cells: [VisibleGridCell],
                              effectiveTop: Double,
                              viewportBottom: Double) -> VisibleGridCell? {
        guard effectiveTop.isFinite, viewportBottom.isFinite,
              viewportBottom > effectiveTop, !cells.isEmpty else { return nil }
        let sorted = cells.sorted {
            if $0.section != $1.section { return $0.section < $1.section }
            return $0.item < $1.item
        }
        let fullyVisible = sorted.first {
            $0.minY.isFinite && $0.maxY.isFinite
                && $0.maxY > effectiveTop
                && $0.minY >= effectiveTop - 0.5
                && $0.minY < viewportBottom
        }
        if let fullyVisible { return fullyVisible }
        return sorted.first {
            $0.minY.isFinite && $0.maxY.isFinite
                && $0.maxY > effectiveTop
                && $0.minY < viewportBottom
        }
    }
}
