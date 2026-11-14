// MARK: - 职责说明：多选状态纯逻辑（docs/09 D11/D12；docs/22 §5.4 性能改造）——
// scope（当前筛选结果全集）内的点选切换 / 全选 / 取消全选 / 反选；筛选变化时 selected ∩ newScope 收敛。
// selected 数组保持插入顺序，selectedSet 同步缓存，所有集合判定 O(1)、批量操作 O(n) 或 O(delta)。

import Foundation

public struct SelectionState: Equatable {
    /// 当前选中（保持插入顺序供批量操作展示）
    public private(set) var selected: [String]
    /// 与 selected 同步的集合缓存（docs/22 §5.4：禁止每次 O(n) 构造 Set）
    public private(set) var selectedSet: Set<String>
    /// 多选作用域 = 进入多选时（或筛选变化后）的「当前筛选结果」id 全集
    public private(set) var scope: Set<String>
    /// 作用域标识（docs/13 S10）："month:2024-05" = 单月多选；nil = 普通多选（当前筛选全集）
    public private(set) var scopeID: String?

    /// 全选态：scope 非空且 selected 覆盖 scope
    public var allSelected: Bool { !scope.isEmpty && selectedSet == scope }
    public var isEmpty: Bool { selected.isEmpty }
    /// 作用域是否为单月（scopeID 以 "month:" 开头）
    public var isMonthScope: Bool { scopeID?.hasPrefix("month:") ?? false }

    public init() {
        selected = []
        selectedSet = []
        scope = []
        scopeID = nil
    }

    /// 进入多选：scope = 当前筛选结果全集；initial = 长按进入时初始选中的 id；
    /// scopeID = 作用域标识（单月多选传 "month:<sectionID>"，docs/13 S10）
    public mutating func begin(scope: Set<String>, initial: String? = nil, scopeID: String? = nil) {
        self.scope = scope
        self.scopeID = scopeID
        selected = []
        selectedSet = []
        if let initial, scope.contains(initial) {
            selected.append(initial)
            selectedSet.insert(initial)
        }
    }

    /// 点选切换（scope 外的 id 忽略——不该出现在网格上，防御性）
    public mutating func toggle(_ id: String) {
        guard scope.contains(id) else { return }
        if selectedSet.contains(id) {
            selectedSet.remove(id)
            selected.removeAll { $0 == id }
        } else {
            selected.append(id)
            selectedSet.insert(id)
        }
    }

    /// 加选（框选只加不取消，docs/09 D13）
    public mutating func select(_ id: String) {
        guard scope.contains(id), !selectedSet.contains(id) else { return }
        selected.append(id)
        selectedSet.insert(id)
    }

    /// 批量加选（docs/13 S07）：顺序保持、去重、scope 外 id 忽略
    public mutating func select(_ ids: [String]) {
        for id in ids { select(id) }
    }

    /// 反向滑回时按快照取消单个 cell；不得误取消「滑动开始前已选中」的 cell。
    public mutating func remove(id: String) {
        guard selectedSet.remove(id) != nil else { return }
        selected.removeAll { $0 == id }
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
        selectedSet = seen
    }

    /// v4 滑选：base 为拖动开始帧快照，range 为行带；目标 = base ∪ range。
    public mutating func applyRange(base: Set<String>, range: Set<String>) {
        replaceSelection(Array(base.union(range)).sorted())
    }

    /// 增量应用（docs/32 §2.6）：O(delta)——remove 剔除、add 追加（保持既有插入序，
    /// 不整表重排排序）；全选 2 万张拖一帧 < 4ms 的前提（A09）。scope 外 id 忽略。
    public mutating func applyDelta(add: Set<String>, remove: Set<String>) {
        guard !add.isEmpty || !remove.isEmpty else { return }
        if !remove.isEmpty {
            selected.removeAll { remove.contains($0) }
            selectedSet.subtract(remove)
        }
        var appended: [String] = []
        for id in add where scope.contains(id) && !selectedSet.contains(id) {
            appended.append(id)
        }
        guard !appended.isEmpty else { return }
        selected.append(contentsOf: appended)
        for id in appended { selectedSet.insert(id) }
    }

    /// O(1) 选中判定（cell 配置/徽标刷新高频路径）。
    public func contains(_ id: String) -> Bool {
        selectedSet.contains(id)
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
        selectedSet = scope
    }

    public mutating func deselectAll() {
        selected = []
        selectedSet = []
    }

    /// 反选：selected = scope - selected
    public mutating func invert() {
        selectedSet = scope.subtracting(selectedSet)
        selected = selectedSet.sorted()
    }

    /// 筛选/scope 变化：selected 收敛到新 scope 的交集，并整体替换 scope
    public mutating func intersectScope(with newScope: Set<String>) {
        selectedSet = selectedSet.intersection(newScope)
        selected = selected.filter { newScope.contains($0) }
        scope = newScope
    }

    /// 移除已不在库中的 id（提交删除后调用）
    public mutating func removeAll(_ ids: Set<String>) {
        selected.removeAll { ids.contains($0) }
        selectedSet.subtract(ids)
        scope.subtract(ids)
    }
}
