// MARK: - 职责说明：手势灵敏度档位常量（docs/03 §5.1 / docs/04 §3.4 舒适·标准·保守）。
// 灵敏度越高（阈值越小）越易触发；与设置项 gesture.sensitivity 一一对应。
// 设置联动已于 M7 落地：App 侧 SwipeGestureEngine.config(for:) 每次判定时实时读取 gesture.sensitivity。

import Foundation

public enum Sensitivity: String, CaseIterable {
    /// 舒适：轻滑即触发
    case comfortable
    /// 标准（默认）
    case standard
    /// 保守：需要明确的长距离/高速手势
    case conservative

    /// 距离阈值（pt）：80 / 120 / 180（docs/03 §5.1）
    public var distanceThreshold: Double {
        switch self {
        case .comfortable:  return 80
        case .standard:     return 120
        case .conservative: return 180
        }
    }

    /// 速度阈值（pt/s）：500 / 700 / 900（docs/03 §5.1）
    public var velocityThreshold: Double {
        switch self {
        case .comfortable:  return 500
        case .standard:     return 700
        case .conservative: return 900
        }
    }
}

/// 拖动框选阈值（docs/16 M12 R08：全部魔法数收口，App 侧只引用不散落）
public enum BoxSelectConfig {
    /// 长按起手时长（s）
    public static let minPressDuration: TimeInterval = 0.15
    /// 进入框选的位移阈值（pt）
    public static let moveThreshold: Double = 4
    /// 上/下边缘自动滚动触发区高度（pt）
    public static let autoScrollEdge: Double = 60
    /// 自动滚动步长（pt/帧）
    public static let autoScrollStep: Double = 10
    /// 二维相交命中阈值（相交面积 / cell 面积；原生相册手感：扫过约 1/5 格即命中）
    public static let hitThreshold: Double = 0.2
}
