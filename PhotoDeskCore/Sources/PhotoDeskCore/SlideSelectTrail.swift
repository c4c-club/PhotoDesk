// MARK: - 职责说明：原生轨迹滑选路径事务（M18 T02，docs/38 §2.3、docs/37 §5）——
// 手势基线快照 + 单调路径栈：手势基线 base 在 beginTrail 帧（enterSelection 之后）由 App 拍快照；
// consume(orderedIDs) 逐 id 处理——抖动（id == path.last）忽略、已访问（occurrences 非空）截断回
// 最近一次出现（出栈 cell 回 base 态）、新 id 入栈并按 mode 改变选中；
// target = select ? base ∪ Set(path) : base − Set(path)，按事件增量维护（O(delta)，不整集重算、
// 不 sorted() 全量重排——最终落地由 SelectionState.applyDelta 承担）。
// 净差语义：帧内记录每 id 的「最后一次事件方向」（入/出）；同帧 A→B→A→B 只留最后事件，
// 即 delta = 本帧相对上一帧 target 的净差（docs/38 §2.3 第 5 行），O(delta) 无 subtracting 全量运算。
// 帧累计器为结构体持久存储（removeAll(keepingCapacity:)），连跑上万帧零重复分配。
// 不变量：path 内无重复 id（append 前提 occurrences[id] 为 nil，截断同步清除出栈项），
// 故 occurrences 用 [String: Int]（最近一次出现下标）即精确等价于 docs/38 §2.3 的 [String: [Int]]。
// base 在 init 时先与 scope 取交集（scope 外 id 永不入栈、不出现在 target）；
// base/mode/scope 为 init 快照（值语义防御性拷贝），consume 不可变。
// consume([]) 幂等不改状态、返回空 delta。仅 import Foundation，零 Apple 依赖（红线 2）。

import Foundation

/// 轨迹滑选模式：起手 cell 未选 → select（滑过即选）；已选 → deselect（滑过即取消）。
public enum SlideSelectMode: Equatable, Sendable {
    case select
    case deselect
}

/// 一帧 consume 的净选中变化（相对上一帧 target）；空 delta = 本帧无净变化。
public struct SlideSelectDelta: Equatable, Sendable {
    public let add: Set<String>
    public let remove: Set<String>

    public var isEmpty: Bool { add.isEmpty && remove.isEmpty }

    public init(add: Set<String> = [], remove: Set<String> = []) {
        self.add = add
        self.remove = remove
    }
}

/// 路径栈事务：滑到哪选到哪、回滑取消、手势前已选保持。
public struct SlideSelectTrail: Sendable {
    /// beginTrail 帧基线（已与 scope 取交集）；select 模式下永不被 delta 触碰。
    public let base: Set<String>
    /// 多选作用域（月份 scope 等）；nil = 当前筛选全集。
    public let scope: Set<String>?
    /// init 快照，由 anchorInitiallySelected 决定（true = 起手已选 = deselect）。
    public let mode: SlideSelectMode
    /// 访问路径栈（保持进入顺序，无重复）。
    public private(set) var path: [String]
    /// 当前选中目标（事件级增量维护；App 侧经 applySelectionDelta 落到 SelectionState）。
    public private(set) var target: Set<String>

    /// id → 在 path 中的最近一次出现下标（path 无重复不变量下即「已访问」判定）。
    private var occurrences: [String: Int]
    /// 帧内每 id 的最后一次事件方向（true = 加入 target / false = 移出 target）；
    /// 帧尾合成净 delta 后清空（保留容量，跨帧零分配）。
    private var frameLastOp: [String: Bool]

    public init(base: Set<String>, anchorInitiallySelected: Bool, scope: Set<String>? = nil) {
        let scopedScope = scope.map { Set($0) }
        self.scope = scopedScope
        self.base = base.intersection(scopedScope ?? base)
        self.mode = anchorInitiallySelected ? .deselect : .select
        self.path = []
        self.target = self.base
        self.occurrences = [:]
        self.frameLastOp = [:]
    }

    /// 消费一帧有序命中 id（线段扫掠按进入顺序输出）；返回相对上一帧的净 add/remove。
    @discardableResult
    public mutating func consume(_ orderedIDs: [String]) -> SlideSelectDelta {
        guard !orderedIDs.isEmpty else { return SlideSelectDelta() }
        for id in orderedIDs {
            guard !id.isEmpty else { continue }                            // 空 id 防御性忽略
            if let scopeSet = scope, !scopeSet.contains(id) { continue }   // scope 外忽略
            if path.last == id { continue }                                // 抖动（docs/38 §2.3 第 1 行）
            if let lastIndex = occurrences[id] {
                let popCount = path.count - 1 - lastIndex
                if popCount > 0 {                                          // 回滑截断：出栈回 base 态
                    for k in 0..<popCount {
                        let popped = path[path.count - 1 - k]
                        occurrences.removeValue(forKey: popped)
                        restoreToBase(popped)
                    }
                    path.removeLast(popCount)
                }
            } else {                                                       // 新访问：入栈
                path.append(id)
                occurrences[id] = path.count - 1
                enterTrail(id)
            }
        }
        guard !frameLastOp.isEmpty else { return SlideSelectDelta() }
        var addSet = Set<String>(minimumCapacity: frameLastOp.count)
        var removeSet = Set<String>()
        for (id, joined) in frameLastOp {
            if joined { addSet.insert(id) } else { removeSet.insert(id) }
        }
        frameLastOp.removeAll(keepingCapacity: true)
        return SlideSelectDelta(add: addSet, remove: removeSet)
    }

    /// 新 id 入栈对 target 的影响；返回值即事件是否真实改变 target（base 内 id 入栈无净差）。
    private mutating func enterTrail(_ id: String) {
        switch mode {
        case .select:
            if target.insert(id).inserted { frameLastOp[id] = true }
        case .deselect:
            if target.remove(id) != nil { frameLastOp[id] = false }
        }
    }

    /// 出栈 cell 回 base 态（docs/38 §2.3：回滑恢复由 base 决定，不由路径栈决定）。
    private mutating func restoreToBase(_ id: String) {
        switch mode {
        case .select:
            if !base.contains(id), target.remove(id) != nil { frameLastOp[id] = false }
        case .deselect:
            if base.contains(id), target.insert(id).inserted { frameLastOp[id] = true }
        }
    }
}
