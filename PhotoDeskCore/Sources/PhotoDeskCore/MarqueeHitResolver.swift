// MARK: - 职责说明：框选命中纯函数（M17 T03，docs/32 §2.4/§4.1）——
// 「矩形 + 一组真实 cell frame → 命中 id 集合」的唯一实现；App 侧（T04 GridHitTester）只喂
// layoutAttributes 换算出的真实 frame，不再由网格参数推算（docs/31 G7/G8/G10 根因收口）。
// 相交判定为闭区间（贴边即命中）；HitRect.init 自动归一（反向拖等价）并做 1pt 扩展
// （零尺寸起手矩形命中手指下 cell，沿 M15 先例）；clipTop 把矩形上边抬到钉住头下缘
// （粘性头遮住的 cell 不得被框选，docs/31 G11），抬后为空返回空集。
// 非有限矩形 → 空集；非有限/退化 frame 逐个跳过（不得产生幽灵命中）；cells 允许乱序与同 id 重复。
// 仅 import Foundation，全部 Double（红线 2）。

import Foundation

/// 一个 cell 的真实 frame（由 App 侧 layoutAttributes 换算；id 即 PhotoItem.id）
public struct CellFrame: Hashable, Sendable {
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
}

/// 框选矩形（anchor/current 两点构造：自动归一 + 四边各扩 1pt）
public struct HitRect: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(anchor: (Double, Double), current: (Double, Double)) {
        self.minX = Swift.min(anchor.0, current.0) - 1
        self.minY = Swift.min(anchor.1, current.1) - 1
        self.maxX = Swift.max(anchor.0, current.0) + 1
        self.maxY = Swift.max(anchor.1, current.1) + 1
    }
}

public enum MarqueeHitResolver {
    /// 闭区间相交：贴边即命中；clipTop 非 nil 时先把矩形上边抬到该值（粘性头下缘）。
    /// 非有限矩形 → 空集；cells 乱序/同 id 重复均安全；性能 O(n)（2 万 frame < 20ms，CI 容器预算）。
    public static func hit(_ rect: HitRect, cells: [CellFrame], clipTop: Double? = nil) -> Set<String> {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite,
              rect.minX <= rect.maxX, rect.minY <= rect.maxY else { return [] }
        var top = rect.minY
        if let clipTop, clipTop.isFinite, clipTop > top {
            top = clipTop
        }
        guard top <= rect.maxY else { return [] }   // 抬后矩形为空（整段被粘性头遮住）
        var result = Set<String>(minimumCapacity: 8)
        for cell in cells {
            guard cell.minX.isFinite, cell.minY.isFinite, cell.maxX.isFinite, cell.maxY.isFinite,
                  cell.minX <= cell.maxX, cell.minY <= cell.maxY else { continue }
            if cell.minX <= rect.maxX, cell.maxX >= rect.minX,
               cell.minY <= rect.maxY, cell.maxY >= top {
                result.insert(cell.id)
            }
        }
        return result
    }
}
