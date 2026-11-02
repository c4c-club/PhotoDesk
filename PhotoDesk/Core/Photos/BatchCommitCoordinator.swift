// MARK: - 职责说明：批量提交协调器（docs/09 D16 §5）★——全应用唯一被允许调用 PhotoWriter
// 删除/隐藏批量写的地方。删除：安全副本（尊重 safetyCopyEnabled；iCloud-only 跳过并保留队列）
// → 按 BatchCommitPlanner 5,000 分批 → 每批一次 moveToRecentlyDeleted（= 一次系统确认）。
// 隐藏：一次 setHidden 批量提交（通常无系统确认）。滑动路径绝不调用本类（0 PhotoKit 写）。

import Foundation

@MainActor
final class BatchCommitCoordinator {
    struct DeleteOutcome: Equatable {
        let committed: [String]
        /// iCloud-only / 副本失败被跳过的 id（保留在队列，docs/09 §7：不能删无副本项）
        let skippedNeedsDownload: [String]
    }

    private let writer: PhotoWriterProtocol
    /// nil = mock 模式（UI 测试）：跳过副本，直接批量提交到 mock writer
    private let trashBin: TrashBin?

    init(writer: PhotoWriterProtocol, trashBin: TrashBin?) {
        self.writer = writer
        self.trashBin = trashBin
    }

    // MARK: - 删除提交

    /// - Parameter progress: (已完成张数, 总张数)——@MainActor 闭包（调用方为 @MainActor）
    func commitDeletes(ids: [String],
                       progress: @MainActor @escaping (Int, Int) -> Void) async throws -> DeleteOutcome {
        guard !ids.isEmpty else { return DeleteOutcome(committed: [], skippedNeedsDownload: []) }
        let batches = BatchCommitPlanner.batches(for: ids)
        let total = ids.count
        var committed: [String] = []
        var skipped: [String] = []
        var done = 0

        for batch in batches {
            var batchIDs = batch.ids
            // 红线 1：副本开关开启时，提交前统一落撤销保险副本；拿不到原件（iCloud-only）→ 跳过保留
            if let trashBin, trashBin.isSafetyCopyEnabled {
                var withCopy: [String] = []
                for id in batchIDs {
                    do {
                        _ = try await trashBin.storeCopy(forAssetID: id)
                        withCopy.append(id)
                    } catch TrashError.needsDownload {
                        skipped.append(id)
                    } catch {
                        skipped.append(id)
                    }
                }
                batchIDs = withCopy
            }
            guard !batchIDs.isEmpty else {
                done += batch.ids.count
                progress(done, total)
                continue
            }
            // 每批一次 performChanges → 一次系统确认（非每张）
            try await writer.moveToRecentlyDeleted(ids: batchIDs)
            committed.append(contentsOf: batchIDs)
            done += batch.ids.count
            progress(done, total)
        }
        return DeleteOutcome(committed: committed, skippedNeedsDownload: skipped)
    }

    // MARK: - 隐藏提交

    /// 一次 performChanges 批量 isHidden = true
    func commitHides(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await writer.setHidden(ids: ids, isHidden: true)
    }
}
