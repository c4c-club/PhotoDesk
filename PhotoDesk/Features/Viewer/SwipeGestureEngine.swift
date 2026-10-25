// MARK: - 职责说明：上下滑手势状态机（docs/03 §5.1 / docs/05 M2 任务 2.4）★核心——
// 把 UIPanGestureRecognizer 的 translation/velocity 适配为 Double，喂给 PhotoDeskCore.SwipeResolver 纯函数
// （红线 2：判定逻辑全部在核心包，本类只做 UIKit 类型适配与单次手势内的状态保持）。
// 状态机：idle → undetermined →（|dy|>1.5|dx|）vertical(方向锁，一次判定向，不再改判)
//        undetermined →（|dx| 占优）horizontal（交还分页器）→ 松手/取消回 idle。
// 锁定（isLocked）与方向（direction）是两个独立概念：先定方向，距离/速度达标才锁。

import CoreGraphics
import Foundation
import PhotoDeskCore

final class SwipeGestureEngine {
    /// 单次手势的阶段
    enum Phase: Equatable {
        case idle
        case undetermined
        case vertical(SwipeDirection)   // 方向已锁
        case horizontal                 // 水平：交还分页器
    }

    /// update 的输出（驱动浮层与触觉）
    struct Output: Equatable {
        let direction: SwipeDirection?   // 非 nil = 已锁定垂直方向
        let progress: Double             // 0...1
        let locked: Bool                 // 阈值/速度达标
        /// locked 由 false → true 的边沿（触发触觉）
        let lockEdge: Bool
        let isHorizontal: Bool

        static let neutral = Output(direction: nil, progress: 0, locked: false, lockEdge: false, isHorizontal: false)
    }

    /// 每次手势新建或 begin 重置；判定参数来自设置（灵敏度 + 确认开关）
    private let resolver: SwipeResolver
    private(set) var phase: Phase = .idle
    private var lastLocked = false

    init(config: SwipeConfig) {
        resolver = SwipeResolver(config: config)
    }

    /// 由设置构造判定配置（灵敏度档位 → 阈值；最小速度距离固定 40，docs/03 §5.1）
    static func config(for sensitivity: Sensitivity, confirmDestructive: Bool) -> SwipeConfig {
        SwipeConfig(distanceThreshold: sensitivity.distanceThreshold,
                    velocityThreshold: sensitivity.velocityThreshold,
                    minDistanceForVelocity: 40,
                    confirmRequired: confirmDestructive)
    }

    func begin() {
        phase = .undetermined
        lastLocked = false
    }

    func update(translation: CGSize, velocity: CGSize) -> Output {
        let dx = Double(translation.width)
        let dy = Double(translation.height)
        let vx = Double(velocity.width)
        let vy = Double(velocity.height)

        if case .vertical = phase {
            // 方向已锁，不再改判
        } else if case .horizontal = phase {
            // 保持横向
        } else if let direction = resolver.direction(dx: dx, dy: dy) {
            phase = .vertical(direction)
        } else if abs(dx) > abs(dy), abs(dx) > 8 {
            phase = .horizontal
        }

        switch phase {
        case .vertical(let direction):
            let locked = resolver.isLocked(dx: dx, dy: dy, vx: vx, vy: vy)
            let lockEdge = locked && !lastLocked
            lastLocked = locked
            return Output(direction: direction,
                          progress: resolver.progress(dx: dx, dy: dy),
                          locked: locked,
                          lockEdge: lockEdge,
                          isHorizontal: false)
        case .horizontal:
            return Output(direction: nil, progress: 0, locked: false, lockEdge: false, isHorizontal: true)
        case .undetermined, .idle:
            return .neutral
        }
    }

    /// 松手：锁定才返回应执行的方向
    func finish() -> SwipeDirection? {
        defer { reset() }
        if case .vertical(let direction) = phase, lastLocked {
            return direction
        }
        return nil
    }

    func cancel() {
        reset()
    }

    private func reset() {
        phase = .idle
        lastLocked = false
    }
}
