// MARK: - 职责说明：会话整理状态机（docs/09 D16 §2 ★）——滑动入队（同步 <16ms）+ 磁盘 0.2s debounce +
// 批量提交（删除一次 deleteAssets / 隐藏一次 setHidden，只经 BatchCommitCoordinator）+ 重启恢复。
// 提交失败/系统确认取消 → 队列保留不丢数据；onSessionChanged 通知 LibraryViewModel 过滤 pending 项。

import Foundation
import PhotoDeskCore

@MainActor
final class ReviewSessionController: ObservableObject {
    @Published private(set) var session: ReviewSession
    @Published private(set) var isCommitting = false
    @Published private(set) var commitProgress: Double = 0

    var pendingDeleteCount: Int { session.count(of: .delete) }
    var pendingHideCount: Int { session.count(of: .hide) }
    var isEmpty: Bool { session.isEmpty }

    /// LibraryViewModel 订阅：pending 集合变化 → 网格/全选立即排除 pending 项
    var onSessionChanged: ((ReviewSession) -> Void)?
    /// 提交删除完成（SessionReviewView 关闭 / Toast）：(成功张数, 跳过张数, 失败?)
    var onDeleteCommitted: ((Int, Int, Bool) -> Void)?
    /// 提交隐藏完成
    var onHidesCommitted: ((Int, Bool) -> Void)?

    private let store: PendingActionStore
    private let coordinator: BatchCommitCoordinator
    private var saveTask: Task<Void, Never>?
    /// 提交中新增的入队（提交完成后的下一次 debounce 保存会带上）
    private var pendingSaveAfterCommit = false

    init(store: PendingActionStore = PendingActionStore(),
         writer: PhotoWriterProtocol,
         trashBin: TrashBin?,
         settings: SettingsStore) {
        self.store = store
        self.coordinator = BatchCommitCoordinator(writer: writer, trashBin: trashBin)
        // 启动恢复：不自动提交、不自动弹系统框（docs/09 D16 §3.8）
        self.session = store.load()
    }

    // MARK: - 入队（滑动路径：同步、零 PhotoKit）

    @discardableResult
    func enqueueDelete(id: String, originIndex: Int) -> Bool {
        guard session.markDelete(id, originIndex: originIndex) else { return false }
        sessionChanged()
        return true
    }

    @discardableResult
    func enqueueHide(id: String, originIndex: Int) -> Bool {
        guard session.markHide(id, originIndex: originIndex) else { return false }
        sessionChanged()
        return true
    }

    /// 多选批量入队（originIndex 无序列语义，统一 0）
    func enqueueDeletes(ids: [String]) {
        for id in ids { _ = session.markDelete(id, originIndex: 0) }
        sessionChanged()
    }

    func enqueueHides(ids: [String]) {
        for id in ids { _ = session.markHide(id, originIndex: 0) }
        sessionChanged()
    }

    /// 撤销一条 pending（Toast「撤销」/ review 页「恢复」）——零 PhotoKit 写
    func undoPending(id: String, kind: PendingKind) {
        session.unmark(id, kind: kind)
        sessionChanged()
    }

    /// review 页逐张恢复（= undoPending 的 UI 语义别名）
    func restore(id: String) {
        session.unmark(id, kind: .delete)
        session.unmark(id, kind: .hide)
        sessionChanged()
    }

    // MARK: - 批量提交（唯一 PhotoKit 写入口）

    /// 「全部移到最近删除」：副本（尊重开关）→ 分批一次 deleteAssets/批。返回 (成功, 跳过, 失败?)
    @discardableResult
    func commitDeletes() async -> (committed: Int, skipped: Int, failed: Bool) {
        guard !isCommitting else { return (0, 0, false) }
        let ids = session.pendingDeleteIDs
        guard !ids.isEmpty else { return (0, 0, false) }
        isCommitting = true
        commitProgress = 0
        defer {
            isCommitting = false
            if pendingSaveAfterCommit { saveNow() }
        }
        do {
            let outcome = try await coordinator.commitDeletes(ids: ids) { [weak self] done, total in
                self?.commitProgress = total > 0 ? Double(done) / Double(total) : 1
            }
            // 幂等：成功的移除队列；skipped（iCloud-only）保留待用户先下载
            session.removeCommitted(outcome.committed, kind: .delete)
            saveNow()
            sessionChanged(push: true)
            onDeleteCommitted?(outcome.committed.count, outcome.skippedNeedsDownload.count, false)
            return (outcome.committed.count, outcome.skippedNeedsDownload.count, false)
        } catch {
            // 系统确认取消 / 写失败：队列保留（docs/09 D16 §5.4：不丢数据）
            onDeleteCommitted?(0, 0, true)
            return (0, 0, true)
        }
    }

    /// 「全部隐藏」/ flushHidesIfNeeded：一次批量 setHidden
    @discardableResult
    func commitHides() async -> (committed: Int, failed: Bool) {
        guard !isCommitting else { return (0, false) }
        let ids = session.pendingHideIDs
        guard !ids.isEmpty else { return (0, false) }
        isCommitting = true
        commitProgress = 0
        defer { isCommitting = false }
        do {
            try await coordinator.commitHides(ids: ids)
            session.removeCommitted(ids, kind: .hide)
            saveNow()
            sessionChanged(push: true)
            onHidesCommitted?(ids.count, false)
            return (ids.count, false)
        } catch {
            onHidesCommitted?(0, true)
            return (0, true)
        }
    }

    /// 进入 Vault / 离开整理会话 / App 进后台：批量提交待隐藏（docs/09 D04）
    func flushHidesIfNeeded(reason: String) async {
        guard pendingHideCount > 0 else { return }
        _ = await commitHides()
    }

    // MARK: - 持久化（0.2s debounce；入队同步完成内存部分）

    private func sessionChanged(push: Bool = true) {
        if push { onSessionChanged?(session) }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.saveNow() }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        if isCommitting {
            pendingSaveAfterCommit = true   // 提交中不写盘，结束再落
            return
        }
        pendingSaveAfterCommit = false
        store.save(session)
        store.clearIfEmpty(session)
    }
}
