// MARK: - 职责说明：去重分组（docs/02 §3.3 / docs/03 §5.4 第 5-6 步）——
// 粗筛桶：宽高比近似（±0.02）+ 创建时间 |Δt| ≤ 2s（连续序列：连拍/AI 连拍产生的同组）→
// 桶内两两汉明距离 ≤ 阈值合并（并查集）；≤ 4 高置信重复、≤ 8 疑似重复（阈值设置可调）。
// 推荐保留：原图（未编辑）优先 > 像素面积最大 > 最新修改（docs/03 §3.3）。
// 纯逻辑、Foundation-only（红线 2）；App 侧从 Core Data 指纹缓存构造候选。

import Foundation

/// 参与去重判定的最小条目（App 侧由 FingerprintService 从 Core Data 指纹缓存构造）
public struct DuplicateCandidate {
    public let id: String
    public let dhash: UInt64
    /// pHash 可选：与 dHash 组合提升置信度
    public let phash: UInt64?
    public let aspect: Double
    public let createdAt: Date?
    public let pixelArea: Int
    /// 是否经编辑（modificationDate 显著晚于 creationDate 视为有编辑）
    public let hasEdits: Bool
    public let modificationDate: Date?

    public init(id: String, dhash: UInt64, phash: UInt64?, aspect: Double,
                createdAt: Date?, pixelArea: Int, hasEdits: Bool, modificationDate: Date?) {
        self.id = id
        self.dhash = dhash
        self.phash = phash
        self.aspect = aspect
        self.createdAt = createdAt
        self.pixelArea = pixelArea
        self.hasEdits = hasEdits
        self.modificationDate = modificationDate
    }
}

/// 一个重复组：members 为组内全部 id，recommendedKeepID 为推荐保留项
public struct DuplicateGroup {
    public let members: [String]
    public let recommendedKeepID: String
    /// 组内最小汉明距离（≤ 4 高置信 / ≤ 8 疑似，docs/02 §3.3）
    public let minHammingDistance: Int

    public init(members: [String], recommendedKeepID: String, minHammingDistance: Int) {
        self.members = members
        self.recommendedKeepID = recommendedKeepID
        self.minHammingDistance = minHammingDistance
    }
}

public enum DuplicateGrouper {
    /// 宽高比粗筛容差（docs/03 §5.4：±0.02）
    public static let aspectTolerance = 0.02
    /// 创建时间粗筛窗口（docs/03 §5.4：|Δt| ≤ 2s）
    public static let timeWindow: TimeInterval = 2
    /// 高置信重复的汉明距离
    public static let highConfidenceDistance = 4

    /// 64 bit 汉明距离
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// - Parameter distanceThreshold: 汉明距离 ≤ 8 疑似重复、≤ 4 高置信（docs/02 §3.3）
    public static func groups(from candidates: [DuplicateCandidate],
                              distanceThreshold: Int = 8) -> [DuplicateGroup] {
        guard candidates.count >= 2 else { return [] }

        // 按创建时间排序（无日期者排最后，不参与时间桶）
        let dated = candidates.filter { $0.createdAt != nil }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        guard dated.count >= 2 else { return [] }

        // 并查集
        var parent = [Int](0..<dated.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var current = i
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }
        func union(_ i: Int, _ j: Int) {
            let ri = find(i), rj = find(j)
            if ri != rj { parent[rj] = ri }
        }

        // 滑动窗口配对：|Δt| ≤ 2s 且宽高比 ±0.02 且汉明距离 ≤ 阈值 → 同组
        var minDistances = [Int](repeating: .max, count: dated.count)
        for i in 0..<dated.count {
            for j in (i + 1)..<dated.count {
                let a = dated[i], b = dated[j]
                guard let ta = a.createdAt, let tb = b.createdAt else { continue }
                let delta = tb.timeIntervalSince(ta)
                if delta > timeWindow { break }   // 已排序，后续更远
                guard abs(a.aspect - b.aspect) <= aspectTolerance else { continue }
                let distance = hammingDistance(a.dhash, b.dhash)
                guard distance <= distanceThreshold else { continue }
                union(i, j)
                minDistances[i] = min(minDistances[i], distance)
                minDistances[j] = min(minDistances[j], distance)
            }
        }

        // 按根收集成组
        var buckets: [Int: [Int]] = [:]
        for index in 0..<dated.count {
            buckets[find(index), default: []].append(index)
        }

        let groups = buckets.values
            .filter { $0.count >= 2 }
            .map { members -> DuplicateGroup in
                let candidatesInGroup = members.map { dated[$0] }
                let minDistance = members.map { minDistances[$0] == .max ? distanceThreshold : minDistances[$0] }.min() ?? distanceThreshold
                return DuplicateGroup(members: candidatesInGroup.map(\.id),
                                      recommendedKeepID: recommendedKeep(candidatesInGroup).id,
                                      minHammingDistance: minDistance)
            }
            .sorted { $0.minHammingDistance < $1.minHammingDistance }
        return groups
    }

    /// 推荐保留：原图（未编辑）优先 > 像素面积最大 > 最新修改（docs/03 §3.3）
    public static func recommendedKeep(_ members: [DuplicateCandidate]) -> DuplicateCandidate {
        members.max { lhs, rhs in
            if lhs.hasEdits != rhs.hasEdits { return lhs.hasEdits }        // 未编辑者更大（true 排后）
            if lhs.pixelArea != rhs.pixelArea { return lhs.pixelArea < rhs.pixelArea }   // 面积大者
            return (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
        } ?? members[0]
    }
}
