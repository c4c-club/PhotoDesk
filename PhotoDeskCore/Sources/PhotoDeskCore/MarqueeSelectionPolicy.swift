// MARK: - 职责说明：框选集合纯语义（docs/25 §6.1/§6.5）——模式判定（起手 cell 已选 → deselect、
// 未选 → select）与目标集合归并（select 并集 / deselect 差集 / scope 过滤）。
// deprecated：基于网格参数推算的 cells(in:)/GridMetrics/MarqueeRect 已于 M17 T04 删除
// （docs/32 §2.4，docs/31 G7/G8/G10、A09）——几何命中由 App 层 GridHitTester 读真实
// layoutAttributes 完成。本类型只剩集合语义；只用 String/Set，零 UIKit。

import Foundation

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
}
