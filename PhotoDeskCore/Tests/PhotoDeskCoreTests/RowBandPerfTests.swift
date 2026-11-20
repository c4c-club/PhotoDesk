// MARK: - RowBandPerfTests：M19 T07 性能测量（docs/42 §5 预算的 Core 侧口径）——
// Docker `swift test` 为 debug 构建（-Onone）：闸门按 M18 T02/T03 先例取绝对回归闸 <20ms；
// docs/42 §5 的 iPhone 11 预算（单帧行带解析 ≤2ms、单帧展开+applyDelta ≤4ms）以本测试
// 输出的 p50/p95 留痕（"T07-PERF" 行，供 artifacts/audit/m19/t07/perf.txt 采集），
// 真机复测（T09）与 iOS release 口径为准。运行环境差异写入 docs/05 变更记录。

import XCTest
@testable import PhotoDeskCore

final class RowBandPerfTests: XCTestCase {

    /// 40 段 × 500 项（2 万 item）× 4 列 × 120pt 行高（与 RowBandMapTests 预算用例同规模）
    private func makeMap() -> RowBandMap {
        var sections: [RowBandSection] = []
        for s in 0..<40 {
            sections.append(RowBandSection(section: s, itemCount: 500, columns: 4, rowHeight: 120,
                                           firstRowMinY: Double(100 + s * 20_240), headerHeight: 48))
        }
        return RowBandMap(sections: sections)
    }

    private func percentile(_ samples: [Double], _ p: Double) -> Double {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return -1 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.up)) - 1))
        return sorted[index]
    }

    private func ms(_ duration: ContinuousClock.Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// 单帧行带解析（bandIndex + bandSequence + 整行展开）与 SelectionState.applyDelta
    /// 的 p50/p95：600 帧随机视口采样（每帧 4 行带 ≈ 一帧拖拽的最大跨度）。
    func testRowBandParseExpandAndApplyDeltaBudgets() {
        let map = makeMap()
        let totalRows = map.count
        XCTAssertEqual(totalRows, 40 * 125, "2 万 item ÷ 4 列 = 5000 行带")
        var parse: [Double] = []
        var apply: [Double] = []
        parse.reserveCapacity(600)
        apply.reserveCapacity(600)
        // 预热：首次 bandIndex 含平铺数组冷启动，不计入样本
        _ = map.bandIndex(atContentY: 10_000, clipTop: 48)
        var scope = Set<String>(minimumCapacity: 20_000)
        for i in 0..<20_000 { scope.insert("asset-\(i)") }
        var state = SelectionState()
        state.begin(scope: scope, initial: nil)
        state.selectAll()
        for i in 0..<600 {
            let y = Double(120 + (i * 7919) % 970_000)
            let t0 = ContinuousClock.now
            let band = map.bandIndex(atContentY: y, clipTop: 48) ?? 0
            let to = min(totalRows - 1, band + 3)
            let sequence = map.bandSequence(from: band, to: to)
            let items = map.items(forBandIndices: sequence)
            parse.append(ms(ContinuousClock.now - t0))
            let globalIDs = Set(items.map { "asset-\($0.section * 500 + $0.item)" })
            XCTAssertFalse(globalIDs.isEmpty, "整行展开不得为空")
            let t1 = ContinuousClock.now
            state.applyDelta(add: [], remove: globalIDs)
            let applyMs = ms(ContinuousClock.now - t1)
            state.applyDelta(add: globalIDs, remove: [])   // 还原全选，下一帧同口径
            apply.append(applyMs)
        }
        let parseP50 = percentile(parse, 0.5)
        let parseP95 = percentile(parse, 0.95)
        let applyP50 = percentile(apply, 0.5)
        let applyP95 = percentile(apply, 0.95)
        print("T07-PERF parse+expand p50=\(String(format: "%.3f", parseP50))ms p95=\(String(format: "%.3f", parseP95))ms | "
            + "applyDelta p50=\(String(format: "%.3f", applyP50))ms p95=\(String(format: "%.3f", applyP95))ms | "
            + "samples=\(parse.count) | budget(iPhone11): parse<=2ms expand+applyDelta<=4ms (debug/Docker 口径)")
        XCTAssertLessThan(parseP95, 20, "单帧行带解析+展开绝对回归闸 <20ms（Docker debug；docs/42 §5 预算真机口径）")
        XCTAssertLessThan(applyP95, 20, "applyDelta 绝对回归闸 <20ms（Docker debug；docs/42 §5 预算真机口径）")
    }
}
