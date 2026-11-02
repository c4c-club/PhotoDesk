// MARK: - 职责说明：智能清理 ViewModel（docs/05 M4 任务 4.7；docs/09 D15/D16 改造）——
// 扫描（ScanCoordinator）→ 结果（五类卡片数据）→ 待清理清单（pendingIDs）→ 会话入队 → 一次批量提交。
// 执行只经 ReviewSessionController（BatchCommitCoordinator 内一次 deleteAssets/批，系统确认 1 次）；
// 本类不做任何 App 内删除二次确认（docs/09 D03 明令移除）。

import Foundation
import PhotoDeskCore

@MainActor
final class CleanupViewModel: ObservableObject {
    /// 待清理清单（勾选的资源 id）
    @Published private(set) var pendingIDs = Set<String>()
    /// 执行中
    @Published private(set) var isExecuting = false

    let coordinator: ScanCoordinator
    private let reviewSession: ReviewSessionController

    /// 执行结果（页面内联展示，不用 App 内删除确认）
    struct ExecuteOutcome: Equatable {
        let committed: Int
        let skipped: Int
        let failed: Bool
        var message: String {
            if failed { return "系统未允许删除，\(pendingText)仍在待删除" }
            var text = "已移到系统「最近删除」\(committed) 项"
            if skipped > 0 { text += "；\(skipped) 项在 iCloud，请先下载原件" }
            return text
        }
        private var pendingText: String { "所选内容" }
    }

    init(coordinator: ScanCoordinator, reviewSession: ReviewSessionController) {
        self.coordinator = coordinator
        self.reviewSession = reviewSession
    }

    // MARK: - 扫描

    func startScan() {
        pendingIDs.removeAll()
        coordinator.startScan()
    }

    func cancelScan() {
        coordinator.cancel()
    }

    // MARK: - 待清理清单

    func addToPending(_ id: String) { pendingIDs.insert(id) }
    func removeFromPending(_ id: String) { pendingIDs.remove(id) }
    func clearPending() { pendingIDs.removeAll() }

    /// 一键「保留推荐项，其余移到最近删除」（docs/04 §3.3）
    func keepRecommended(in group: DuplicateGroup) {
        for id in group.members where id != group.recommendedKeepID {
            pendingIDs.insert(id)
        }
    }

    // MARK: - 执行（会话入队 + 一次批量提交；无 App 内确认）

    func executePending() async -> ExecuteOutcome {
        guard !isExecuting else {
            return ExecuteOutcome(committed: 0, skipped: 0, failed: false)
        }
        let ids = Array(pendingIDs)
        guard !ids.isEmpty else {
            return ExecuteOutcome(committed: 0, skipped: 0, failed: false)
        }
        isExecuting = true
        defer { isExecuting = false }
        // 入队（幂等：已在 pending 的不重复）→ 一次批量提交（一次系统确认）
        reviewSession.enqueueDeletes(ids: ids)
        let result = await reviewSession.commitDeletes()
        if result.failed {
            // 系统确认取消/失败：队列保留（docs/09 D16 §5.4 不丢数据），清单计数保持
            return ExecuteOutcome(committed: 0, skipped: 0, failed: true)
        }
        pendingIDs.removeAll()
        return ExecuteOutcome(committed: result.committed, skipped: result.skipped, failed: false)
    }
}
