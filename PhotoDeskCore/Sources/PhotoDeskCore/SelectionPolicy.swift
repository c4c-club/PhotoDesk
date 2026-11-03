// MARK: - 职责说明：多选状态纯逻辑（docs/09 D11/D12）——scope（当前筛选结果全集）内的
// 点选切换 / 全选 / 取消全选 / 反选；筛选变化时 selected ∩ newScope 收敛（已筛掉的 id 不再保留）。
// O(n) 集合操作，不逐 cell 遍历；App 侧只负责把 scope 传进来并刷新可见 cell。

import Foundation

public struct SelectionState: Equatable {
    /// 当前选中（保持插入顺序供批量操作展示；集合判定用 selectedSet）
    public private(set) var selected: [String]
    /// 多选作用域 = 进入多选时（或筛选变化后）的「当前筛选结果」id 全集
    public private(set) var scope: Set<String>
    /// 作用域标识（docs/13 S10）："month:2024-05" = 单月多选；nil = 普通多选（当前筛选全集）
    public private(set) var scopeID: String?

    public var selectedSet: Set<String> { Set(selected) }
    /// 全选态：scope 非空且 selected 覆盖 scope
    public var allSelected: Bool { !scope.isEmpty && selectedSet == scope }
    public var isEmpty: Bool { selected.isEmpty }
    /// 作用域是否为单月（scopeID 以 "month:" 开头）
    public var isMonthScope: Bool { scopeID?.hasPrefix("month:") ?? false }

    public init() {
        selected = []
        scope = []
        scopeID = nil
    }

    /// 进入多选：scope = 当前筛选结果全集；initial = 长按进入时初始选中的 id；
    /// scopeID = 作用域标识（单月多选传 "month:<sectionID>"，docs/13 S10）
    public mutating func begin(scope: Set<String>, initial: String? = nil, scopeID: String? = nil) {
        self.scope = scope
        self.scopeID = scopeID
        selected = []
        if let initial, scope.contains(initial) {
            selected.append(initial)
        }
    }

    /// 点选切换（scope 外的 id 忽略——不该出现在网格上，防御性）
    public mutating func toggle(_ id: String) {
        guard scope.contains(id) else { return }
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
    }

    /// 加选（框选只加不取消，docs/09 D13）
    public mutating func select(_ id: String) {
        guard scope.contains(id), !selectedSet.contains(id) else { return }
        selected.append(id)
    }

    /// 批量加选（docs/13 S07）：顺序保持、去重、scope 外 id 忽略
    public mutating func select(_ ids: [String]) {
        for id in ids {
            select(id)
        }
    }

    /// 范围替换（docs/13 S07 长按拖选）：选中集整体替换为给定 id 列表
    ///（调用方传入 base ∪ range），过滤 scope 外 id、去重保序。
    public mutating func replaceSelection(_ ids: [String]) {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where scope.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        selected = result
    }

    /// 范围选择（docs/13 S07）：orderedIDs 内 anchor→target 连续范围与当前选中取并集；
    /// 任一端缺失时无操作（保持现状）。
    public mutating func selectRange(in orderedIDs: [String], from anchor: String, to target: String) {
        let range = SelectionRange.ids(in: orderedIDs, from: anchor, to: target)
        guard !range.isEmpty else { return }
        var merged = selected
        for id in range where !selectedSet.contains(id) {
            merged.append(id)
        }
        replaceSelection(merged)
    }

    public mutating func selectAll() {
        selected = scope.sorted()
    }

    public mutating func deselectAll() {
        selected = []
    }

    /// 反选：selected = scope - selected
    public mutating func invert() {
        let current = selectedSet
        selected = scope.filter { !current.contains($0) }.sorted()
    }

    /// 筛选/scope 变化：selected 收敛到新 scope 的交集，并整体替换 scope
    public mutating func intersectScope(with newScope: Set<String>) {
        let keep = selected.filter { newScope.contains($0) }
        scope = newScope
        selected = keep
    }

    /// 移除已不在库中的 id（提交删除后调用）
    public mutating func removeAll(_ ids: Set<String>) {
        selected.removeAll { ids.contains($0) }
        scope.subtract(ids)
    }
}
