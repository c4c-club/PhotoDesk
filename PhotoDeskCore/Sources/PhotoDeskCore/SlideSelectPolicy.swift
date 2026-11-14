// MARK: - 职责说明：单指滑选纯逻辑——边缘自动滚动速度与 contentOffset 钳制下沉 Core；
// 仅用 Double 与自定义 cell 值类型，零 UIKit / IndexPath / 图片对象。
// 方向锁 / 长按判定已迁往 SelectionGestureMachine（M17 T02，docs/32 §2.2）；
// 旧方向锁 / 往返奇偶选择死代码已删除（docs/31 X10）。

import Foundation

public struct SlideSelectCell: Hashable, Codable, Sendable {
    public let section: Int
    public let item: Int

    public init(section: Int, item: Int) {
        self.section = section
        self.item = item
    }
}

public enum SlideSelectPolicy {
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
