// MARK: - 职责说明：位置记忆 v6 单一协调器（docs/28 §5.4–5.6 / M16 T03）——
// 唯一 save/restore 入口。保存由 Core PositionRestoreMachineV6 门禁：canSave 只在 settled
//（I1 恢复完成前零写盘）；滚动静止防抖 1.5s（§5.6），拖动结束/切后台立即保存 + flush；
// 恢复流程：loading → waitingForWindow（windowStart>0 → waitingForHead，head 批次逐批 delta
// 补偿）→ applying（一次）→ verifying（真实 attributes；nil = 失败，v5 默认通过是假 settled 根因）
// → settled；verify 失败重试一次，两次 → fallback（锚点 cell 顶部 / section / ratio，绝不假 settled）。

import UIKit
import PhotoDeskCore

/// 保存用几何快照（主线程抓取，纯值）。
struct LibraryPositionSnapshot {
    let queryKey: String
    let anchorAssetID: String
    let anchorVisualY: Double
    let anchorSectionID: String
    let anchorItemIndex: Int
    let contentOffsetY: Double
    let contentHeight: Double
    let viewportHeight: Double
    /// v6 取证字段：全量索引位置（未知 nil）/ 保存时列数 / adjustedContentInset.top
    var anchorGlobalIndex: Int? = nil
    var gridColumns: Int = 3
    var contentInsetTop: Double = 0
}

/// 恢复时 VC 提供的实时几何与执行能力（v6：窗口/代际注入 + 真实 attributes 闭包）。
struct LibraryPositionRestoreContext {
    let bounds: CGSize
    let isIndexComplete: Bool
    let contentHeight: Double
    let viewportHeight: Double
    let adjustedTop: Double
    let bottomInset: Double
    /// 锚点是否在当前数据索引里（查 currentItemsBySection，与布局物化无关）
    let anchorInData: (String) -> Bool
    /// 锚点 cell 当前布局 minY（content 坐标；未物化/未布局返回 nil——verify 视为失败）
    let anchorMinY: (String) -> Double?
    /// sectionID + itemIndex 的 minY（fallback 用）
    let sectionMinY: (String, Int) -> Double?
    /// scrollToItem(at: .top) + layoutIfNeeded；返回是否成功（数据在但布局异常 → false 保持等待）
    let scrollToAnchorTop: (String) -> Bool
    /// setContentOffset(y:) + layoutIfNeeded
    let applyOffset: (Double) -> Void
    let actualOffsetY: () -> Double
    /// 强制当前布局收敛（viewDidLayoutSubviews 之外的入口需要）
    let layoutNow: () -> Void
    /// 首批窗口起始 offset（v6 waitingForHead 判定：> 0 必等 head 回填）
    var firstBatchWindowStart: Int = 0
    /// head 回填代际（连续两轮不变 + 索引完成 → applying）
    var headInsertGeneration: Int = 0
    /// 当前 queryKey 实时读取（筛选/年份切换即变；nil = 调用方不参与该守卫，测试用）
    var currentQueryKey: (() -> String)? = nil
}

@MainActor
final class LibraryPositionCoordinator {
    private let store: LibraryPositionStore
    private var machine = PositionRestoreMachineV6()
    private var pendingAnchor: LibraryPositionV6?
    /// 记录无效（isSane == false，§5.3）→ 跳过 asset 精确路径，直接 section/ratio
    private var pendingAnchorIsInsane = false
    private var pendingSave: DispatchWorkItem?
    private var lastRestoredQueryKey: String?
    private var targetOffsetY: Double = 0

    /// 最近一次恢复采用的策略（asset / section / ratio / none），供调试汇总。
    private(set) var lastStrategy: PositionRestoreStrategy = .none
    /// 最近一次恢复/等待的诊断串，供 UI 取证。
    private(set) var lastRestoreDiagnostics = ""
    /// DEBUG 取证：恢复期间被 I1 门禁拒绝的保存请求数（写盘次数恒 0）。
    private(set) var rejectedSaveRequests = 0
    /// 阶段变化回调（VC 用于遮罩开关；不参与几何写入）。
    var onPhaseChange: ((PositionRestorePhaseV6) -> Void)?

    init(store: LibraryPositionStore) {
        self.store = store
    }

    var phase: PositionRestorePhaseV6 { machine.phase }
    var isRestoreInFlight: Bool { machine.isInFlight }
    var restoreAttempts: Int { machine.attempts }

    // MARK: - 保存（I1/I2：canSave 只在 settled；§5.6 触发矩阵）

    /// 滚动静止防抖保存（1.5s，只在 tracking 时由 VC 调用）。恢复未完成 / 快照缺失 → 丢弃。
    func scheduleSave(reason: String, snapshot: LibraryPositionSnapshot?, debounce: TimeInterval = 1.5) {
        guard store.isEnabled, let snapshot else { return }
        guard machine.canSave else {
            rejectedSaveRequests += 1
            return
        }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.commitSave(reason: reason, snapshot: snapshot)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, debounce), execute: work)
    }

    /// 立即保存（拖动结束 / 切后台 / 退出 / 月跳 / 回顶）并 flush：
    /// 文件原子写走串行队列，flush 等待队列排空，保证进程被杀的最后一笔一定落盘。
    func saveNow(reason: String, snapshot: LibraryPositionSnapshot?) {
        guard store.isEnabled, let snapshot else { return }
        guard machine.canSave else {
            rejectedSaveRequests += 1
            return
        }
        pendingSave?.cancel()
        pendingSave = nil
        commitSave(reason: reason, snapshot: snapshot)
        store.flush()
    }

    func cancelPendingSaves() {
        pendingSave?.cancel()
        pendingSave = nil
    }

    private func commitSave(reason: String, snapshot: LibraryPositionSnapshot) {
        guard store.isEnabled, machine.canSave else { return }
        let scrollable = max(1, snapshot.contentHeight - snapshot.viewportHeight)
        // §5.3：visualY 超出 [0, viewport) 视为无效——保存侧防御性钳制，绝不写坏数据
        let visualY = min(max(snapshot.anchorVisualY, 0), max(0, snapshot.viewportHeight - 1))
        let position = LibraryPositionV6(queryKey: snapshot.queryKey,
                                         anchorAssetID: snapshot.anchorAssetID,
                                         anchorGlobalIndex: snapshot.anchorGlobalIndex,
                                         anchorSectionID: snapshot.anchorSectionID,
                                         anchorSectionItemIndex: snapshot.anchorItemIndex,
                                         anchorVisualY: visualY,
                                         anchorContentOffsetY: snapshot.contentOffsetY,
                                         gridColumns: snapshot.gridColumns,
                                         contentInsetTop: snapshot.contentInsetTop,
                                         contentHeight: snapshot.contentHeight,
                                         viewportHeight: snapshot.viewportHeight,
                                         savedAt: Date())
        store.save(position, queryKey: snapshot.queryKey)
        let ratio = min(1, max(0, snapshot.contentOffsetY / Double(scrollable)))
        ViewerTrace.log("position.save.v6 \(reason) anchor=\(position.anchorAssetID.prefix(8)) " +
                        "idx=\(position.anchorGlobalIndex.map(String.init) ?? "-") " +
                        "visualY=\(Int(position.anchorVisualY)) off=\(Int(position.anchorContentOffsetY)) " +
                        "ratio=\(String(format: "%.2f", ratio))")
    }

    // MARK: - 恢复（I2：同一 queryKey 一次启动只恢复一次）

    /// 只 load 一次锚点；queryKey 变化才重置状态机。无锚点直接 settled（不遮罩、可保存）。
    func beginRestore(queryKey: String) {
        guard queryKey != lastRestoredQueryKey else { return }
        lastRestoredQueryKey = queryKey
        cancelPendingSaves()
        rejectedSaveRequests = 0
        let loaded = store.isEnabled ? store.load(queryKey: queryKey) : nil
        pendingAnchor = loaded
        pendingAnchorIsInsane = loaded.map { !$0.isSane } ?? false
        if pendingAnchorIsInsane {
            ViewerTrace.log("position.restore.v6 insane-record query=\(queryKey.prefix(8)) → fallback-only")
        }
        let hasAnchor = pendingAnchor != nil
        let phase = machine.begin(hasAnchor: hasAnchor)
        if pendingAnchorIsInsane {
            machine.forceFallback()
        }
        if !hasAnchor {
            ViewerTrace.log("position.restore.v6 skip query=\(queryKey.prefix(8)) reason=no-anchor")
        } else {
            ViewerTrace.log("position.restore.v6 begin query=\(queryKey.prefix(8)) " +
                            "anchor=\(pendingAnchor?.anchorAssetID.prefix(8) ?? "-") " +
                            "idx=\(pendingAnchor?.anchorGlobalIndex.map(String.init) ?? "-")")
        }
        onPhaseChange?(machine.phase)
    }

    /// 用户主动跳转/接管时取消恢复：清除锚点、收起遮罩，后续滚动可正常保存。
    func cancelRestore(reason: String) {
        guard machine.isInFlight else { return }
        pendingAnchor = nil
        machine.cancel()
        ViewerTrace.log("position.restore.v6 cancel reason=\(reason)")
        onPhaseChange?(machine.phase)
    }

    /// applySnapshot completion / viewDidLayoutSubviews / viewDidAppear 都调用；可重入。
    func attemptRestore(context: LibraryPositionRestoreContext) {
        guard machine.isInFlight, let anchor = pendingAnchor else { return }
        switch machine.phase {
        case .loading, .waitingForWindow:
            let phase = machine.windowResolved(windowStart: context.firstBatchWindowStart,
                                               boundsReady: context.bounds.width > 0
                                                            && context.bounds.height > 0
                                                            && context.contentHeight > 0)
            onPhaseChange?(phase)
            attemptReadyPath(context: context, anchor: anchor)
        case .waitingForHead, .applying:
            attemptReadyPath(context: context, anchor: anchor)
        case .verifying:
            verify(context: context, anchor: anchor)
        case .fallback:
            applyFallback(context: context, anchor: anchor)
        case .idle, .settled:
            break
        }
    }

    /// applying/waitingForHead 的统一推进：先查锚点在数据（缺 → 等/降级），
    /// waitingForHead 里推代际；只有真正进入 applying 才允许写几何。
    private func attemptReadyPath(context: LibraryPositionRestoreContext, anchor: LibraryPositionV6) {
        if !context.anchorInData(anchor.anchorAssetID) {
            // 锚点暂不在数据：索引未完成保持等待（I4 无硬超时）；完成 → fallback
            let phase = machine.anchorMissing(indexComplete: context.isIndexComplete)
            onPhaseChange?(phase)
            if phase == .fallback {
                applyFallback(context: context, anchor: anchor)
            }
            return
        }
        if machine.phase == .waitingForHead {
            let phase = machine.headProgress(generation: context.headInsertGeneration,
                                             indexComplete: context.isIndexComplete)
            onPhaseChange?(phase)
            guard machine.phase == .applying else { return }
        }
        guard machine.phase == .applying else { return }   // waitingForWindow / 仍在等待 → 不写几何
        applyAnchor(context: context, anchor: anchor)
    }

    /// §5.5 步骤 5：scrollToItem(.top) → 真实 attributes minY → target = minY − visualY → 钳制 → 写入。
    private func applyAnchor(context: LibraryPositionRestoreContext, anchor: LibraryPositionV6) {
        machine.apply()   // v6：入口只允许一次（重复调用直接返回）
        guard context.scrollToAnchorTop(anchor.anchorAssetID) else {
            // 数据在但布局异常：等下一轮布局 pass
            return
        }
        context.layoutNow()
        guard let minY = context.anchorMinY(anchor.anchorAssetID) else {
            // 真实 attributes 缺失：索引完成 → fallback；未完成 → 等待
            if context.isIndexComplete {
                let phase = machine.anchorMissing(indexComplete: true)
                onPhaseChange?(phase)
                applyFallback(context: context, anchor: anchor)
            }
            return
        }
        let target = PositionAnchorPolicy.targetOffsetY(cellMinY: minY, anchorVisualY: anchor.anchorVisualY)
        targetOffsetY = PositionAnchorPolicy.clampedTargetOffsetY(target,
                                                                  contentHeight: context.contentHeight,
                                                                  viewportHeight: context.viewportHeight,
                                                                  adjustedTop: context.adjustedTop,
                                                                  bottomInset: context.bottomInset)
        lastStrategy = .asset
        lastRestoreDiagnostics = "asset minY=\(Int(minY)) target=\(Int(target)) clamped=\(Int(targetOffsetY)) " +
            "savedCH=\(Int(anchor.contentHeight)) curCH=\(Int(context.contentHeight))"
        machine.applied()
        context.applyOffset(targetOffsetY)
        onPhaseChange?(machine.phase)
        DispatchQueue.main.async { [weak self] in
            self?.attemptRestore(context: context)
        }
    }

    /// head 批次 contentHeight delta（§5.5 步骤 4）：waitingForHead 期间由 VC 在 apply completion 调用，
    /// 返回需要平移的 dy（0 = 不调整）；offset 写入由 VC 执行。
    func headBatchDelta(contentHeightBefore: Double,
                        contentHeightAfter: Double,
                        currentOffsetY: Double,
                        maxOffsetY: Double) -> Double {
        guard machine.phase == .waitingForHead else { return 0 }
        let adjusted = HeadInsertCompensationPolicy.adjustedOffsetY(
            beforeY: currentOffsetY,
            contentHeightBefore: contentHeightBefore,
            contentHeightAfter: contentHeightAfter,
            insertedAboveAnchor: true,   // head 批次全部位于锚点窗口之前（上方）
            maxOffsetY: maxOffsetY)
        return adjusted - currentOffsetY
    }

    /// §5.5 步骤 6 校验：真实 attributes 的视觉 y 误差 ≤ 2pt 且 offset ≤ 2pt；
    /// attributes 缺失 = 失败（v6 硬化：不得默认通过）。
    private func verify(context: LibraryPositionRestoreContext, anchor: LibraryPositionV6) {
        context.layoutNow()
        let actual = context.actualOffsetY()
        let offsetOK = abs(actual - targetOffsetY) <= 2.0
        var visualOK = false
        var actualVisualYText = "nil"
        if let minY = context.anchorMinY(anchor.anchorAssetID) {
            let actualVisualY = minY - actual
            actualVisualYText = String(Int(actualVisualY))
            visualOK = abs(actualVisualY - anchor.anchorVisualY) <= 2.0
        }
        let ok = offsetOK && visualOK
        let phase = machine.verified(ok: ok)
        onPhaseChange?(phase)
        lastRestoreDiagnostics += " verify actual=\(Int(actual)) target=\(Int(targetOffsetY)) " +
            "vY=\(actualVisualYText) ok=\(ok) att=\(machine.attempts)"
        switch phase {
        case .settled:
            finish(reason: machine.attempts > 0 ? "verify-failed" : lastStrategy.rawValue)
        case .applying:
            // 重试：用当前真实布局重算 target（不重新 scrollToItem）
            if let minY = context.anchorMinY(anchor.anchorAssetID) {
                let target = PositionAnchorPolicy.targetOffsetY(cellMinY: minY, anchorVisualY: anchor.anchorVisualY)
                targetOffsetY = PositionAnchorPolicy.clampedTargetOffsetY(target,
                                                                          contentHeight: context.contentHeight,
                                                                          viewportHeight: context.viewportHeight,
                                                                          adjustedTop: context.adjustedTop,
                                                                          bottomInset: context.bottomInset)
            }
            machine.applied()
            context.applyOffset(targetOffsetY)
            onPhaseChange?(machine.phase)
            DispatchQueue.main.async { [weak self] in
                self?.attemptRestore(context: context)
            }
        case .fallback:
            // v6：两次 verify 仍失败 → 锚点 cell 顶部兜底（不假 settled）
            applyFallback(context: context, anchor: anchor)
        default:
            break
        }
    }

    /// v6 fallback（§5.5 步骤 6 + §5.3）：锚点在数据 → cell 顶部兜底（同一张照片仍可见）；
    /// 不在 → sectionID+index → ratio 逐级退化。全部直接收敛 settled，不再进 verify。
    private func applyFallback(context: LibraryPositionRestoreContext, anchor: LibraryPositionV6) {
        if context.anchorInData(anchor.anchorAssetID),
           context.scrollToAnchorTop(anchor.anchorAssetID) {
            context.layoutNow()
            if let minY = context.anchorMinY(anchor.anchorAssetID) {
                let offset = PositionAnchorPolicy.clampedTargetOffsetY(minY,
                                                                       contentHeight: context.contentHeight,
                                                                       viewportHeight: context.viewportHeight,
                                                                       adjustedTop: context.adjustedTop,
                                                                       bottomInset: context.bottomInset)
                lastStrategy = .asset
                lastRestoreDiagnostics += " fallback anchorTop=\(Int(offset))"
                context.applyOffset(offset)
            }
            machine.settleFallback()
            finish(reason: "fallback-anchor-top")
            onPhaseChange?(machine.phase)
            return
        }
        let sectionMinY = context.sectionMinY(anchor.anchorSectionID, anchor.anchorSectionItemIndex)
        let resolved = PositionAnchorPolicy.resolve(anchor: anchor.toCoreAnchor,
                                                    assetCellMinY: nil,
                                                    sectionCellMinY: sectionMinY,
                                                    contentHeight: context.contentHeight,
                                                    viewportHeight: context.viewportHeight,
                                                    adjustedTop: context.adjustedTop,
                                                    bottomInset: context.bottomInset)
        guard resolved.strategy != .none else {
            machine.settleFallback()
            finish(reason: "no-anchor")
            onPhaseChange?(machine.phase)
            return
        }
        lastStrategy = resolved.strategy
        lastRestoreDiagnostics += " fallback \(resolved.strategy.rawValue) offset=\(Int(resolved.offsetY))"
        context.applyOffset(resolved.offsetY)
        machine.settleFallback()
        finish(reason: "fallback-\(resolved.strategy.rawValue)")
        onPhaseChange?(machine.phase)
    }

    private func finish(reason: String) {
        pendingAnchor = nil
        ViewerTrace.log("position.restore.v6 \(machine.phase.rawValue) reason=\(reason) " +
                        "strategy=\(lastStrategy.rawValue) rej=\(rejectedSaveRequests)")
    }
}