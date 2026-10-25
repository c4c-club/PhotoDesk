// MARK: - 职责说明：智能清理 ViewModel（docs/05 M4 任务 4.7）——
// 扫描（ScanCoordinator）→ 结果（五类卡片数据）→ 待清理清单（pendingIDs）→ 二次确认 → 批量执行。
// 执行复用 LibraryViewModel.performBatch(.moveToRecentlyDeleted)（TrashBin 副本先行 + 撤销栈，红线 1）。

import Foundation
import PhotoDeskCore

@MainActor
final class CleanupViewModel: ObservableObject {
    /// 待清理清单（勾选的资源 id）
    @Published private(set) var pendingIDs = Set<String>()
    /// 执行中
    @Published private(set) var isExecuting = false

    let coordinator: ScanCoordinator
    private let libraryViewModel: LibraryViewModel

    init(coordinator: ScanCoordinator, libraryViewModel: LibraryViewModel) {
        self.coordinator = coordinator
        self.libraryViewModel = libraryViewModel
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

    // MARK: - 执行（二次确认由 View 的 alert 承担）

    func executePending() async -> LibraryViewModel.BatchOutcome {
        guard !isExecuting, !pendingIDs.isEmpty else {
            return LibraryViewModel.BatchOutcome(succeeded: 0, needsDownload: 0)
        }
        isExecuting = true
        let outcome = await libraryViewModel.performBatch(.moveToRecentlyDeleted, ids: Array(pendingIDs))
        pendingIDs.removeAll()
        isExecuting = false
        return outcome
    }
}
