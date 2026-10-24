// MARK: - 职责说明：上下滑手势判定（方向 / 阈值 / 速度）——纯函数、零 Apple 依赖（docs/03 §5.1，红线 2）。
// App 侧经 SwipeResolverAdapter 把 CGSize/CGVelocity 适配为 Double 后调用本模块（docs/03 §5.10），不重复实现。
// TODO(P1): 实现判定逻辑并补全单测（方向 1.5× 边界、距离阈值、速度触发、progress 计算）。

/// 滑动方向（up = 负 dy，down = 正 dy）
public enum SwipeDirection {
    case up
    case down
}

/// 手势判定参数。灵敏度档位见 `Sensitivity`（docs/03 §5.1：距离 80/120/180、速度 500/700/900 pt/s）
public struct SwipeConfig {
    /// 距离阈值（pt）：拖拽绝对距离达标即锁定
    public let distanceThreshold: Double
    /// 速度阈值（pt/s）：快速滑动触发
    public let velocityThreshold: Double
    /// 速度触发所需的最小距离（pt）
    public let minDistanceForVelocity: Double
    /// 破坏性动作是否需要二次确认（与设置项 confirmDestructive 联动）
    public let confirmRequired: Bool

    public init(distanceThreshold: Double,
                velocityThreshold: Double,
                minDistanceForVelocity: Double,
                confirmRequired: Bool) {
        self.distanceThreshold = distanceThreshold
        self.velocityThreshold = velocityThreshold
        self.minDistanceForVelocity = minDistanceForVelocity
        self.confirmRequired = confirmRequired
    }
}

/// 纯函数判定器：图片不随手指位移，只驱动 ActionOverlay（docs/03 §5.1）
public struct SwipeResolver {
    public let config: SwipeConfig

    public init(config: SwipeConfig) {
        self.config = config
    }

    /// 方向判定：|dy| > 1.5 × |dx| 才算垂直手势，否则返回 nil（让位给横向翻页）
    public func direction(dx: Double, dy: Double) -> SwipeDirection? {
        // TODO(P1): 按上方注释实现
        return nil
    }

    /// 拖拽进度 0...1（以距离阈值归一），驱动浮层透明度/缩放/位移
    public func progress(dx: Double, dy: Double) -> Double {
        // TODO(P1): min(|dy| / distanceThreshold, 1)
        return 0
    }

    /// 是否锁定：距离达标，或速度达标且距离不低于 minDistanceForVelocity
    public func isLocked(dx: Double, dy: Double, vx: Double, vy: Double) -> Bool {
        // TODO(P1): 按上方注释实现
        return false
    }
}
