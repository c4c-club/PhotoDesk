// MARK: - 职责说明：网格二维矩形命中纯函数（docs/16 M12 R08）——
// iOS 原生相册式拖动多选：拖曳矩形与每个 cell 实际可见 frame 的二维相交实时增减选中。
// 只 import Foundation；GridPoint/GridRect 为 Double 版（不传 CGRect/CGSize 进核心包，红线 2）。
// 合并语义二选一（docs/16 §2.8 修复 3，写死并测试）：锚点初态已选 → 反选（拖过即取消）；
// 锚点初态未选 → 加选（拖过即选中）——与 iOS 原生相册长按拖动一致。
// 0/负/NaN/∞ 输入一律安全返回；乱序与跨 section 输入安全。

import Foundation

/// 二维点（Double 版）
public struct GridPoint: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 二维矩形（Double 版；任意两点构造自动规范化）
public struct GridRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// 由任意两点构造（拖曳矩形：起点/当前手指点；负宽高取正、左上角归一）
    public init(from: GridPoint, to: GridPoint) {
        self.x = Swift.min(from.x, to.x)
        self.y = Swift.min(from.y, to.y)
        self.width = Swift.abs(from.x - to.x)
        self.height = Swift.abs(from.y - to.y)
    }

    public static let zero = GridRect(x: 0, y: 0, width: 0, height: 0)

    var isUsable: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite && width >= 0 && height >= 0
    }

    /// 与另一矩形的相交面积（不相交 = 0；任一非法 = 0）
    public func intersectionArea(with other: GridRect) -> Double {
        guard isUsable, other.isUsable else { return 0 }
        let left = Swift.max(x, other.x)
        let right = Swift.min(x + width, other.x + other.width)
        let top = Swift.max(y, other.y)
        let bottom = Swift.min(y + height, other.y + other.height)
        guard right > left, bottom > top else { return 0 }
        let area = (right - left) * (bottom - top)
        return area.isFinite ? area : 0
    }
}

/// 网格 cell 命中区域（App 层把 cell 的 view 坐标 frame 适配进来；跨 section 只按几何判定）
public struct GridCellRect: Equatable {
    public let id: String
    public let rect: GridRect

    public init(id: String, rect: GridRect) {
        self.id = id
        self.rect = rect
    }
}

public enum GridHitRegion {
    /// 拖曳矩形命中的 cell id 集合（二维相交 + 阈值）
    /// - Parameter threshold: 相交面积占 cell 面积的比例下限（0...1，超出钳制；App 侧 BoxSelectConfig）
    public static func hitIDs(cells: [GridCellRect], rect: GridRect, threshold: Double) -> Set<String> {
        guard rect.isUsable else { return [] }
        let t = sanitizedThreshold(threshold)
        var result = Set<String>()
        for cell in cells {
            guard cell.rect.isUsable, cell.rect.width > 0, cell.rect.height > 0 else { continue }
            let area = cell.rect.intersectionArea(with: rect)
            guard area > 0 else { continue }
            let cellArea = cell.rect.width * cell.rect.height
            guard cellArea > 0, cellArea.isFinite, area.isFinite else { continue }
            if area / cellArea >= t {
                result.insert(cell.id)
            }
        }
        return result
    }

    /// 基线重算合并语义（docs/16 §2.8 修复 3，二选一写死）：
    /// 锚点初态已选 → 反选（base − hits）；锚点初态未选 → 加选（base ∪ hits）。
    /// 每帧都从进入拖选前的基线重算，往回拖自然移除——禁止 base ∪ 一维区间累加。
    public static func mergedSelection(base: Set<String>,
                                       hits: Set<String>,
                                       anchorInitiallySelected: Bool) -> Set<String> {
        anchorInitiallySelected ? base.subtracting(hits) : base.union(hits)
    }

    private static func sanitizedThreshold(_ threshold: Double) -> Double {
        guard threshold.isFinite, threshold >= 0 else { return 0 }
        return Swift.min(threshold, 1)
    }
}
