// MARK: - 职责说明：范围选择纯函数（docs/13 S07）——
// 长按拖选：有序 id 列表内 anchor→target 的连续范围（双向、包含两端）。
// 缺失任一端返回空数组；重复 id 去重保序；10k 列表 < 10ms。App 侧 LibraryViewController
// 只负责把 indexPath 换成 id 并把结果喂给 SelectionState.replaceSelection。

import Foundation

public enum SelectionRange {
    /// - Parameters:
    ///   - orderedIDs: 网格展开顺序的 id（跨 section 平铺）
    ///   - anchor: 长按起点 id
    ///   - target: 当前拖动位置 id
    /// - Returns: anchor 与 target 之间（含两端）的连续 id，保持列表顺序；任一端缺失 → []；
    ///   anchor == target 且存在 → [anchor]；结果去重保序。
    public static func ids(in orderedIDs: [String], from anchor: String, to target: String) -> [String] {
        guard let startIndex = orderedIDs.firstIndex(of: anchor),
              let endIndex = orderedIDs.firstIndex(of: target) else { return [] }
        let range = startIndex <= endIndex ? startIndex...endIndex : endIndex...startIndex
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(range.count)
        for index in range {
            let id = orderedIDs[index]
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }
}
