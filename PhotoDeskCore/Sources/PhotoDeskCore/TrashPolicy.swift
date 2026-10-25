// MARK: - 职责说明：沙盒回收站（TrashBin）容量淘汰策略（docs/03 §5.1 / 红线 1）。
// 副本只是「撤销保险」而非备份：上限 2GB、按时间从旧到新淘汰、设置可关闭；
// 真正兜底是系统「最近删除」30 天。纯逻辑在本包，落盘/删除动作在 App 侧 TrashBin（红线 2）。
// TODO(P4): 淘汰算法 + 单测（超限、按时间序、空集、恰好等于上限）。

import Foundation

/// 沙盒副本索引条目的最小视图（对应 Core Data TrashItem 的 id/byteSize/createdAt）
public struct TrashRecord {
    public let id: UUID
    public let byteSize: Int64
    public let createdAt: Date

    public init(id: UUID, byteSize: Int64, createdAt: Date) {
        self.id = id
        self.byteSize = byteSize
        self.createdAt = createdAt
    }
}

public enum TrashPolicy {
    /// 默认容量上限 2GB（docs/02 §3.5；设置项 trash.limitMB 可调）
    public static let defaultLimitBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// - Returns: 超出容量上限时应淘汰的记录 id（按 createdAt 从旧到新），不超限则返回空
    public static func evictionCandidates(from records: [TrashRecord],
                                          limitBytes: Int64 = TrashPolicy.defaultLimitBytes) -> [UUID] {
        guard limitBytes >= 0 else { return [] }
        let sorted = records.sorted { $0.createdAt < $1.createdAt }   // 最旧优先
        var total = records.reduce(Int64(0)) { $0 + $1.byteSize }
        guard total > limitBytes else { return [] }

        var candidates: [UUID] = []
        for record in sorted {
            guard total > limitBytes else { break }
            candidates.append(record.id)
            total -= record.byteSize
        }
        return candidates
    }
}
