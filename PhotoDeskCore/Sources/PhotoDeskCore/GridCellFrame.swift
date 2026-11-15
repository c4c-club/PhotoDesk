// MARK: - 职责说明：网格 cell 真实 frame 值类型（M18 T03，docs/38 §3）——
// 从 MarqueeHitResolver.swift 抽出，避免线段命中等新逻辑依赖 marquee 命名；
// App 层由 layoutAttributes.frame 换算喂入（GridHitTester），Core 只收 Double（红线 2）。
// 旧 MarqueeHitResolver.swift 以 typealias CellFrame = GridCellFrame 桥接，旧单测照常编译。

import Foundation

/// 网格 cell 在内容坐标系的轴对齐包围盒（闭区间语义：贴边计为相交）。
public struct GridCellFrame: Hashable, Sendable {
    public let id: String
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(id: String, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.id = id
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// 合法性：有限值且 min ≤ max（退化/非法 frame 由命中方逐个跳过）。
    var isValid: Bool {
        minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite
            && minX <= maxX && minY <= maxY
    }
}
