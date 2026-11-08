// MARK: - 职责说明：缩放变换纯策略（docs/25 §4.3 / M15 P0-1）——
// 自管变换模型：显示尺寸 = aspectFit 尺寸 × scale，内容中心 = 视口中心 + translation。
// 全部几何只依赖 Foundation/Double（红线 2）；scale 复用 ZoomGeometry.sanitizedScale 消毒。
// 契约：钳制优先于锚点——内容小于视口的轴强制居中；锚点不变性只在钳制不触发时成立。

import Foundation

/// 一次缩放/平移后的变换状态。translation 为内容中心相对视口中心的偏移。
public struct ZoomTransform: Equatable, Sendable {
    /// 缩放倍率，恒在 [minScale, maxScale]（默认 1...5）
    public var scale: Double
    /// 相对视口中心的水平偏移（内容小于视口时恒为 0）
    public var translationX: Double
    /// 相对视口中心的垂直偏移（内容小于视口时恒为 0）
    public var translationY: Double

    public init(scale: Double = 1, translationX: Double = 0, translationY: Double = 0) {
        self.scale = scale
        self.translationX = translationX
        self.translationY = translationY
    }

    public static let identity = ZoomTransform(scale: 1, translationX: 0, translationY: 0)
}

public enum ZoomTransformPolicy {
    /// 捏合：pinchScale 为相对当前 scale 的乘法因子；保持 anchor（视口坐标）下的内容点不动。
    public static func pinch(current: ZoomTransform,
                             pinchScale: Double,
                             anchorX: Double, anchorY: Double,
                             contentWidth: Double, contentHeight: Double,
                             viewportWidth: Double, viewportHeight: Double,
                             minScale: Double = 1, maxScale: Double = 5) -> ZoomTransform {
        let newScale = ZoomGeometry.sanitizedScale(current.scale * pinchScale,
                                                   minScale: minScale, maxScale: maxScale)
        guard isUsable(contentWidth), isUsable(contentHeight),
              isUsable(viewportWidth), isUsable(viewportHeight) else {
            return ZoomTransform(scale: newScale, translationX: 0, translationY: 0)
        }
        // 当前 anchor 下的内容点（aspectFit 坐标）
        let qx = (anchorX - viewportWidth / 2 - current.translationX) / current.scale + contentWidth / 2
        let qy = (anchorY - viewportHeight / 2 - current.translationY) / current.scale + contentHeight / 2
        // 新 scale 下让同一内容点回到 anchor
        var tx = anchorX - viewportWidth / 2 - newScale * (qx - contentWidth / 2)
        var ty = anchorY - viewportHeight / 2 - newScale * (qy - contentHeight / 2)
        let clamped = clampTranslation(scale: newScale, tx: tx, ty: ty,
                                       contentWidth: contentWidth, contentHeight: contentHeight,
                                       viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        tx = clamped.x
        ty = clamped.y
        return ZoomTransform(scale: newScale, translationX: tx, translationY: ty)
    }

    /// 单指拖动：translation += delta，再按边界钳制（内容小于视口的轴居中）。
    public static func pan(current: ZoomTransform,
                           deltaX: Double, deltaY: Double,
                           contentWidth: Double, contentHeight: Double,
                           viewportWidth: Double, viewportHeight: Double,
                           minScale: Double = 1, maxScale: Double = 5) -> ZoomTransform {
        let scale = ZoomGeometry.sanitizedScale(current.scale, minScale: minScale, maxScale: maxScale)
        guard isUsable(contentWidth), isUsable(contentHeight),
              isUsable(viewportWidth), isUsable(viewportHeight) else {
            return ZoomTransform(scale: scale, translationX: 0, translationY: 0)
        }
        let targetX = deltaX.isFinite ? current.translationX + deltaX : current.translationX
        let targetY = deltaY.isFinite ? current.translationY + deltaY : current.translationY
        let clamped = clampTranslation(scale: scale, tx: targetX, ty: targetY,
                                       contentWidth: contentWidth, contentHeight: contentHeight,
                                       viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        return ZoomTransform(scale: scale, translationX: clamped.x, translationY: clamped.y)
    }

    /// 双击：1× → targetScale（点击点为锚）；已放大 → 回 1× 居中。
    public static func doubleTap(current: ZoomTransform,
                                 tapX: Double, tapY: Double,
                                 contentWidth: Double, contentHeight: Double,
                                 viewportWidth: Double, viewportHeight: Double,
                                 targetScale: Double = 2.5) -> ZoomTransform {
        guard current.scale > 1.01 else {
            guard isUsable(viewportWidth), isUsable(viewportHeight),
                  isUsable(contentWidth), isUsable(contentHeight) else {
                return ZoomTransform(scale: ZoomGeometry.sanitizedScale(targetScale), translationX: 0, translationY: 0)
            }
            guard tapX.isFinite, tapY.isFinite else {
                return ZoomTransform(scale: ZoomGeometry.sanitizedScale(targetScale), translationX: 0, translationY: 0)
            }
            let scale = ZoomGeometry.sanitizedScale(targetScale)
            // 当前 1× 居中：内容点 q = (tap - V/2)/1 + C/2
            let qx = (tapX - viewportWidth / 2) + contentWidth / 2
            let qy = (tapY - viewportHeight / 2) + contentHeight / 2
            var tx = tapX - viewportWidth / 2 - scale * (qx - contentWidth / 2)
            var ty = tapY - viewportHeight / 2 - scale * (qy - contentHeight / 2)
            let clamped = clampTranslation(scale: scale, tx: tx, ty: ty,
                                           contentWidth: contentWidth, contentHeight: contentHeight,
                                           viewportWidth: viewportWidth, viewportHeight: viewportHeight)
            tx = clamped.x
            ty = clamped.y
            return ZoomTransform(scale: scale, translationX: tx, translationY: ty)
        }
        return .identity
    }

    /// 布局/旋转变化：保持当前中心内容点（中心点在任意视口尺寸下都映射到中心 ⇔ 平移不变），
    /// 按新视口重新钳制。旧视口仅用于参数对称；旧视口非法时无法得知原中心 → 平移归零。
    public static func relayout(current: ZoomTransform,
                                oldViewport: (Double, Double),
                                newViewport: (Double, Double),
                                contentWidth: Double, contentHeight: Double,
                                minScale: Double = 1, maxScale: Double = 5) -> ZoomTransform {
        let scale = ZoomGeometry.sanitizedScale(current.scale, minScale: minScale, maxScale: maxScale)
        guard isUsable(contentWidth), isUsable(contentHeight),
              isUsable(newViewport.0), isUsable(newViewport.1) else {
            return ZoomTransform(scale: scale, translationX: 0, translationY: 0)
        }
        guard isUsable(oldViewport.0), isUsable(oldViewport.1) else {
            return ZoomTransform(scale: scale, translationX: 0, translationY: 0)
        }
        let clamped = clampTranslation(scale: scale, tx: current.translationX, ty: current.translationY,
                                       contentWidth: contentWidth, contentHeight: contentHeight,
                                       viewportWidth: newViewport.0, viewportHeight: newViewport.1)
        return ZoomTransform(scale: scale, translationX: clamped.x, translationY: clamped.y)
    }

    // MARK: - 私有

    /// 平移钳制：内容小于视口的轴 → 0；大于视口的轴 → 边缘不露白（|t| ≤ (显示尺寸-视口)/2）。
    private static func clampTranslation(scale: Double, tx: Double, ty: Double,
                                         contentWidth: Double, contentHeight: Double,
                                         viewportWidth: Double, viewportHeight: Double)
        -> (x: Double, y: Double) {
        let displayedW = contentWidth * scale
        let displayedH = contentHeight * scale
        let maxX = displayedW > viewportWidth ? (displayedW - viewportWidth) / 2 : 0
        let maxY = displayedH > viewportHeight ? (displayedH - viewportHeight) / 2 : 0
        guard maxX.isFinite, maxY.isFinite else { return (0, 0) }
        let cx = tx.isFinite ? min(max(tx, -maxX), maxX) : 0
        let cy = ty.isFinite ? min(max(ty, -maxY), maxY) : 0
        return (cx, cy)
    }

    private static func isUsable(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
