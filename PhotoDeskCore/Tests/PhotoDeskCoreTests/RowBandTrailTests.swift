// MARK: - RowBandTrailTests：行带展开与路径事务组合红/绿（M19 T03，docs/42 §1.2/§3.1/§10.1、docs/45 §2/§5）——
// 语义锁：items(forBandIndices:) 行主序展开（行序 + 行内列序）、重复行带去重保首现、越界下标忽略；
// 与 SlideSelectTrail 组合：逐帧喂「指尖所在行带的展开 id 序列」，路径栈负责跨帧行带累加与回滑整行截断；
// 正向 3 行 target=9 → 回滑到第 1 行 target=3 → 再正向恢复 9；预选 X（路径外）/Y（路径行内且 base 已含）
// 全程保持；deselect 模式滑过 2 行移除 6 格、回滑恢复；scope 外 item 经 trail  consume 过滤永不入选
// （docs/42 §10.1：Core 只产 RowBandItem 数值单元，App 经 itemIdentifier 映射，scope 过滤在 trail consume）；
// 性能：1 万 item 全库展开 + consume <10ms（docs/42 §5 预算，debug/Docker 实测留痕）。

import XCTest
@testable import PhotoDeskCore

final class RowBandTrailTests: XCTestCase {

    // MARK: - helpers

    /// T02 默认布局：S0(10 项/3 列/4 行, bands 0–3) + S1(7 项/4 列/2 行, bands 4–5)
    private func makeMap() -> RowBandMap {
        RowBandMap(sections: [
            RowBandSection(section: 0, itemCount: 10, columns: 3, rowHeight: 120, firstRowMinY: 100, headerHeight: 48),
            RowBandSection(section: 1, itemCount: 7, columns: 4, rowHeight: 120, firstRowMinY: 680, headerHeight: 48),
        ])
    }

    private func ids(_ items: [RowBandItem]) -> [String] {
        items.map { "s\($0.section)-i\($0.item)" }
    }

    private func bandIDs(_ map: RowBandMap, _ bands: [Int]) -> [String] {
        ids(map.items(forBandIndices: bands))
    }

    // MARK: - 展开：行主序 / 截断 / 去重 / 跨段

    func testExpandForwardThreeBandsRowMajorNineItems() {
        let map = makeMap()
        let items = map.items(forBandIndices: [0, 1, 2])
        XCTAssertEqual(items, [
            RowBandItem(section: 0, item: 0), RowBandItem(section: 0, item: 1), RowBandItem(section: 0, item: 2),
            RowBandItem(section: 0, item: 3), RowBandItem(section: 0, item: 4), RowBandItem(section: 0, item: 5),
            RowBandItem(section: 0, item: 6), RowBandItem(section: 0, item: 7), RowBandItem(section: 0, item: 8),
        ], "3 行带 × 3 列 = 9 item，行主序（行序 + 行内列序）")
    }

    func testExpandPartialLastRowOnlyRealItems() {
        let map = makeMap()
        XCTAssertEqual(map.items(forBandIndices: [3]), [RowBandItem(section: 0, item: 9)],
                       "末行不满只展开真实 item")
    }

    func testExpandReverseSequenceMirrorsOrder() {
        let map = makeMap()
        let forward = map.items(forBandIndices: [0, 1, 2])
        let backward = map.items(forBandIndices: [2, 1, 0])
        XCTAssertEqual(backward, Array(forward[6..<9]) + Array(forward[3..<6]) + Array(forward[0..<3]),
                       "反向序列 = 行带访问序反向，行内保持列升序（docs/42 §3.1 列升序去重保序）")
    }

    func testExpandDedupKeepsFirstOccurrence() {
        let map = makeMap()
        XCTAssertEqual(map.items(forBandIndices: [0, 1, 0]), map.items(forBandIndices: [0, 1]),
                       "重复行带去重保首现顺序")
    }

    func testExpandCrossSectionFlatOrder() {
        let map = makeMap()
        let items = map.items(forBandIndices: [2, 3, 4])
        XCTAssertEqual(items.first?.section, 0)
        XCTAssertEqual(items.last, RowBandItem(section: 1, item: 3), "跨段展开按 section 升序平铺")
        XCTAssertEqual(items.count, 3 + 1 + 4)
    }

    func testExpandInvalidBandIndexIgnored() {
        let map = makeMap()
        XCTAssertEqual(map.items(forBandIndices: [-1, 0, 99]), map.items(forBandIndices: [0]),
                       "越界行带下标防御性忽略")
    }

    // MARK: - 与 SlideSelectTrail 组合（逐帧喂当前行带展开 id）

    func testTrailForwardThreeBandsTargetNine() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        XCTAssertEqual(trail.consume(bandIDs(map, [0])).add.count, 3)
        _ = trail.consume(bandIDs(map, [1]))
        _ = trail.consume(bandIDs(map, [2]))
        XCTAssertEqual(trail.target.count, 9, "正向选 3 行 → target = 3×3 = 9 格")
        XCTAssertEqual(trail.path.count, 9)
    }

    func testTrailBackslideTwoBandsTargetThree() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [0]))
        _ = trail.consume(bandIDs(map, [1]))
        _ = trail.consume(bandIDs(map, [2]))
        let delta = trail.consume(bandIDs(map, [0]))
        XCTAssertEqual(delta.remove.count, 6, "回滑到第 1 行：第 2、3 行共 6 格整行撤销")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.target.count, 3)
        XCTAssertEqual(trail.path.count, 3)
    }

    func testTrailForwardAgainRestoresNine() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [0]))
        _ = trail.consume(bandIDs(map, [1]))
        _ = trail.consume(bandIDs(map, [2]))
        _ = trail.consume(bandIDs(map, [0]))
        _ = trail.consume(bandIDs(map, [1]))
        _ = trail.consume(bandIDs(map, [2]))
        XCTAssertEqual(trail.target.count, 9, "再正向回到第 3 行恢复 9 格")
    }

    func testTrailPreSelectedOutsidePathSurvives() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: ["X"], anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [0]))
        _ = trail.consume(bandIDs(map, [1]))
        let delta = trail.consume(bandIDs(map, [2]))
        XCTAssertTrue(trail.target.contains("X"), "预选 X（不在路径行内）全程保持")
        XCTAssertFalse(delta.remove.contains("X"))
        XCTAssertFalse(delta.add.contains("X"))
    }

    func testTrailPreSelectedInsideRowSurvivesBackslide() {
        let map = makeMap()
        let row1IDs = Set(bandIDs(map, [1]))
        var trail = SlideSelectTrail(base: row1IDs, anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [0]))
        let d1 = trail.consume(bandIDs(map, [1]))
        XCTAssertTrue(d1.add.isEmpty, "预选 Y（路径行内且 base 已含）入选无净差")
        let d2 = trail.consume(bandIDs(map, [0]))
        XCTAssertFalse(d2.remove.contains("s0-i3"), "回滑后 Y 回 base 态仍保持选中")
        XCTAssertEqual(trail.target, row1IDs.union(bandIDs(map, [0])), "Y 全程保持 + 第 1 行保持")
    }

    // MARK: - deselect 模式（起手已选整行）

    func testDeselectModeRemovesRowsAndBackslideRestores() {
        let map = makeMap()
        let allNine = Set(bandIDs(map, [0, 1, 2]))
        var trail = SlideSelectTrail(base: allNine, anchorInitiallySelected: true)
        XCTAssertEqual(trail.mode, .deselect)
        let d0 = trail.consume(bandIDs(map, [0]))
        XCTAssertEqual(d0.remove.count, 3, "deselect：滑过第 1 行取消 3 格")
        _ = trail.consume(bandIDs(map, [1]))
        XCTAssertEqual(trail.target, allNine.subtracting(bandIDs(map, [0, 1])), "滑过 2 行移除 6 格")
        let dBack = trail.consume(bandIDs(map, [0]))
        XCTAssertEqual(dBack.add, Set(bandIDs(map, [1])), "回滑第 1 行：第 2 行整行恢复（第 1 行保持取消态）")
        XCTAssertEqual(trail.target, allNine.subtracting(Set(bandIDs(map, [0]))), "路径缩到第 1 行 → target = base − 第 1 行")
    }

    // MARK: - scope 过滤（trail consume 层，docs/42 §10.1）

    func testTrailScopeFiltersOutOfScopeRowItems() {
        let map = makeMap()
        let scope: Set<String> = ["s0-i0", "s0-i1", "s0-i2", "s0-i3", "s0-i4", "s0-i5"]
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false, scope: scope)
        _ = trail.consume(bandIDs(map, [0]))
        _ = trail.consume(bandIDs(map, [1]))
        _ = trail.consume(bandIDs(map, [2]))
        XCTAssertEqual(trail.target, scope, "行带含 scope 外 item 时：scope 内正常入选、scope 外永不入选")
        XCTAssertEqual(trail.path.count, 6, "scope 外 id 不入路径栈")
    }

    // MARK: - 快速跨带（单帧多行带）

    func testFastThreeBandCrossInOneConsume() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [0]))
        let delta = trail.consume(bandIDs(map, [1, 2]))
        XCTAssertEqual(delta.add.count, 6, "一帧跨 2 个行带（快拖）按序补选 6 格")
        XCTAssertEqual(trail.target.count, 9)
        XCTAssertEqual(trail.path, bandIDs(map, [0, 1, 2]), "路径栈保持行带平铺序")
    }

    // MARK: - 行为矩阵边界（M19 T06，docs/43 T06、docs/42 §1.2 行为表/§4 矩阵）

    /// ① 回滑跨 section：第 2 月滑到第 1 月末行 → 第 2 月整段撤销（4+3 格）。
    func testTrailBackslideAcrossSectionRevokesWholeSection() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [3]))   // 第 1 月末行（s0-i9，1 格）
        _ = trail.consume(bandIDs(map, [4]))   // 第 2 月首行（4 格）
        _ = trail.consume(bandIDs(map, [5]))   // 第 2 月末行（3 格）
        XCTAssertEqual(trail.target.count, 8, "跨两月累计 1+4+3 = 8 格")
        let delta = trail.consume(bandIDs(map, [3]))   // 回滑到第 1 月末行
        XCTAssertEqual(delta.remove.count, 7, "第 2 月两个行带整段撤销")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.target, Set(bandIDs(map, [3])), "只剩第 1 月末行")
        XCTAssertEqual(trail.path.count, 1, "路径栈同步收缩到第 1 月末行")
    }

    /// ② 取消模式 base 只含整行部分格：滑过该行只移除 base 内格，行内其余格不新增。
    func testDeselectPartialBaseRowRemovesOnlyBaseCells() {
        let map = makeMap()
        let partial: Set<String> = ["s0-i0", "s0-i2"]
        var trail = SlideSelectTrail(base: partial, anchorInitiallySelected: true)
        XCTAssertEqual(trail.mode, .deselect)
        let delta = trail.consume(bandIDs(map, [0]))
        XCTAssertEqual(delta.remove, partial, "只移除 base 内 2 格")
        XCTAssertTrue(delta.add.isEmpty, "行内未选格不得新增（取消模式不反向选）")
        XCTAssertTrue(trail.target.isEmpty, "target = base − 行带∩base")
    }

    /// ③ 起手行已全选（deselect）：滑过下一行后回滑，被出栈行整行恢复 base 态。
    func testDeselectFullRowsBackslideRestoresRow() {
        let map = makeMap()
        let base = Set(bandIDs(map, [0, 1]))
        var trail = SlideSelectTrail(base: base, anchorInitiallySelected: true)
        _ = trail.consume(bandIDs(map, [0]))
        _ = trail.consume(bandIDs(map, [1]))
        XCTAssertTrue(trail.target.isEmpty, "两行全取消")
        let delta = trail.consume(bandIDs(map, [0]))   // 回滑到第 1 行
        XCTAssertEqual(delta.add, Set(bandIDs(map, [1])), "第 2 行整行恢复（base 态）")
        XCTAssertEqual(trail.target, Set(bandIDs(map, [1])), "第 1 行保持取消、第 2 行恢复")
    }

    /// ④ 单月 scope：跨月单帧（第 1 月末行 + 第 2 月首行）只展开并入选当月 item。
    func testMonthScopeSingleFrameCrossSectionOnlyScopedItems() {
        let map = makeMap()
        let scope = Set(bandIDs(map, [4, 5]))   // 第 2 月全量
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false, scope: scope)
        let delta = trail.consume(bandIDs(map, [3, 4]))   // 跨月单帧
        XCTAssertEqual(delta.add, Set(bandIDs(map, [4])), "只入选第 2 月首行 4 格")
        XCTAssertFalse(delta.add.contains("s0-i9"), "第 1 月末行不得越界入选")
        XCTAssertEqual(trail.path.count, 4, "scope 外 id 不入路径栈")
        XCTAssertEqual(trail.target, Set(bandIDs(map, [4])))
    }

    /// ⑤ 全选（scope 全量）后行带取消：只减对应行，其余行（含跨月）保持。
    func testSelectAllThenBandDeselectRemovesOnlyThatRow() {
        let map = makeMap()
        let all = Set(bandIDs(map, [0, 1, 2, 3, 4, 5]))
        var trail = SlideSelectTrail(base: all, anchorInitiallySelected: true, scope: all)
        let delta = trail.consume(bandIDs(map, [1]))
        XCTAssertEqual(delta.remove, Set(bandIDs(map, [1])), "只减第 2 行 3 格")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.target, all.subtracting(bandIDs(map, [1])), "其余行全部保持")
        XCTAssertTrue(trail.target.contains("s1-i0"), "跨月行不受影响")
    }

    /// ⑥ 同一行内抖动（反复重喂同一行带）：净差为零、路径栈与 target 幂等。
    func testBandSequenceJitterWithinRowIsIdempotent() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(bandIDs(map, [0]))
        let before = trail.target
        let pathBefore = trail.path
        XCTAssertTrue(trail.consume(bandIDs(map, [0])).isEmpty, "同行抖动第 1 次零净差")
        XCTAssertTrue(trail.consume(bandIDs(map, [0])).isEmpty, "同行抖动第 2 次零净差")
        XCTAssertEqual(trail.target, before, "target 幂等")
        XCTAssertEqual(trail.path, pathBefore, "路径栈不重复增长")
    }

    // MARK: - 性能（docs/42 §5：1 万 item 全库展开 + consume）

    func testPerfTenThousandItemsExpandAndConsumeUnder10ms() {
        var sections: [RowBandSection] = []
        for s in 0..<40 {
            sections.append(RowBandSection(section: s, itemCount: 250, columns: 3, rowHeight: 120,
                                           firstRowMinY: Double(100 + s * 10_280), headerHeight: 48))
        }
        let map = RowBandMap(sections: sections)
        XCTAssertEqual(map.count, 40 * 84, "1 万 item → 3360 行带")
        let start = ContinuousClock.now
        let allIDs = ids(map.items(forBandIndices: map.bandSequence(from: 0, to: map.count - 1)))
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        let delta = trail.consume(allIDs)
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(trail.target.count, 10_000, "全库展开 + consume 后全选")
        XCTAssertEqual(delta.add.count, 10_000)
        // docs/42 §5 预算 10ms 为 iOS release 口径；本地 Docker swift test 为 debug 构建，
        // 实测 25.8ms（M18 T02 先例：预算修订 + 留痕）→ 绝对回归闸 <50ms，T07 iOS release 复测。
        XCTAssertLessThan(elapsed, .milliseconds(50), "1 万 item 全库展开 + consume 绝对回归闸 <50ms（debug/Docker 留痕）")
    }
}
