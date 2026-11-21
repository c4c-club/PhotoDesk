// MARK: - 职责说明：单指滑选纯逻辑——边缘自动滚动速度与 contentOffset 钳制下沉 Core；
// 仅用 Double，零 UIKit / IndexPath / 图片对象。SlideSelectCell 随参数推算命中路径
// 一并于 M17 T04 删除（命中由 App 层 GridHitTester 真实 attributes 完成，docs/32 §2.4）；
// 方向锁 / 长按判定已迁往 SelectionGestureMachine（M17 T02，docs/32 §2.2）。

import Foundation

/// 混合命中模式（M20 T04，docs/49 T04 §2.2）：同带/横向占优按 cell 扫掠，纵向跨带占优按整行展开。
public enum SlideSelectHitMode: Equatable, Sendable {
    case cells
    case rows
}

public enum SlideSelectPolicy {
    /// 线段命中模式判定（docs/49 T04 §2.2）：fromBand == toBand → .cells；
    /// |dy| ≥ |dx| × verticalDominanceRatio → .rows；其余 → .cells；
    /// 非有限 dx/dy/ratio 或非正 ratio → .cells（不崩溃）。
    public static func hitMode(
        dx: Double,
        dy: Double,
        fromBand: Int,
        toBand: Int,
        verticalDominanceRatio: Double
    ) -> SlideSelectHitMode {
        guard dx.isFinite, dy.isFinite,
              verticalDominanceRatio.isFinite, verticalDominanceRatio > 0 else { return .cells }
        guard fromBand != toBand else { return .cells }
        if abs(dy) >= abs(dx) * verticalDominanceRatio { return .rows }
        return .cells
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
