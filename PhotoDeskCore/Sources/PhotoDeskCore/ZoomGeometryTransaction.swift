// MARK: - 职责说明：缩放事务几何提交纯逻辑——活跃期多次写入合并为一次，非有限/非正 pending 丢弃；contentInset 只按未变换 bounds 计算一次，零 Apple 依赖。

import Foundation

/// 一次待提交的几何快照：contentSize / contentInset / zoomScale 全部用 Double 值类型表达，App 侧只做 CGFloat 适配。
public struct ZoomGeometryCommit: Equatable {
    public let contentSize: DoubleSize
    public let insets: DoubleInsets
    public let zoomScale: Double

    public init(contentSize: DoubleSize, insets: DoubleInsets, zoomScale: Double) {
        self.contentSize = contentSize
        self.insets = insets
        self.zoomScale = zoomScale
    }
}

public enum ZoomGeometryTransaction {
    /// 校验全部有限且宽高严格 > 0、inset 非负、scale 有限且 > 0；不合格直接丢弃，不写 UIKit 属性。
    public static func sanitized(_ commit: ZoomGeometryCommit) -> ZoomGeometryCommit? {
        let size = commit.contentSize
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }

        let insets = commit.insets
        guard insets.top.isFinite, insets.left.isFinite,
              insets.bottom.isFinite, insets.right.isFinite,
              insets.top >= 0, insets.left >= 0,
              insets.bottom >= 0, insets.right >= 0 else { return nil }

        guard commit.zoomScale.isFinite, commit.zoomScale > 0 else { return nil }
        return commit
    }

    /// 活跃期所有 pending 合并为 0 或 1 次提交：非有限/非正项丢弃，最后一次有效值胜出。
    /// 返回数组而非可选值，便于测试直接断言「合并为一次」。
    public static func coalesced(_ pending: [ZoomGeometryCommit]) -> [ZoomGeometryCommit] {
        guard let last = pending.reversed().compactMap(sanitized).first else { return [] }
        return [last]
    }

    public static func merged(_ pending: [ZoomGeometryCommit]) -> ZoomGeometryCommit? {
        coalesced(pending).first
    }

    /// 居中 inset 只由未变换 bounds 计算；禁止再乘一次 zoomScale 造成双倍补偿。
    public static func centeringInsets(content: DoubleSize, viewport: DoubleSize, zoomScale: Double) -> DoubleInsets {
        ZoomGeometry.centeredInset(
            contentWidth: content.width,
            contentHeight: content.height,
            viewportWidth: viewport.width,
            viewportHeight: viewport.height,
            zoomScale: zoomScale
        )
    }
}
