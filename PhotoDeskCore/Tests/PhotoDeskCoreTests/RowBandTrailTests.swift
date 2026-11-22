// MARK: - RowBandTrailTests：路径事务喂入序列与行为矩阵（M19 T03 → M20 T06 重写，docs/49 T06 §2.2）——
// RowBandMap 展开语义（行主序/截断/去重/跨段）保持 M19 锁；组合序列按 M20 T05 控制器喂入策略重写：
// beginTrail 只 consume 单锚点（起手绝不整行）、行模式首帧 rebase 后整段种子一次 consume、
// 续帧喂「orderedIDs − path」、向上 rewind 只 consume 目的行末项（截断到目的行）；
// 旧「首帧整行」断言全部删除（docs/49 T06 §2.2：不得保留为兼容分支）；
// 4 列 5 步矩阵（长按 1 → 右扫 4 → 下拖 8 → 续帧 12 → 左回 10）在 Core 按有序 id 序列锁定
// （XCUI 无法合成同手势多段转向，docs/49 T06 §2.4——连续语义归此处，UI 分段验证）。

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

    // MARK: - 展开：行主序 / 截断 / 去重 / 跨段（RowBandMap 语义，M19 锁保持）

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

    // MARK: - 与 SlideSelectTrail 组合（M20 T05 控制器喂入序列）
    // beginTrail 单锚点 → 行模式首帧整段种子（rebase 同构）→ 续帧喂新带 → 向上 rewind consume([末项])

    func testTrailAnchorStartThenRowSeedAppendsWholeRows() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        XCTAssertEqual(trail.consume(["s0-i0"]).add, ["s0-i0"], "beginTrail 只 consume 锚点一格（起手绝不整行）")
        _ = trail.consume(bandIDs(map, [0, 1, 2]))   // 行模式首帧整段种子（rebase 后同构喂入）
        XCTAssertEqual(trail.target.count, 9, "锚点 + 种子覆盖 3 整行 → target = 9")
        XCTAssertEqual(trail.path, bandIDs(map, [0, 1, 2]), "路径栈 = 种子序，锚点重入按抖动忽略、无重复")
    }

    func testTrailRowUpRewindTruncatesToDestinationRow() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["s0-i0"])
        _ = trail.consume(bandIDs(map, [0, 1, 2]))
        let rewindID = bandIDs(map, [0]).last!   // trailHitTest 向上返回 = 终带（目的行）末项
        let delta = trail.consume([rewindID])
        XCTAssertEqual(delta.remove.count, 6, "向上 rewind 只回退目的行之后的 id（第 2、3 行共 6 格）")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.target.count, 3, "回到目的行 = 3 格")
        XCTAssertEqual(trail.path, bandIDs(map, [0]), "路径栈缩回目的行")
    }

    func testTrailForwardAgainRestoresNineAfterRewind() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["s0-i0"])
        _ = trail.consume(bandIDs(map, [0, 1, 2]))
        _ = trail.consume([bandIDs(map, [0]).last!])   // rewind 到第 1 行
        let delta = trail.consume(bandIDs(map, [1, 2]))   // 续帧再下拖（喂新带）
        XCTAssertEqual(delta.add.count, 6, "再正向按序补选第 2、3 行 6 格")
        XCTAssertEqual(trail.target.count, 9, "恢复 9 格")
        XCTAssertEqual(trail.path.count, 9)
    }

    func testTrailPreSelectedOutsidePathSurvives() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: ["X"], anchorInitiallySelected: false)
        _ = trail.consume(["s0-i0"])
        _ = trail.consume(bandIDs(map, [1, 2]))
        let delta = trail.consume([bandIDs(map, [1]).last!])
        XCTAssertTrue(trail.target.contains("X"), "预选 X（不在路径行内）全程保持")
        XCTAssertFalse(delta.remove.contains("X"))
        XCTAssertFalse(delta.add.contains("X"))
    }

    func testTrailPreSelectedInsideRowSurvivesRewind() {
        let map = makeMap()
        let row1IDs = Set(bandIDs(map, [1]))
        var trail = SlideSelectTrail(base: row1IDs, anchorInitiallySelected: false)
        _ = trail.consume(["s0-i0"])
        let d1 = trail.consume(bandIDs(map, [1]))
        XCTAssertTrue(d1.add.isEmpty, "预选 Y（路径行内且 base 已含）入选无净差")
        let d2 = trail.consume([bandIDs(map, [1]).last!])   // rewind 到第 1 行末项
        XCTAssertFalse(d2.remove.contains("s0-i3"), "回卷后 Y 回 base 态仍保持选中")
        XCTAssertEqual(trail.target, row1IDs.union(["s0-i0"]), "Y 全程保持 + 已喂入的第 1 行格保持")
    }

    // MARK: - deselect 模式（起手已选：锚点即取消、种子续喂、rewind 恢复）

    func testDeselectModeRemovesRowsAndRewindRestores() {
        let map = makeMap()
        let allNine = Set(bandIDs(map, [0, 1, 2]))
        var trail = SlideSelectTrail(base: allNine, anchorInitiallySelected: true)
        XCTAssertEqual(trail.mode, .deselect)
        let d0 = trail.consume(["s0-i0"])
        XCTAssertEqual(d0.remove, ["s0-i0"], "deselect：beginTrail 单锚点即取消")
        _ = trail.consume(bandIDs(map, [0, 1, 2]))   // 行模式首帧种子
        XCTAssertTrue(trail.target.isEmpty, "滑过 3 行全取消")
        let dBack = trail.consume([bandIDs(map, [0]).last!])   // rewind 到第 1 行末项
        XCTAssertEqual(dBack.add, Set(bandIDs(map, [1, 2])), "向上回卷恢复第 2、3 行（base 态）")
        XCTAssertEqual(trail.target, allNine.subtracting(bandIDs(map, [0])), "第 1 行保持取消、第 2、3 行恢复")
    }

    // MARK: - scope 过滤（trail consume 层，docs/42 §10.1）

    func testTrailScopeFiltersOutOfScopeRowItems() {
        let map = makeMap()
        let scope: Set<String> = ["s0-i0", "s0-i1", "s0-i2", "s0-i3", "s0-i4", "s0-i5"]
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false, scope: scope)
        _ = trail.consume(["s0-i0"])
        _ = trail.consume(bandIDs(map, [0, 1, 2]))
        XCTAssertEqual(trail.target, scope, "行带含 scope 外 item 时：scope 内正常入选、scope 外永不入选")
        XCTAssertEqual(trail.path.count, 6, "scope 外 id 不入路径栈")
    }

    // MARK: - 快速跨带（续帧单帧多行带）

    func testFastTwoBandCrossInOneConsume() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["s0-i0"])
        let delta = trail.consume(bandIDs(map, [1, 2]))   // 续帧喂新带（控制器已过滤 path 内 id）
        XCTAssertEqual(delta.add.count, 6, "续帧一帧跨 2 个新行带（快拖）按序补选 6 格")
        XCTAssertEqual(trail.target.count, 7, "锚点 + 2 行 = 7")
        XCTAssertEqual(trail.path, ["s0-i0"] + bandIDs(map, [1, 2]), "路径栈 = 锚点 + 新带平铺序（锚点重入抖动忽略、不重复）")
    }

    // MARK: - 行为矩阵边界（M19 T06 → M20 T06 喂入序列重写）

    /// ① 回滑跨 section：锚点 + 第 2 月两行 → rewind 到第 1 月末行 → 第 2 月整段撤销（4+3 格）。
    func testTrailBackslideAcrossSectionRevokesWholeSection() {
        let map = makeMap()
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["s0-i9"])           // 第 1 月末行锚点
        _ = trail.consume(bandIDs(map, [4]))   // 第 2 月首行
        _ = trail.consume(bandIDs(map, [5]))   // 第 2 月末行
        XCTAssertEqual(trail.target.count, 8, "锚点 + 4 + 3 = 8 格")
        let delta = trail.consume(["s0-i9"])   // rewind 到第 1 月末行
        XCTAssertEqual(delta.remove.count, 7, "第 2 月两个行带整段撤销")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.target, Set(bandIDs(map, [3])), "只剩第 1 月末行")
        XCTAssertEqual(trail.path, ["s0-i9"], "路径栈同步收缩到锚点")
    }

    /// ② 取消模式 base 只含整行部分格：锚点即取消、种子续喂只移除 base 内格。
    func testDeselectPartialBaseRowRemovesOnlyBaseCells() {
        let map = makeMap()
        let partial: Set<String> = ["s0-i0", "s0-i2"]
        var trail = SlideSelectTrail(base: partial, anchorInitiallySelected: true)
        XCTAssertEqual(trail.mode, .deselect)
        let d0 = trail.consume(["s0-i0"])
        XCTAssertEqual(d0.remove, ["s0-i0"])
        let d1 = trail.consume(bandIDs(map, [0]))
        XCTAssertEqual(d1.remove, ["s0-i2"], "种子续喂只移除 base 内剩余格")
        XCTAssertTrue(d1.add.isEmpty, "行内未选格不得新增（取消模式不反向选）")
        XCTAssertTrue(trail.target.isEmpty, "target = base − 行带∩base")
    }

    /// ③ 起手行已全选（deselect）：种子全取消后 rewind 恢复第 2 行。
    func testDeselectFullRowsBackslideRestoresRow() {
        let map = makeMap()
        let base = Set(bandIDs(map, [0, 1]))
        var trail = SlideSelectTrail(base: base, anchorInitiallySelected: true)
        _ = trail.consume(["s0-i0"])
        _ = trail.consume(bandIDs(map, [0, 1]))
        XCTAssertTrue(trail.target.isEmpty, "两行全取消")
        let delta = trail.consume([bandIDs(map, [0]).last!])   // rewind 到第 1 行末项
        XCTAssertEqual(delta.add, Set(bandIDs(map, [1])), "第 2 行整行恢复（base 态）")
        XCTAssertEqual(trail.target, Set(bandIDs(map, [1])), "第 1 行保持取消、第 2 行恢复")
    }

    /// ④ 单月 scope：跨月单帧（第 1 月末行 + 第 2 月首行）只展开并入选当月 item。
    func testMonthScopeSingleFrameCrossSectionOnlyScopedItems() {
        let map = makeMap()
        let scope = Set(bandIDs(map, [4, 5]))   // 第 2 月全量
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false, scope: scope)
        let delta = trail.consume(bandIDs(map, [3, 4]))   // 跨月单帧（帧命中展开，scope 在 trail 层过滤）
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

    // MARK: - M20 T06：4 列 5 步矩阵（连续喂入 Core 锁，docs/49 T06 §2.2/§2.4）

    /// 4 列 × 3 行 12 格（s0-i0..i11）。5 段有序喂入复现用户矩阵：
    /// 长按 (1,1) = 1 → 右扫 (1,4) = 4 → 下拖 (2,4) = 8（首帧 rebase + 种子）→
    /// 续帧 (3,4) = 12 → 左回 (3,2) = 10（path 回卷截断）；路径栈全程无重复。
    func testFourColumnFiveStepMatrixCounts() {
        let ids = (0..<12).map { "s0-i\($0)" }
        let row = { (r: Int) in Array(ids[(r * 4)..<((r + 1) * 4)]) }
        // ① beginTrail 单锚点（长按 (1,1)）
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        XCTAssertEqual(trail.consume([ids[0]]).add, Set([ids[0]]), "① 长按 (1,1) → 1")
        // ② cells 横扫 (1,1)→(1,4)：锚点重入抖动忽略、新格按序入栈
        XCTAssertEqual(trail.consume(row(0)).add.count, 3, "② 右扫第 1 行 → 4")
        // ③ rows 下拖 (1,4)→(2,4)：控制器首帧 rebase（base = 当前 target）+ 整段种子
        trail = SlideSelectTrail(base: trail.target, anchorInitiallySelected: false)
        XCTAssertEqual(trail.consume(row(0) + row(1)).add.count, 4, "③ 下拖 1 行 → 8")
        // ④ rows 续帧 (2,4)→(3,4)：喂 orderedIDs − path（第 3 行 4 格）
        let remaining = row(2).filter { !trail.path.contains($0) }
        XCTAssertEqual(remaining, row(2), "续帧过滤不误伤新行")
        XCTAssertEqual(trail.consume(remaining).add.count, 4, "④ 续帧第 3 行 → 12")
        // ⑤ cells 左回 (3,4)→(3,2)：已访问 id 重入触发回卷截断（12 → 10）
        let d5 = trail.consume([ids[11], ids[10], ids[9]])
        XCTAssertEqual(d5.remove, Set([ids[11], ids[10]]), "⑤ 左回只出栈尾部 2 格")
        XCTAssertTrue(d5.add.isEmpty)
        XCTAssertEqual(trail.target.count, 10, "⑤ 左回 → 10")
        XCTAssertEqual(trail.path.count, 10)
        XCTAssertEqual(trail.path, Array(ids[0..<10]), "路径栈 = 前 10 格有序，无重复")
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
