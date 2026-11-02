// MARK: - 职责说明：删除/隐藏后的智能补位纯函数（docs/09 D02/D16 ★）——
// 上滑（从顶部飞出）→ 下一张从底部补位；下滑 → 从顶部补位；末尾回退 → 与飞出边同侧补位（回卷感）；
// 工具栏无手势 → 默认从底部前进；列表删空 → shouldClose（关闭查看器）。
// 不依赖 UIKit；App 侧只把 VerticalEdge 映射为动画方向。

import Foundation

/// 垂直边（entry = 补位进入边；exit = 卡片飞出边）
public enum VerticalEdge: String, Codable {
    case top
    case bottom
}

/// 补位计划
public struct ReplacementPlan: Equatable {
    /// 删除后应停留的 index（nil = 关闭）
    public let nextIndex: Int?
    /// 下一张进入边（nil = 关闭或无需动画）
    public let entryEdge: VerticalEdge?
    /// 列表已空 → 关闭查看器
    public let shouldClose: Bool

    public init(nextIndex: Int?, entryEdge: VerticalEdge?, shouldClose: Bool) {
        self.nextIndex = nextIndex
        self.entryEdge = entryEdge
        self.shouldClose = shouldClose
    }

    /// 静态占位（不移动）
    public static let stay = ReplacementPlan(nextIndex: nil, entryEdge: nil, shouldClose: false)
}

public enum ReplacementPlanner {
    /// - Parameters:
    ///   - currentIndex: 被移除条目的 index
    ///   - countAfterRemoval: 移除后的列表长度
    ///   - exitEdge: 卡片飞出边（上滑 = .top，下滑 = .bottom；工具栏操作 = nil）
    ///   - hasNext: 移除位置之后还有条目（原 i+1 存在）
    ///   - hasPrevious: 移除位置之前还有条目（原 i-1 存在）
    public static func plan(currentIndex: Int,
                            countAfterRemoval: Int,
                            exitEdge: VerticalEdge?,
                            hasNext: Bool,
                            hasPrevious: Bool) -> ReplacementPlan {
        // 列表删空：关闭查看器（docs/09 D02：空列表关闭）
        guard countAfterRemoval > 0 else {
            return ReplacementPlan(nextIndex: nil, entryEdge: nil, shouldClose: true)
        }
        // 后面还有 → 保持 index（原 i+1 顶到 i），下一张按飞出方向对侧补位
        if hasNext {
            let entry: VerticalEdge
            switch exitEdge {
            case .top:    entry = .bottom   // 上滑 → 底部顶上来
            case .bottom: entry = .top      // 下滑 → 顶部压下来
            case nil:     entry = .bottom   // 工具栏/无手势 → 默认前进（底部）
            }
            return ReplacementPlan(nextIndex: currentIndex, entryEdge: entry, shouldClose: false)
        }
        // 已是最后一张 → 回退上一张，补位边与飞出方向相同（回卷）
        guard hasPrevious, currentIndex - 1 >= 0 else {
            // 理论不可达（count>0 且无后无前 = 只剩自身？防御：停在 0）
            return ReplacementPlan(nextIndex: max(0, min(currentIndex, countAfterRemoval - 1)),
                                   entryEdge: exitEdge, shouldClose: false)
        }
        return ReplacementPlan(nextIndex: currentIndex - 1, entryEdge: exitEdge ?? .bottom, shouldClose: false)
    }
}
