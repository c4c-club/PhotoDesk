// MARK: - 职责说明：位置记忆 v5 单一协调器（docs/25 §5.4–5.7 / M15 P0-2）——
// 唯一 save/restore 入口。保存由 Core PositionRestoreMachineV5 门禁：canSave 只在 settled
// （I1 恢复完成前零写盘）；滚动防抖 0.5s（只 tracking），拖动结束/切后台立即保存 + flush。
// 恢复算法（§5.5）：indexPath 查数据 → scrollToItem(.top) + layoutIfNeeded → target = minY - anchorVisualY
// → 钳制 → setContentOffset → verify ±0.5pt → 失败只调 offset 重试一次 → 两次仍失败 settled（不阻塞 UI）。
// 锚点不在数据且索引未完成 → 保持 restoring 等待（I4：无硬超时）；索引完成仍缺 → section/ratio fallback。

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
}

/// 恢复时 VC 提供的实时几何与执行能力（v5：数据存在性 / scrollToItem / 布局刷新分开注入）。
struct LibraryPositionRestoreContext {
    let bounds: CGSize
    let isIndexComplete: Bool
    let contentHeight: Double
    let viewportHeight: Double
    let adjustedTop: Double
    let bottomInset: Double
    /// 锚点是否在当前数据索引里（查 currentItemsBySection，与布局物化无关）
    let anchorInData: (String) -> Bool
    /// 锚点 cell 当前布局 minY（content 坐标；未物化/未布局返回 nil）
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
}

@MainActor
final class LibraryPositionCoordinator {
    private let store: LibraryPositionStore
    private var machine = PositionRestoreMachineV5()
    private var pendingAnchor: LibraryPosition?
    private var pendingSave: DispatchWorkItem?
    private var lastRestoredQueryKey: String?
    private var targetOffsetY: Double = 0

    /// 最近一次恢复采用的策略（asset / section / ratio / none），供调试汇总。
    private(set) var lastStrategy: PositionRestoreStrategy = .none
    /// 阶段变化回调（VC 用于遮罩开关；不参与几何写入）。
    var onPhaseChange: ((PositionRestorePhaseV5) -> Void)?

    init(store: LibraryPositionStore) {
        self.store = store
    }

    var phase: PositionRestorePhaseV5 { machine.phase }
    var isRestoreInFlight: Bool { machine.isInFlight }
    var restoreAttempts: Int { machine.attempts }

    // MARK: - 保存（I1/I2：canSave 只在 settled）

    /// 滚动防抖保存（0.5s，只在 tracking 时由 VC 调用）。恢复未完成 / 快照缺失 → 丢弃。
    func scheduleSave(reason: String, snapshot: LibraryPositionSnapshot?, debounce: TimeInterval = 0.5) {
        guard store.isEnabled, machine.canSave, let snapshot else { return }
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
        guard store.isEnabled, machine.canSave, let snapshot else { return }
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
        let position = LibraryPosition(anchorAssetID: snapshot.anchorAssetID,
                                       anchorVisualY: snapshot.anchorVisualY,
                                       anchorContentOffsetY: snapshot.contentOffsetY,
                                       assetID: snapshot.anchorAssetID,
                                       sectionID: snapshot.anchorSectionID,
                                       itemIndexInSection: snapshot.anchorItemIndex,
                                       offsetRatio: min(1, max(0, snapshot.contentOffsetY / scrollable)),
                                       contentHeight: snapshot.contentHeight,
                                       viewportHeight: snapshot.viewportHeight,
                                       savedAt: Date(),
                                       queryKey: snapshot.queryKey)
        store.save(position, queryKey: snapshot.queryKey)
        ViewerTrace.log("position.save.v5 \(reason) anchor=\(position.anchorAssetID.prefix(8)) " +
                        "visualY=\(Int(position.anchorVisualY)) off=\(Int(position.anchorContentOffsetY))")
    }

    // MARK: - 恢复（I2：同一 queryKey 一次启动只恢复一次）

    /// 只 load 一次锚点；queryKey 变化才重置状态机。无锚点直接 settled（不遮罩、可保存）。
    func beginRestore(queryKey: String) {
        guard queryKey != lastRestoredQueryKey else { return }
        lastRestoredQueryKey = queryKey
        cancelPendingSaves()
        pendingAnchor = store.isEnabled ? store.load(queryKey: queryKey) : nil
        let phase = machine.begin(hasAnchor: pendingAnchor != nil)
        if pendingAnchor == nil {
            ViewerTrace.log("position.restore.v5 skip query=\(queryKey.prefix(8)) reason=no-anchor")
        } else {
            ViewerTrace.log("position.restore.v5 begin query=\(queryKey.prefix(8)) " +
                            "anchor=\(pendingAnchor?.anchorAssetID.prefix(8) ?? "-")")
        }
        onPhaseChange?(phase)
    }

    /// 用户主动跳转/接管时取消恢复：清除锚点、收起遮罩，后续滚动可正常保存。
    func cancelRestore(reason: String) {
        guard machine.isInFlight else { return }
        pendingAnchor = nil
        machine.cancel()
        ViewerTrace.log("position.restore.v5 cancel reason=\(reason)")
        onPhaseChange?(machine.phase)
    }

    /// applySnapshot completion / viewDidLayoutSubviews / viewDidAppear 都调用；可重入。
    func attemptRestore(context: LibraryPositionRestoreContext) {
        guard machine.isInFlight, let anchor = pendingAnchor else { return }
        if machine.phase == .verifying {
            verify(context: context, anchor: anchor)
            return
        }
        let assetInData = context.anchorInData(anchor.anchorAssetID)
        let phase = machine.dataAvailable(anchorPresent: assetInData,
                                          indexComplete: context.isIndexComplete,
                                          boundsReady: context.bounds.width > 0 && context.bounds.height > 0)
        onPhaseChange?(phase)
        switch phase {
        case .applying:
            applyAnchor(context: context, anchor: anchor)
        case .fallback:
            applyFallback(context: context, anchor: anchor)
        default:
            return   // restoring：等待索引/布局，不失败（I4）
        }
    }

    /// §5.5 主路径：scrollToItem(.top)（UICollectionView 自己算目标 offset）→ 一次像素修正。
    private func applyAnchor(context: LibraryPositionRestoreContext, anchor: LibraryPosition) {
        guard context.scrollToAnchorTop(anchor.anchorAssetID) else { return }   // 保持 restoring
        context.layoutNow()
        guard let minY = context.anchorMinY(anchor.anchorAssetID) else { return }
        let target = PositionAnchorPolicy.targetOffsetY(cellMinY: minY, anchorVisualY: anchor.anchorVisualY)
        targetOffsetY = PositionAnchorPolicy.clampedTargetOffsetY(target,
                                                                  contentHeight: context.contentHeight,
                                                                  viewportHeight: context.viewportHeight,
                                                                  adjustedTop: context.adjustedTop,
                                                                  bottomInset: context.bottomInset)
        lastStrategy = .asset
        machine.applied()
        context.applyOffset(targetOffsetY)
        onPhaseChange?(machine.phase)
        DispatchQueue.main.async { [weak self] in
            self?.attemptRestore(context: context)
        }
    }

    /// fallback：锚点不在数据且索引已完成 → sectionID+itemIndex → ratio（resolve 逐级退化）。
    private func applyFallback(context: LibraryPositionRestoreContext, anchor: LibraryPosition) {
        let sectionMinY = context.sectionMinY(anchor.sectionID, anchor.itemIndexInSection)
        let resolved = PositionAnchorPolicy.resolve(anchor: anchor.toCoreAnchor,
                                                    assetCellMinY: nil,
                                                    sectionCellMinY: sectionMinY,
                                                    contentHeight: context.contentHeight,
                                                    viewportHeight: context.viewportHeight,
                                                    adjustedTop: context.adjustedTop,
                                                    bottomInset: context.bottomInset)
        lastStrategy = resolved.strategy
        guard resolved.strategy != .none else {
            machine.settleFallback()
            finish(reason: "no-anchor")
            return
        }
        targetOffsetY = resolved.offsetY
        machine.applied()
        context.applyOffset(resolved.offsetY)
        onPhaseChange?(machine.phase)
        DispatchQueue.main.async { [weak self] in
            self?.attemptRestore(context: context)
        }
    }

    /// §5.5 校验：offset 误差 ≤ 0.5pt 且锚点视觉 y 误差 ≤ 0.5pt；失败只调 offset 重试一次。
    private func verify(context: LibraryPositionRestoreContext, anchor: LibraryPosition) {
        context.layoutNow()
        let actual = context.actualOffsetY()
        let offsetOK = abs(actual - targetOffsetY) <= 0.5
        var visualOK = true
        if let minY = context.anchorMinY(anchor.anchorAssetID) {
            visualOK = abs((minY - actual) - anchor.anchorVisualY) <= 0.5
        }
        let ok = offsetOK && visualOK
        let phase = machine.verified(ok: ok)
        onPhaseChange?(phase)
        ViewerTrace.log("position.restore.v5 verify actual=\(Int(actual)) target=\(Int(targetOffsetY)) " +
                        "visualY=\(Int(anchor.anchorVisualY)) ok=\(ok) attempts=\(machine.attempts)")
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
            DispatchQueue.main.async { [weak self] in
                self?.attemptRestore(context: context)
            }
        default:
            break
        }
    }

    private func finish(reason: String) {
        pendingAnchor = nil
        ViewerTrace.log("position.restore.v5 \(machine.phase.rawValue) reason=\(reason) " +
                        "strategy=\(lastStrategy.rawValue)")
    }
}
