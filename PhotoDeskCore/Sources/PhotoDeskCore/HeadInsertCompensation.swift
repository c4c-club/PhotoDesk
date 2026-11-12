// MARK: - 职责说明：head 回填前插补偿纯策略（docs/28 §5.5 步骤 4 / M16 T03）——
// 每个 head 批次前插后按 contentHeight delta 调整 contentOffset.y：
// 插入项位于锚点上方 → 锚点视觉位置被推走，offset += delta；插入在锚点下方 → 不变。
// 非有限 / 非正 delta 一律拒绝调整；maxOffsetY 非法（≤0 / 非有限）→ 放弃补偿保持原值；
// 结果钳制 [0, maxOffsetY]。多批用 Ledger 累计。纯 Foundation / Double，零 UIKit。

import Foundation

public enum HeadInsertCompensationPolicy {
    /// 单批补偿：返回调整后的 offset（无需调整 / 无法安全调整时返回原值）。
    public static func adjustedOffsetY(beforeY: Double,
                                       contentHeightBefore: Double,
                                       contentHeightAfter: Double,
                                       insertedAboveAnchor: Bool,
                                       maxOffsetY: Double) -> Double {
        guard beforeY.isFinite else { return 0 }
        guard let safeMax = validMax(maxOffsetY) else { return beforeY }
        let delta = contentHeightAfter - contentHeightBefore
        guard delta.isFinite, delta > 0, insertedAboveAnchor else {
            return clamp(beforeY, max: safeMax)
        }
        return clamp(beforeY + delta, max: safeMax)
    }

    private static func validMax(_ value: Double) -> Double? {
        (value.isFinite && value > 0) ? value : nil
    }

    private static func clamp(_ y: Double, max maxY: Double) -> Double {
        Swift.min(Swift.max(y, 0), maxY)
    }

    /// 多批累计账本：每批 append 一次，offsetY 即当前应处的 contentOffset.y。
    public struct Ledger: Equatable, Sendable {
        public let maxOffsetY: Double
        public private(set) var offsetY: Double
        public private(set) var appliedDeltas: [Double] = []

        public init(initialY: Double, maxOffsetY: Double) {
            self.maxOffsetY = validMax(maxOffsetY) ?? 0
            self.offsetY = initialY.isFinite ? Self.clamp(initialY, max: self.maxOffsetY) : 0
        }

        public mutating func append(delta: Double, insertedAboveAnchor: Bool) {
            guard delta.isFinite, delta > 0, insertedAboveAnchor else { return }
            appliedDeltas.append(delta)
            offsetY = Swift.min(Swift.max(offsetY + delta, 0), maxOffsetY)
        }

        private static func clamp(_ y: Double, max maxY: Double) -> Double {
            Swift.min(Swift.max(y, 0), maxY)
        }
    }
}