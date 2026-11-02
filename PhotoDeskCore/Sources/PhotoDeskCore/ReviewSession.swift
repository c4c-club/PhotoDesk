// MARK: - 职责说明：会话式整理队列（docs/09 D16 ★）——滑动删除/隐藏只入队不写 PhotoKit；
// 保持入队顺序（提交按顺序批量）；同一 assetID 只能处于一种 pending（改标自动替换）；
// 上限 10,000 条（超出拒绝入队，防无界内存）；Codable 供 PendingActionStore 持久化（杀进程恢复）。
// 只存 assetID / kind / originIndex / 时间，不存图片、不存 PHAsset（红线 2）。

import Foundation

/// 待处理动作类型
public enum PendingKind: String, Codable, Hashable {
    case delete
    case hide
}

/// 一条待处理记录
public struct PendingEntry: Codable, Hashable, Identifiable {
    public let assetID: String
    public let kind: PendingKind
    /// 入队时在当前整理序列中的位置（恢复排序 / 调试用）
    public let originIndex: Int
    public let markedAt: Date

    public init(assetID: String, kind: PendingKind, originIndex: Int, markedAt: Date) {
        self.assetID = assetID
        self.kind = kind
        self.originIndex = originIndex
        self.markedAt = markedAt
    }

    public var id: String { "\(kind.rawValue):\(assetID)" }
}

/// 整理会话（pendingDelete / pendingHide 双队列）
public struct ReviewSession: Codable, Equatable {
    /// 队列上限（docs/09 D16：10,000）
    public static let maxEntries = 10_000

    public private(set) var entries: [PendingEntry]

    public init(entries: [PendingEntry] = []) {
        self.entries = entries
    }

    // MARK: - 查询

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// 待删除 id（保持入队顺序、去重）
    public var pendingDeleteIDs: [String] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard entry.kind == .delete, !seen.contains(entry.assetID) else { return nil }
            seen.insert(entry.assetID)
            return entry.assetID
        }
    }

    /// 待隐藏 id（保持入队顺序、去重）
    public var pendingHideIDs: [String] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard entry.kind == .hide, !seen.contains(entry.assetID) else { return nil }
            seen.insert(entry.assetID)
            return entry.assetID
        }
    }

    /// 指定类型的待处理数量
    public func count(of kind: PendingKind) -> Int {
        entries.lazy.filter { $0.kind == kind }.count
    }

    /// 指定 assetID 的 pending 类型（未入队返回 nil）
    public func kind(of assetID: String) -> PendingKind? {
        entries.last(where: { $0.assetID == assetID })?.kind
    }

    // MARK: - 入队

    /// 标记待删除；同一 assetID 已 pending（任何类型）→ 先移除旧记录再入队；满员返回 false
    @discardableResult
    public mutating func markDelete(_ assetID: String, originIndex: Int, at markedAt: Date = Date()) -> Bool {
        mark(PendingEntry(assetID: assetID, kind: .delete, originIndex: originIndex, markedAt: markedAt))
    }

    /// 标记待隐藏；语义同 markDelete
    @discardableResult
    public mutating func markHide(_ assetID: String, originIndex: Int, at markedAt: Date = Date()) -> Bool {
        mark(PendingEntry(assetID: assetID, kind: .hide, originIndex: originIndex, markedAt: markedAt))
    }

    private mutating func mark(_ entry: PendingEntry) -> Bool {
        if isPending(entry.assetID) { removeAsset(entry.assetID) }
        guard entries.count < Self.maxEntries else { return false }
        entries.append(entry)
        return true
    }

    // MARK: - 撤销 / 提交

    /// 撤销一条 pending（review 页「恢复」/ Toast「撤销」）
    public mutating func unmark(_ assetID: String, kind: PendingKind) {
        entries.removeAll { $0.assetID == assetID && $0.kind == kind }
    }

    /// 提交成功后移除（按类型批量）
    public mutating func removeCommitted(_ assetIDs: [String], kind: PendingKind) {
        let ids = Set(assetIDs)
        entries.removeAll { ids.contains($0.assetID) && $0.kind == kind }
    }

    // MARK: - 私有

    private func isPending(_ assetID: String) -> Bool {
        entries.contains { $0.assetID == assetID }
    }

    private mutating func removeAsset(_ assetID: String) {
        entries.removeAll { $0.assetID == assetID }
    }
}
