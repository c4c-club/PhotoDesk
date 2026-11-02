// MARK: - 职责说明：存储统计聚合纯逻辑（docs/09 D07）——按类型（照片/视频/其他）与年份聚合字节、
// 未知大小计数、占比。输入为基础类型（mediaType 用 Int：0 photo / 1 video / 2 other；bytes nil = 未知，
// 通常为 iCloud-only 未取到字节的项），供 StorageStatsService 在 App 侧调用与单测。

import Foundation

/// 单条统计输入（App 侧从 PhotoItem + AssetSizeProvider 组装）
public struct StorageEntry: Hashable {
    public let mediaType: Int     // 0 photo / 1 video / 2 other
    public let year: Int?         // creationDate 年份（nil = 无日期）
    public let bytes: Int64?      // nil = 大小未知（不参与聚合，计入 unknownCount）

    public init(mediaType: Int, year: Int?, bytes: Int64?) {
        self.mediaType = mediaType
        self.year = year
        self.bytes = bytes
    }
}

/// 聚合结果
public struct StorageSummary: Equatable {
    public var totalBytes: Int64 = 0
    public var photoBytes: Int64 = 0
    public var videoBytes: Int64 = 0
    public var otherBytes: Int64 = 0
    /// 大小未知的条目数（脚注「部分 iCloud 资源大小未知」）
    public var unknownCount = 0
    public var byYear: [Int: Int64] = [:]

    public init() {}
}

public enum StorageMath {
    /// 单次遍历聚合（10,000 条毫秒级；App 侧不必再拆线程）
    public static func summarize(_ entries: [StorageEntry]) -> StorageSummary {
        var summary = StorageSummary()
        for entry in entries {
            guard let bytes = entry.bytes else {
                summary.unknownCount += 1
                continue
            }
            summary.totalBytes += bytes
            switch entry.mediaType {
            case 0:  summary.photoBytes += bytes
            case 1:  summary.videoBytes += bytes
            default: summary.otherBytes += bytes
            }
            if let year = entry.year {
                summary.byYear[year, default: 0] += bytes
            }
        }
        return summary
    }

    /// 占比（0–100，整数；total ≤ 0 时返回 0）
    public static func percent(_ bytes: Int64, of total: Int64) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(bytes) / Double(total) * 100).rounded())
    }
}
