// MARK: - 职责说明：去重分组（docs/02 §3.3 / docs/03 §5.4 第 5-6 步）——
// 分桶（宽高比近似 + |Δt| ≤ 2s）→ 桶内两两汉明距离 → 生成组并推荐保留项（原图 > 尺寸最大 > 有编辑 > 最新修改）。
// TODO(P4): 分组 + 推荐算法 + 单测（阈值边界 8/4、分桶正确性）。

import Foundation

/// 参与去重判定的最小条目（App 侧由 FingerprintService 从 Core Data 指纹缓存构造）
public struct DuplicateCandidate {
    public let id: String
    public let dhash: UInt64
    /// pHash 可选：与 dHash 组合提升置信度
    public let phash: UInt64?
    public let aspect: Double
    public let createdAt: Date?

    public init(id: String, dhash: UInt64, phash: UInt64?, aspect: Double, createdAt: Date?) {
        self.id = id
        self.dhash = dhash
        self.phash = phash
        self.aspect = aspect
        self.createdAt = createdAt
    }
}

/// 一个重复组：members 为组内全部 id，recommendedKeepID 为推荐保留项
public struct DuplicateGroup {
    public let members: [String]
    public let recommendedKeepID: String

    public init(members: [String], recommendedKeepID: String) {
        self.members = members
        self.recommendedKeepID = recommendedKeepID
    }
}

public enum DuplicateGrouper {
    /// 64 bit 汉明距离
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        // TODO(P4): (a ^ b).nonzeroBitCount
        return 0
    }

    /// - Parameter distanceThreshold: 汉明距离 ≤ 8 疑似重复、≤ 4 高置信（docs/02 §3.3）
    public static func groups(from candidates: [DuplicateCandidate],
                              distanceThreshold: Int = 8) -> [DuplicateGroup] {
        // TODO(P4): 分桶降比较量级 → 桶内两两比较 → 成组 + 推荐保留
        return []
    }
}
