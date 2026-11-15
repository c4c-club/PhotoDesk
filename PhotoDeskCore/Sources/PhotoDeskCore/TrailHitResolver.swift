// MARK: - 职责说明：指尖线段×cell 扫掠命中（M18 T03，docs/38 §2、docs/37 §4/§7）——
// 「滑到哪选到哪」的 Core 几何：对每个 cell 用 Liang–Barsky/slab 法求线段参数区间 [tEnter,tExit]，
// 命中者按 tEnter 升序（同 t 按 id 升序）输出 id 序列——T05 回滑截断依赖该顺序单调性；
// 反向线段天然产出反向序列（t 区间镜像）。零长度/近垂直（|dx| ≤ epsilon）走逐轴退化分支。
// clipTop：粘性头遮挡区（内容 y < clipTop）不可命中——先把每个 cell 的有效上边抬到
// max(minY, clipTop) 再求交（不是只整格过滤：跨头 cell 的头下部分仍可命中）。
// expansion：单边扩展（贴边/亚 pt 采样误差补扫；负值钳 0）。非法 frame（负宽/非有限）逐个跳过。
// 性能契约：2 万 frame <20ms（纯算术，无散列无分配热点，docs/38 §4）。
// 仅 import Foundation；几何输入全 Double/GridPoint（红线 2）。

import Foundation

public enum TrailHitResolver {

    /// 求线段 from→to 与 cells 的扫掠命中，按经过顺序输出去重 id。
    /// - Parameters:
    ///   - from/to: 指尖线段两端（content 坐标；非有限 → 空序列）
    ///   - cells: 真实 cell frame（非法项跳过）
    ///   - clipTop: 粘性头底边（内容坐标）；非有限视为 nil
    ///   - expansion: 单边扩展 pt；负/非有限钳 0
    ///   - epsilon: 退化分支阈值（|dx|/|dy| ≤ epsilon 视为垂直/水平分量）
    public static func orderedIDs(from: GridPoint,
                                  to: GridPoint,
                                  cells: [GridCellFrame],
                                  clipTop: Double?,
                                  expansion: Double,
                                  epsilon: Double) -> [String] {
        guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite else { return [] }
        let expand = (expansion.isFinite && expansion > 0) ? expansion : 0
        let eps = (epsilon.isFinite && epsilon >= 0) ? epsilon : 0
        let dx = to.x - from.x
        let dy = to.y - from.y
        let verticalLike = abs(dx) <= eps
        let horizontalLike = abs(dy) <= eps

        struct Hit {
            let t: Double
            let id: String
        }
        var hits: [Hit] = []
        hits.reserveCapacity(min(cells.count, 64))

        for cell in cells {
            guard cell.isValid else { continue }
            let minX = cell.minX - expand
            let maxX = cell.maxX + expand
            var minY = cell.minY - expand
            var maxY = cell.maxY + expand
            if let clip = clipTop, clip.isFinite, clip > minY {
                minY = clip                       // 遮挡区抬高有效上边（半裁 cell 仍可命中头下部分）
            }
            if minY > maxY { continue }           // 整格被遮挡

            var tEnter = 0.0
            var tExit = 1.0
            // x slab
            if verticalLike {
                guard from.x >= minX, from.x <= maxX else { continue }
            } else {
                let inv = 1 / dx
                var t0 = (minX - from.x) * inv
                var t1 = (maxX - from.x) * inv
                if t0 > t1 { swap(&t0, &t1) }
                tEnter = max(tEnter, t0)
                tExit = min(tExit, t1)
                if tEnter > tExit { continue }
            }
            // y slab
            if horizontalLike {
                guard from.y >= minY, from.y <= maxY else { continue }
            } else {
                let inv = 1 / dy
                var t0 = (minY - from.y) * inv
                var t1 = (maxY - from.y) * inv
                if t0 > t1 { swap(&t0, &t1) }
                tEnter = max(tEnter, t0)
                tExit = min(tExit, t1)
                if tEnter > tExit { continue }
            }
            hits.append(Hit(t: tEnter, id: cell.id))
        }

        hits.sort { $0.t != $1.t ? $0.t < $1.t : $0.id < $1.id }
        var result: [String] = []
        result.reserveCapacity(hits.count)
        var seen = Set<String>()
        seen.reserveCapacity(hits.count)
        for hit in hits {
            if !seen.insert(hit.id).inserted { continue }   // 同 id 全局去重保序（首个 tMin）
            result.append(hit.id)
        }
        return result
    }
}
