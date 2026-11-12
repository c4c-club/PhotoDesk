// MARK: - 职责说明：网格捏合列数决策（docs/28 §4.4.1/§4.4.3，M16 T02）——
// 纯 Int/Double 单飞状态机：.changed 只产出带滞回的 pendingTarget，绝不直接触发布局切换；
// 提交走 markInFlight（同一时刻最多一个在途过渡），过渡完成后 transitionFinished 消费链式 pending；
// 松手回弹带与中断清理齐备，不留半过渡状态。零 Apple 依赖（红线 2）：
// 只 import Foundation，阈值与列数上下限全部来自可注入配置。

import Foundation

/// 网格捏合配置（docs/09 D14 默认 2...5 列；阈值可注入便于测试）
public struct PinchColumnConfig: Equatable, Sendable {
    /// 列数下限
    public let minColumns: Int
    /// 列数上限
    public let maxColumns: Int
    /// 滞回余量（列宽单位）：目标列切换必须越过两列中点再多走该余量，吸收中点抖动
    public let hysteresis: Double
    /// 松手回弹带：|scale - 1| 低于该值时回起始列数（docs/09 D14）
    public let snapbackScaleBand: Double

    public init(minColumns: Int = 2,
                maxColumns: Int = 5,
                hysteresis: Double = 0.06,
                snapbackScaleBand: Double = 0.08) {
        self.minColumns = minColumns
        self.maxColumns = maxColumns
        self.hysteresis = hysteresis
        self.snapbackScaleBand = snapbackScaleBand
    }
}

/// 网格捏合列数 reducer：输入捏合刻度，输出单飞提交决策（docs/28 §4.4.1）。
public struct PinchColumnReducer {
    public let config: PinchColumnConfig
    /// 本次手势起始列数（回弹目标）
    public private(set) var startColumns: Int
    /// 当前已提交列数（markInFlight / transitionFinished 推进）
    public private(set) var currentColumns: Int
    /// 起始刻度（docs/28 §4.4.3：began 记录；非有限值消毒为 1）
    public private(set) var startScale: Double
    /// 待提交目标（单飞队列，最多 1 个；最新者胜）
    public private(set) var pendingTarget: Int?
    /// 在途布局过渡的列数（nil = 无在途）
    public private(set) var inFlightColumns: Int?

    /// 是否允许立即提交（无在途且有 pending）
    public var shouldCommit: Bool { pendingTarget != nil && inFlightColumns == nil }
    /// 事务是否仍有未收尾工作（挂起或在途）
    public var isBusy: Bool { pendingTarget != nil || inFlightColumns != nil }

    public init(config: PinchColumnConfig = PinchColumnConfig(),
                startColumns: Int = 3,
                scale: Double = 1) {
        self.config = config
        let clamped = Self.clamp(startColumns, config)
        self.startColumns = clamped
        self.currentColumns = clamped
        self.startScale = scale.isFinite ? scale : 1
        self.pendingTarget = nil
        self.inFlightColumns = nil
    }

    /// .began：重置事务状态
    public mutating func begin(startColumns: Int, scale: Double) {
        let clamped = Self.clamp(startColumns, config)
        self.startColumns = clamped
        currentColumns = clamped
        startScale = scale.isFinite ? scale : 1
        pendingTarget = nil
        inFlightColumns = nil
    }

    /// .changed：计算带滞回的候选列数；仅当越过中点 + 余量才写入 pending，返回新目标或 nil。
    /// 不提交、不触发布局（docs/28 §4.4.3.1：changed 只更新事务状态）。
    @discardableResult
    public mutating func changed(scale: Double) -> Int? {
        guard scale.isFinite, scale > 0 else { return nil }
        let raw = Double(startColumns) / scale
        let candidate = Self.clamp(Int(raw.rounded()), config)
        let baseline = pendingTarget ?? currentColumns
        guard candidate != baseline else { return nil }
        // 滞回：raw 必须越过 baseline→candidate 中点并向 candidate 偏移 hysteresis 余量
        let midpoint = (Double(baseline) + Double(candidate)) / 2
        let crossed = candidate < baseline
            ? raw <= midpoint - config.hysteresis
            : raw >= midpoint + config.hysteresis
        guard crossed else { return nil }
        pendingTarget = candidate
        return candidate
    }

    /// 单飞提交：取出 pending 挂上在途并推进 currentColumns；
    /// 无 pending 或已在途时返回 nil（调用方不得触发第二次布局切换）。
    @discardableResult
    public mutating func markInFlight() -> Int? {
        guard shouldCommit, let target = pendingTarget else { return nil }
        pendingTarget = nil
        inFlightColumns = target
        currentColumns = target
        return target
    }

    /// 布局过渡完成：清在途；若有链式 pending 立即接续为新的在途并返回其列数
    @discardableResult
    public mutating func transitionFinished() -> Int? {
        inFlightColumns = nil
        guard shouldCommit else { return nil }
        return markInFlight()
    }

    /// .ended：回弹带判定（|scale-1| < band 且列数已变化 → 回起始列数）。
    /// 在途时只挂链（最新者胜），由 transitionFinished 接续；否则返回需立即提交的列数。
    @discardableResult
    public mutating func ended(scale: Double) -> Int? {
        guard scale.isFinite else { return nil }
        guard abs(scale - 1) < config.snapbackScaleBand, currentColumns != startColumns else { return nil }
        pendingTarget = startColumns
        if shouldCommit {
            return markInFlight()
        }
        return nil
    }

    /// 中断：丢弃 pending，保持当前列数（在途过渡仍由 completion 收尾）
    public mutating func cancel() {
        pendingTarget = nil
    }

    private static func clamp(_ value: Int, _ config: PinchColumnConfig) -> Int {
        min(max(value, config.minColumns), config.maxColumns)
    }
}
