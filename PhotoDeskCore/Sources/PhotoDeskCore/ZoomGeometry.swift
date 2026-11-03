// MARK: - 职责说明：缩放几何纯函数（docs/13 §3.3 / S01）——
// UIScrollView 捏合缩放需要的全部几何计算下沉核心包（红线 2：纯 Double、零 Apple 依赖）。
// 所有函数对 0/负数/NaN/∞ 返回安全值（零尺寸/钳制/nil），杜绝「CALayer position contains NaN」崩溃。
// App 侧 ZoomableImageCell 只做 CGFloat↔Double 适配，不重复实现几何。

import Foundation

/// 尺寸（Double 版，避免 CGSize 进核心包）
public struct DoubleSize: Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = DoubleSize(width: 0, height: 0)
}

/// 矩形（内容视图坐标系，Double 版）
public struct DoubleRect: Equatable {
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
}

/// 内边距（滚动内容居中用，Double 版）
public struct DoubleInsets: Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = DoubleInsets(top: 0, left: 0, bottom: 0, right: 0)
}

public enum ZoomGeometry {
    /// aspectFit 后的显示尺寸：图片完整放进视口；任一输入 ≤0/NaN/∞ → .zero
    public static func aspectFitSize(imageWidth: Double, imageHeight: Double,
                                     viewportWidth: Double, viewportHeight: Double) -> DoubleSize {
        guard isSafePositive(imageWidth), isSafePositive(imageHeight),
              isSafePositive(viewportWidth), isSafePositive(viewportHeight) else {
            return .zero
        }
        let scale = Swift.min(viewportWidth / imageWidth, viewportHeight / imageHeight)
        guard scale.isFinite, scale > 0 else { return .zero }
        return DoubleSize(width: imageWidth * scale, height: imageHeight * scale)
    }

    /// 滚动内容居中 inset：content 小于视口 → 正 inset；大于视口（已放大）→ 0。
    /// contentWidth/Height 为「缩放前」的内容尺寸（内部乘 zoomScale）；非法输入一律返回 .zero。
    public static func centeredInset(contentWidth: Double, contentHeight: Double,
                                     viewportWidth: Double, viewportHeight: Double,
                                     zoomScale: Double) -> DoubleInsets {
        guard isSafePositive(contentWidth), isSafePositive(contentHeight),
              isSafePositive(viewportWidth), isSafePositive(viewportHeight) else {
            return .zero
        }
        let scale = sanitizedScale(zoomScale)
        guard scale.isFinite else { return .zero }
        let horizontal = Swift.max(0, (viewportWidth - contentWidth * scale) / 2)
        let vertical = Swift.max(0, (viewportHeight - contentHeight * scale) / 2)
        guard horizontal.isFinite, vertical.isFinite else { return .zero }
        return DoubleInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    /// 双击缩放目标矩形（zoom(to:) 用，zooming view 未缩放坐标系）：
    /// 以 focus 为中心取 viewport/zoomScale 的矩形，钳制在图片范围内；非法输入返回 nil（不缩放）。
    public static func clampedZoomRect(zoomScale: Double,
                                       focusX: Double, focusY: Double,
                                       viewportWidth: Double, viewportHeight: Double,
                                       imageWidth: Double, imageHeight: Double) -> DoubleRect? {
        guard isSafePositive(viewportWidth), isSafePositive(viewportHeight),
              isSafePositive(imageWidth), isSafePositive(imageHeight) else { return nil }
        let scale = sanitizedScale(zoomScale)
        guard scale.isFinite, scale > 0, isSafePositive(focusX), isSafePositive(focusY) else { return nil }

        var width = viewportWidth / scale
        var height = viewportHeight / scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        width = Swift.min(width, imageWidth)
        height = Swift.min(height, imageHeight)

        let x = clamp(focusX - width / 2, 0, Swift.max(0, imageWidth - width))
        let y = clamp(focusY - height / 2, 0, Swift.max(0, imageHeight - height))
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return nil }
        return DoubleRect(x: x, y: y, width: width, height: height)
    }

    /// 缩放倍率消毒：NaN/负数/0 → minScale；∞ → maxScale；其余钳制进 [minScale, maxScale]
    public static func sanitizedScale(_ scale: Double,
                                      minScale: Double = 1,
                                      maxScale: Double = 5) -> Double {
        let lower = (minScale.isFinite && minScale > 0) ? minScale : 1
        let upper = (maxScale.isFinite && maxScale >= lower) ? maxScale : lower
        guard scale.isFinite else { return scale > 0 ? upper : lower }
        if scale.isInfinite { return scale > 0 ? upper : lower }
        if scale <= 0 { return lower }
        return Swift.min(Swift.max(scale, lower), upper)
    }

    // MARK: - 私有

    private static func isSafePositive(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}
