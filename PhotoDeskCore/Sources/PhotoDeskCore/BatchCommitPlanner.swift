// MARK: - 职责说明：批量提交规划纯逻辑（docs/09 D16 §5）——待删除/待隐藏 id 按上限分批
// （每批一次系统确认，不是每张一次）；提交前对账（缺失 id = alreadyGone，跳过不删）；
// 崩溃后幂等对账（库中已不存在的视为已提交，从队列清除；仍在库中的保留）。

import Foundation

/// 一批待提交条目
public struct CommitBatch: Equatable, Codable {
    public let ids: [String]
    public let index: Int       // 第几批（0 起）
    public let totalBatches: Int

    public init(ids: [String], index: Int, totalBatches: Int) {
        self.ids = ids
        self.index = index
        self.totalBatches = totalBatches
    }
}

public enum BatchCommitPlanner {
    /// 单批上限（docs/09 D16：5,000；超出分批，每批一次系统确认）
    public static let defaultBatchSize = 5_000

    /// 把 id 列表按 batchSize 切批（保持顺序；batchSize ≤ 0 时用默认值）
    public static func batches(for ids: [String], batchSize: Int = defaultBatchSize) -> [CommitBatch] {
        let size = max(1, batchSize)
        guard !ids.isEmpty else { return [] }
        let total = Int((ids.count + size - 1) / size)
        var result: [CommitBatch] = []
        for (batchIndex, offset) in stride(from: 0, to: ids.count, by: size).enumerated() {
            let upper = Swift.min(offset + size, ids.count)
            result.append(CommitBatch(ids: Array(ids[offset..<upper]),
                                      index: batchIndex,
                                      totalBatches: total))
        }
        return result
    }

    /// 提交前对账：available = PhotoKit 按 id 解析到的资产。缺失 id 标记 alreadyGone（不参与本批提交）。
    /// - Returns: (committable: 可提交（保持顺序），missing: 已不在库中)
    public static func partition(ids: [String],
                                 available: Set<String>) -> (committable: [String], missing: [String]) {
        var committable: [String] = []
        var missing: [String] = []
        for id in ids {
            if available.contains(id) {
                committable.append(id)
            } else {
                missing.append(id)
            }
        }
        return (committable, missing)
    }

    /// 崩溃/中断后幂等对账：pending 中已不在库里的 id 视为上一批已提交成功 → 从队列移除；
    /// 仍在库中的保留（下次提交或用户撤销）。
    public static func reconcileAfterInterruption(pending: [String],
                                                  stillInLibrary: Set<String>) -> [String] {
        pending.filter { stillInLibrary.contains($0) }
    }
}
