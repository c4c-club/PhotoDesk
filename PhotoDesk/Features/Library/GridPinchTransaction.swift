// MARK: - 职责说明：网格捏合单飞事务（docs/28 §4.4.3，M16 T02）——
// LibraryViewController 的手势事件全部转投这里；锚点以 assetID 定格为跨布局身份
//（docs/28 §6：IndexPath 不作跨布局身份），提交决策全部来自 Core PinchColumnReducer。

import Foundation
import PhotoDeskCore

@MainActor
final class GridPinchTransaction {
    /// 捏合中心 assetID（began 定格，整个事务不变；捏合点无 cell 时为 nil → 完成后不滚动）
    private(set) var anchorAssetID: String?
    /// 事务是否活跃（began → end）
    private(set) var isActive = false
    private var reducer: PinchColumnReducer

    // MARK: 取证访问器（单测与诊断用）

    var startColumns: Int { reducer.startColumns }
    var startScale: Double { reducer.startScale }
    var currentColumns: Int { reducer.currentColumns }
    var pendingTarget: Int? { reducer.pendingTarget }
    var inFlightColumns: Int? { reducer.inFlightColumns }
    /// 是否仍有未收尾工作（在途过渡或挂起回弹）
    var isBusy: Bool { reducer.isBusy }

    init(config: PinchColumnConfig = PinchColumnConfig()) {
        reducer = PinchColumnReducer(config: config)
    }

    // MARK: 手势事件

    /// .began：定格锚点与起始列数
    func begin(anchorAssetID: String?, startColumns: Int, scale: Double) {
        self.anchorAssetID = anchorAssetID
        isActive = true
        reducer.begin(startColumns: startColumns, scale: scale)
    }

    /// .changed：产出 pending 目标；返回新目标（触觉/提示时机）或 nil
    @discardableResult
    func changed(scale: Double) -> Int? {
        guard isActive else { return nil }
        return reducer.changed(scale: scale)
    }

    /// .ended：回弹带判定；返回需立即提交的列数（在途时已挂链返回 nil）
    @discardableResult
    func ended(scale: Double) -> Int? {
        guard isActive else { return nil }
        return reducer.ended(scale: scale)
    }

    /// 单飞提交：无在途时取出 pending；返回列数或 nil（已在途 → 本次只挂链）
    @discardableResult
    func markInFlight() -> Int? {
        guard isActive else { return nil }
        return reducer.markInFlight()
    }

    /// 布局过渡完成：消费链式 pending；返回下一个提交目标或 nil
    @discardableResult
    func transitionFinished() -> Int? {
        guard isActive else { return nil }
        return reducer.transitionFinished()
    }

    /// 事务收尾（无在途、无挂起时调用）：清锚点
    func end() {
        guard !isBusy else { return }
        isActive = false
        anchorAssetID = nil
    }

    /// 中断：丢弃 pending（在途过渡仍由 completion 收尾）
    func cancel() {
        reducer.cancel()
    }
}
