// MARK: - 职责说明：单指滑选纯逻辑——方向锁、快照恢复、去重、边缘速度与 offset 钳制全部下沉 Core；仅用 Double 与自定义 cell 值类型，零 UIKit / IndexPath / 图片对象。

import Foundation

public struct SlideSelectCell: Hashable, Codable, Sendable {
    public let section: Int
    public let item: Int

    public init(section: Int, item: Int) {
        self.section = section
        self.item = item
    }
}

public enum SlideSelectActivation: Equatable, Sendable {
    case horizontal
    case verticalLocked
    case none
}

public enum SlideSelectPolicy {
    /// `.changed` 才调用：仅水平位移严格大于垂直位移时激活；垂直占优或相等时锁住本手势余生。
    /// 非有限值按安全策略锁住，绝不激活选择，避免 NaN 污染 contentOffset / 手势状态。
    public static func shouldActivate(dx: Double, dy: Double, wasLocked: Bool) -> SlideSelectActivation {
        let horizontal = Swift.abs(dx)
        let vertical = Swift.abs(dy)
        if horizontal == 0, vertical == 0 { return .none }
        if wasLocked { return .verticalLocked }
        guard dx.isFinite, dy.isFinite else { return .verticalLocked }

        let epsilon = Swift.max(0, SlideSelectConfig.directionLockEpsilon)
        if horizontal > vertical + epsilon { return .horizontal }
        if vertical + epsilon >= horizontal { return .verticalLocked }
        return .none
    }

    /// 每次经过 cell 写一帧结果：奇数次经过置 true；偶数次（反向滑回）恢复滑动开始时的选中值。
    /// 原本已选中的 cell 永远不会在滑回时误取消。
    public static func resolvedSelection(
        originallySelected: Set<SlideSelectCell>,
        visited: [SlideSelectCell]
    ) -> [SlideSelectCell: Bool] {
        let cells = deduplicated(visited)
        guard !cells.isEmpty else { return [:] }

        var counts: [SlideSelectCell: Int] = [:]
        for cell in cells { counts[cell, default: 0] += 1 }

        var result: [SlideSelectCell: Bool] = [:]
        for (cell, count) in counts {
            let snapshotValue = originallySelected.contains(cell)
            result[cell] = (count % 2 == 1) ? true : snapshotValue
        }
        return result
    }

    /// 只去掉连续重复命中，保留 a → b → a 的回滑路径；语义对应 `lastProcessedIndexPath` 去重。
    public static func deduplicated(_ visited: [SlideSelectCell]) -> [SlideSelectCell] {
        var result: [SlideSelectCell] = []
        for cell in visited where result.last != cell {
            result.append(cell)
        }
        return result
    }

    /// 顶部缓冲区返回负速度，底部缓冲区返回正速度；缓冲区外返回 0。
    /// 速度按「距边距离 / buffer」线性映射 minStep...maxStep，非法输入返回 0。
    public static func edgeVelocity(
        fingerY: Double,
        top: Double,
        bottom: Double,
        buffer: Double,
        minStep: Double,
        maxStep: Double
    ) -> Double {
        guard fingerY.isFinite, top.isFinite, bottom.isFinite, buffer.isFinite,
              minStep.isFinite, maxStep.isFinite,
              buffer > 0, bottom >= top,
              minStep >= 0, maxStep >= minStep else { return 0 }

        let topLimit = top + buffer
        let bottomLimit = bottom - buffer
        let range = maxStep - minStep
        let ratio: Double
        let sign: Double

        if fingerY <= topLimit {
            let distance = Swift.max(0, Swift.min(buffer, topLimit - fingerY))
            ratio = Swift.min(1, Swift.max(0, distance / buffer))
            sign = -1
        } else if fingerY >= bottomLimit {
            let distance = Swift.max(0, Swift.min(buffer, fingerY - bottomLimit))
            ratio = Swift.min(1, Swift.max(0, distance / buffer))
            sign = 1
        } else {
            return 0
        }

        let speed = minStep + range * ratio
        guard speed.isFinite else { return 0 }
        return sign * speed
    }

    /// 钳制 contentOffset.y；反转边界自动归一，NaN 回落到下界，±∞ 落到对应边界。
    public static func clampedOffset(
        current: Double,
        delta: Double,
        min: Double,
        max: Double
    ) -> Double {
        let lower = Swift.min(min, max)
        let upper = Swift.max(min, max)
        guard lower.isFinite, upper.isFinite else { return 0 }
        guard current.isFinite else { return lower }

        let target: Double
        if delta.isNaN {
            target = lower
        } else if delta == Double.infinity {
            target = upper
        } else if delta == -Double.infinity {
            target = lower
        } else {
            target = current + delta
        }

        guard target.isFinite else {
            if delta > 0 { return upper }
            return lower
        }
        return Swift.min(Swift.max(target, lower), upper)
    }
}
