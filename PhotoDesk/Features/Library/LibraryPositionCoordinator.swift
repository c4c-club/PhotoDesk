// MARK: - 职责说明：位置记忆 v4 单一协调器（docs/22 §4.4.3–4.4.4）——
// 唯一 save/restore 入口：保存用 0.35s DispatchWorkItem 防抖 + revision 代际（旧 revision 丢弃），
// 编码/UserDefaults 写走串行 utility 队列；恢复由 Core PositionRestoreStateMachine 驱动，
// 恢复期拒绝一切保存。VC 只负责提供几何快照与执行 setContentOffset，不直接触碰 positionStore。

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

/// 恢复时 VC 提供的实时几何与写 offset 能力。
struct LibraryPositionRestoreContext {
    let bounds: CGSize
    let numberOfSections: Int
    let isIndexComplete: Bool
    let contentHeight: Double
    let viewportHeight: Double
    let adjustedTop: Double
    let bottomInset: Double
    let anchorMinY: (String) -> Double?
    let sectionMinY: (String, Int) -> Double?
    let applyOffset: (Double) -> Void
    let actualOffsetY: () -> Double
}

@MainActor
final class LibraryPositionCoordinator {
    private let store: LibraryPositionStore
    private let writeQueue = DispatchQueue(label: "com.example.PhotoDesk.position-write",
                                           qos: .utility)
    private let revisionLock = NSLock()
    private var revision: Int = 0
    private var pendingSave: DispatchWorkItem?
    private var state = PositionRestoreState()
    private var pendingAnchor: LibraryPosition?
    private var lastRestoredQueryKey: String?
    private var restoreGeneration: Int = 0
    private var targetOffsetY: Double = 0

    /// 最近一次恢复采用的策略（asset / section / ratio / none），供调试汇总。
    private(set) var lastStrategy: PositionRestoreStrategy = .none
    /// 阶段变化回调（VC 用于遮罩开关；不参与几何写入）。
    var onPhaseChange: ((PositionRestorePhase) -> Void)?

    init(store: LibraryPositionStore) {
        self.store = store
    }

    var phase: PositionRestorePhase { state.phase }
    var isRestoreInFlight: Bool { state.isInFlight }

    // MARK: - 保存

    /// 滚动防抖保存（0.35s）。snapshot 为 nil / 位置记忆关闭 / 恢复中 → 丢弃。
    func scheduleSave(reason: String, snapshot: LibraryPositionSnapshot?, debounce: TimeInterval = 0.35) {
        guard store.isEnabled, !state.isInFlight, let snapshot else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.commitSave(reason: reason, snapshot: snapshot)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, debounce), execute: work)
    }

    /// 立即保存（拖动结束 / 切后台 / 退出）。恢复中一律拒绝。
    func saveNow(reason: String, snapshot: LibraryPositionSnapshot?) {
        guard store.isEnabled, !state.isInFlight, let snapshot else { return }
        pendingSave?.cancel()
        pendingSave = nil
        // 立即保存路径（拖动结束/切后台/退出）等写完再返回：保证进程被杀的最后一笔一定落盘，
        // 也让单测在 savePositionNow 之后能同步读到 store。滚动防抖仍走异步队列。
        commitSave(reason: reason, snapshot: snapshot, waitUntilDone: true)
    }

    func cancelPendingSaves() {
        pendingSave?.cancel()
        pendingSave = nil
        _ = nextRevision()
    }

    private func commitSave(reason: String, snapshot: LibraryPositionSnapshot, waitUntilDone: Bool = false) {
        guard store.isEnabled, !state.isInFlight else { return }
        let rev = nextRevision()
        let position = LibraryPosition(anchorAssetID: snapshot.anchorAssetID,
                                       anchorVisualY: snapshot.anchorVisualY,
                                       anchorContentOffsetY: snapshot.contentOffsetY,
                                       assetID: snapshot.anchorAssetID,
                                       sectionID: snapshot.anchorSectionID,
                                       itemIndexInSection: snapshot.anchorItemIndex,
                                       offsetRatio: ratio(snapshot),
                                       contentHeight: snapshot.contentHeight,
                                       viewportHeight: snapshot.viewportHeight,
                                       savedAt: Date())
        let queryKey = snapshot.queryKey
        let work = { [weak self] in
            guard let self else { return }
            guard self.isCurrent(rev) else { return }
            self.store.save(position, queryKey: queryKey)
            ViewerTrace.log("position.save.v4 \(reason) rev=\(rev) anchor=\(position.anchorAssetID.prefix(8)) visualY=\(Int(position.anchorVisualY)) off=\(Int(position.anchorContentOffsetY))")
        }
        if waitUntilDone {
            writeQueue.sync(execute: work)
        } else {
            writeQueue.async(execute: work)
        }
    }

    private func ratio(_ snapshot: LibraryPositionSnapshot) -> Double {
        let scrollable = max(1, snapshot.contentHeight - snapshot.viewportHeight)
        return min(1, max(0, snapshot.contentOffsetY / scrollable))
    }

    private func nextRevision() -> Int {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        revision += 1
        return revision
    }

    private func isCurrent(_ value: Int) -> Bool {
        revisionLock.lock()
        defer { revisionLock.unlock() }
        return value == revision
    }

    // MARK: - 恢复

    /// 只 load 一次锚点；queryKey 变化才重置状态机。无锚点直接 done（不遮罩）。
    func beginRestore(queryKey: String) {
        guard queryKey != lastRestoredQueryKey else { return }
        lastRestoredQueryKey = queryKey
        cancelPendingSaves()
        restoreGeneration += 1
        pendingAnchor = store.isEnabled ? store.load(queryKey: queryKey) : nil
        state.begin(generation: restoreGeneration)
        if pendingAnchor == nil {
            state.skip()
            ViewerTrace.log("position.restore.v4 skip query=\(queryKey.prefix(8)) reason=no-anchor")
            onPhaseChange?(state.phase)
            return
        }
        ViewerTrace.log("position.restore.v4 begin query=\(queryKey.prefix(8)) anchor=\(pendingAnchor?.anchorAssetID.prefix(8) ?? "-")")
        onPhaseChange?(state.phase)
    }

    /// applySnapshot completion / viewDidLayoutSubviews / viewDidAppear 都调用；bounds=0 保持 waitingLayout。
    func attemptRestore(context: LibraryPositionRestoreContext) {
        guard state.isInFlight, let anchor = pendingAnchor else { return }
        if state.timedOut() {
            finish(.failed, reason: "timeout")
            return
        }
        if state.phase == .verifying {
            verify(context: context)
            return
        }
        let boundsReady = context.bounds.width > 0 && context.bounds.height > 0
        let assetMinY = context.anchorMinY(anchor.anchorAssetID)
        let phase = state.layoutAvailable(hasSections: context.numberOfSections > 0,
                                          boundsReady: boundsReady,
                                          anchorPresent: assetMinY != nil,
                                          indexComplete: context.isIndexComplete)
        onPhaseChange?(phase)
        switch phase {
        case .waitingSnapshot, .waitingLayout:
            return
        case .verifying:
            verify(context: context)
        case .applying:
            applyAnchor(context: context, anchor: anchor)
        default:
            return
        }
    }

    private func applyAnchor(context: LibraryPositionRestoreContext, anchor: LibraryPosition) {
        let assetMinY = context.anchorMinY(anchor.anchorAssetID)
        let sectionMinY = context.sectionMinY(anchor.sectionID, anchor.itemIndexInSection)
        let resolved = PositionAnchorPolicy.resolve(anchor: anchor.toCoreAnchor,
                                                    assetCellMinY: assetMinY,
                                                    sectionCellMinY: sectionMinY,
                                                    contentHeight: context.contentHeight,
                                                    viewportHeight: context.viewportHeight,
                                                    adjustedTop: context.adjustedTop,
                                                    bottomInset: context.bottomInset)
        lastStrategy = resolved.strategy
        guard resolved.strategy != .none else {
            finish(.done, reason: "no-anchor")
            return
        }
        targetOffsetY = resolved.offsetY
        state.applied()
        context.applyOffset(resolved.offsetY)
        onPhaseChange?(state.phase)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.isInFlight else { return }
            self.attemptRestore(context: context)
        }
    }

    private func verify(context: LibraryPositionRestoreContext) {
        guard let anchor = pendingAnchor else { return }
        let actual = context.actualOffsetY()
        let offsetOK = abs(actual - targetOffsetY) <= 1
        var visualOK = true
        if let minY = context.anchorMinY(anchor.anchorAssetID) {
            visualOK = abs((minY - actual) - anchor.anchorVisualY) <= 1
        }
        let ok = offsetOK && visualOK
        let phase = state.verified(ok: ok)
        onPhaseChange?(phase)
        switch phase {
        case .done:
            finish(.done, reason: lastStrategy.rawValue)
        case .failed:
            finish(.failed, reason: "verify-\(state.attempts)")
        case .applying:
            ViewerTrace.log("position.restore.v4 retry attempt=\(state.attempts) offset=\(Int(actual)) target=\(Int(targetOffsetY))")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state.phase == .applying, let anchor = self.pendingAnchor else { return }
                self.applyAnchor(context: context, anchor: anchor)
            }
        default:
            break
        }
    }

    private func finish(_ phase: PositionRestorePhase, reason: String) {
        pendingAnchor = nil
        onPhaseChange?(phase)
        ViewerTrace.log("position.restore.v4 \(phase.rawValue) reason=\(reason)")
    }
}
