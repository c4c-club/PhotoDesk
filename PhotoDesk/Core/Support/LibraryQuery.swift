// MARK: - 职责说明：主库查询抽象（docs/09 D10 §2.1）——scope（查什么）+ filter（怎么筛）+ sort（怎么排）。
// key 必须跨进程稳定：scope + canonical JSON（sortedKeys）+ sort 拼 FNV-1a 64 位摘要。
// 禁止 Swift hashValue（每次启动随机化 → 位置记忆全部失效，docs/09 D08 明令）。

import Foundation
import PhotoDeskCore

struct LibraryQuery: Equatable {
    var scope: PhotoScope = .all
    var filter: SearchPredicate = .default
    var sortAscending: Bool = false

    /// 跨进程稳定的查询键（位置记忆 / 筛选持久化的命名空间）
    var key: String {
        Self.stableKey(scope: scope, filter: filter, sortAscending: sortAscending)
    }

    static func stableKey(scope: PhotoScope, filter: SearchPredicate, sortAscending: Bool) -> String {
        let canonical = "\(scopeKey(scope))|\(canonicalFilterJSON(filter))|sort=\(sortAscending ? "asc" : "desc")"
        return Self.fnv1a(canonical)
    }

    // MARK: - 规范化

    private static func scopeKey(_ scope: PhotoScope) -> String {
        switch scope {
        case .all:               return "all"
        case .favorites:         return "favorites"
        case .hidden:            return "hidden"
        case .recentlyDeleted:   return "recentlyDeleted"
        case .videos:            return "videos"
        case .screenshots:       return "screenshots"
        case .album(let id):     return "album:\(id)"
        case .smartAlbum(let s): return "smart:\(s.rawValue)"
        case .search(let p):     return "search:\(canonicalFilterJSON(p))"
        }
    }

    /// 谓词 → canonical JSON（sortedKeys 保证字段序稳定；编码失败回退描述串）
    static func canonicalFilterJSON(_ filter: SearchPredicate) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(filter),
              let json = String(data: data, encoding: .utf8) else {
            return String(describing: filter)
        }
        return json
    }

    /// FNV-1a 64 位（跨进程/跨启动稳定；输出 16 位十六进制）
    static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
