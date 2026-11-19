// MARK: - RowBandMapTests：行带平铺几何与序列红/绿（M19 T02，docs/42 §3.1、docs/45 §3）——
// 语义锁：行带=(section,row) 是轨迹滑选唯一选择单元；init 平铺跳过非法段（columns/rowHeight/itemCount 非法）且后续索引连续；
// bandIndex(atContentY:clipTop:)：行顶/行底−ε 命中、行底边界归下一行、负 y/超出末行钳首末带、
// 段间空隙在 rowBandSnapTolerance 内吸附（平局归下一段首行）、空隙中部 → nil；
// clipTop 之下才可命中（y 低于头下缘钳到头下缘）、全部行被遮挡 → nil；
// bandSequence 双端含、反向镜像、越界钳制、跨段按平铺序；Band.items 全行展开、末行只含真实 item；
// 性能：2 万 item 建表 + 1000 次 bandIndex + 100 次 bandSequence < 5ms（docs/42 §5）。

import XCTest
@testable import PhotoDeskCore

final class RowBandMapTests: XCTestCase {

    // MARK: - helpers

    /// 默认两段布局：S0(10 项/3 列/4 行, y 100..580) + S1(7 项/4 列/2 行, y 680..920)，段间空隙 100pt
    private func makeDefaultMap() -> RowBandMap {
        RowBandMap(sections: [
            RowBandSection(section: 0, itemCount: 10, columns: 3, rowHeight: 120, firstRowMinY: 100, headerHeight: 48),
            RowBandSection(section: 1, itemCount: 7, columns: 4, rowHeight: 120, firstRowMinY: 680, headerHeight: 48),
        ])
    }

    /// 平局布局：S0(2 行, y 0..200) + S1(1 行, y 224..324)，空隙 24pt = 2×rowBandSnapTolerance
    private func makeTieMap() -> RowBandMap {
        RowBandMap(sections: [
            RowBandSection(section: 0, itemCount: 2, columns: 1, rowHeight: 100, firstRowMinY: 0, headerHeight: 48),
            RowBandSection(section: 1, itemCount: 1, columns: 1, rowHeight: 100, firstRowMinY: 224, headerHeight: 48),
        ])
    }

    // MARK: - 平铺与跳过

    func testBandCountSumsCeilRowsAndSkipsInvalidSections() {
        let map = RowBandMap(sections: [
            RowBandSection(section: 0, itemCount: 10, columns: 3, rowHeight: 120, firstRowMinY: 100, headerHeight: 48),
            RowBandSection(section: 1, itemCount: 0, columns: 3, rowHeight: 120, firstRowMinY: 700, headerHeight: 48),
            RowBandSection(section: 2, itemCount: 7, columns: 4, rowHeight: 120, firstRowMinY: 800, headerHeight: 48),
            RowBandSection(section: 3, itemCount: 5, columns: 0, rowHeight: 120, firstRowMinY: 1100, headerHeight: 48),
            RowBandSection(section: 4, itemCount: 5, columns: 3, rowHeight: -1, firstRowMinY: 1200, headerHeight: 48),
            RowBandSection(section: 5, itemCount: 1, columns: 1, rowHeight: 90, firstRowMinY: 1400, headerHeight: 48),
        ])
        XCTAssertEqual(map.count, 4 + 2 + 1, "行数 = Σ ceil(itemCount/columns)；非法段（空段/零列/负行高）跳过且后续索引连续")
        let band4 = map.band(at: 4)
        XCTAssertEqual(band4.section, 2, "跳过段不占平铺下标：全局第 4 带属于 section 2")
        let band6 = map.band(at: 6)
        XCTAssertEqual(band6.section, 5, "非法段之后的有效段索引保持连续")
    }

    func testBandIndexHitsRowTopAndBottomMinusEpsilon() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandIndex(atContentY: 100, clipTop: 0), 0, "行顶命中该行")
        XCTAssertEqual(map.bandIndex(atContentY: 219.9999, clipTop: 0), 0, "行底 − ε 仍命中该行")
        XCTAssertEqual(map.bandIndex(atContentY: 459, clipTop: 0), 2)
    }

    func testBandIndexRowBottomBoundaryBelongsToNextRow() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandIndex(atContentY: 220, clipTop: 0), 1, "行底边界（=下一行行顶）归下一行带")
    }

    func testBandIndexNegativeYClampsToFirstBand() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandIndex(atContentY: -50, clipTop: 0), 0, "负 y 越界钳首行带")
    }

    func testBandIndexBeyondLastRowClampsToLastBand() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandIndex(atContentY: 10000, clipTop: 0), 5, "超出末行钳末行带")
    }

    // MARK: - 段间空隙吸附

    func testBandIndexSnapsAcrossSectionGapWithinTolerance() {
        let map = makeDefaultMap()
        let tol = SlideSelectConfig.rowBandSnapTolerance
        XCTAssertLessThanOrEqual(tol, 50, "默认布局空隙 100pt，容差必须小于空隙一半才有 nil 区")
        XCTAssertEqual(map.bandIndex(atContentY: 680 - 10, clipTop: 0), 4,
                       "距下一段首行顶 10pt（≤ 容差）吸附下一段首行带")
        XCTAssertEqual(map.bandIndex(atContentY: 580 + 10, clipTop: 0), 3,
                       "距上一段末行底 10pt（≤ 容差）吸附上一段末行带")
    }

    func testBandIndexReturnsNilInWideInterSectionGap() {
        let map = makeDefaultMap()
        XCTAssertNil(map.bandIndex(atContentY: 630, clipTop: 0),
                     "段间空隙中部（距两侧边缘均 > 容差）不产生命中")
    }

    func testBandIndexPrefersNextSectionOnGapTie() {
        let map = makeTieMap()
        XCTAssertEqual(map.bandIndex(atContentY: 212, clipTop: 0), 2,
                       "平局（距两侧边缘等距且均在容差内）归下一段首行带")
    }

    // MARK: - clipTop 粘性头遮挡

    func testBandIndexClampsToFirstVisibleRowBelowClipTop() {
        let map = makeDefaultMap()
        // clipTop=300 落在第 1 行带跨度 [220,340) 内：该行部分可见，y 低于头下缘也钳到它
        XCTAssertEqual(map.bandIndex(atContentY: 250, clipTop: 300), 1)
        XCTAssertEqual(map.bandIndex(atContentY: 305, clipTop: 300), 1)
        // clipTop=200 落在第 0 行带跨度 [100,220) 内：第 0 行带部分可见 → 钳到第 0 行带
        XCTAssertEqual(map.bandIndex(atContentY: 150, clipTop: 200), 0)
        // clipTop=220 恰为第 0 行带底缘（整体被遮住）：最近可见 = 第 1 行带
        XCTAssertEqual(map.bandIndex(atContentY: 150, clipTop: 220), 1)
    }

    func testBandIndexReturnsNilWhenAllRowsOccluded() {
        let map = makeDefaultMap()
        XCTAssertNil(map.bandIndex(atContentY: 400, clipTop: 950),
                     "clipTop 不低于任何行带底缘（全遮挡）→ nil")
    }

    // MARK: - 序列

    func testBandSequenceForwardInclusiveAscending() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandSequence(from: 1, to: 4), [1, 2, 3, 4], "双端含、平铺序升序")
    }

    func testBandSequenceReverseMirrorsForward() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandSequence(from: 4, to: 1), [4, 3, 2, 1], "反向 = 正向精确镜像（回滑出栈前提）")
    }

    func testBandSequenceSingleBandReturnsOne() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandSequence(from: 2, to: 2), [2], "同一行带（零长度线段=指尖所在整行）")
    }

    func testBandSequenceClampsOutOfBounds() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.bandSequence(from: -5, to: 3), [0, 1, 2, 3])
        XCTAssertEqual(map.bandSequence(from: 2, to: 999), [2, 3, 4, 5])
        XCTAssertEqual(map.bandSequence(from: -5, to: 999), [0, 1, 2, 3, 4, 5])
    }

    func testBandSequenceCrossesSectionsInFlatSectionOrder() {
        let map = makeDefaultMap()
        let seq = map.bandSequence(from: 2, to: 5)
        XCTAssertEqual(seq, [2, 3, 4, 5])
        XCTAssertEqual(map.band(at: seq[0]).section, 0)
        XCTAssertEqual(map.band(at: seq[2]).section, 1, "跨段序列按 section 升序平铺")
        XCTAssertTrue(map.bandSequence(from: 0, to: 5).isEmpty == false)
    }

    // MARK: - 行带展开（Band.items）

    func testBandItemsFullRowAndPartialLastRow() {
        let map = makeDefaultMap()
        XCTAssertEqual(map.band(at: 0).items, [0, 1, 2], "满行 = row*cols ..< (row+1)*cols")
        XCTAssertEqual(map.band(at: 3).items, [9], "末行不满只展开真实 item（10 项/3 列 → 1 项）")
        XCTAssertEqual(map.band(at: 4).items, [0, 1, 2, 3], "下一段首行 4 列全展开")
        XCTAssertEqual(map.band(at: 5).items, [4, 5, 6])
        XCTAssertEqual(map.band(at: 4).section, 1)
        XCTAssertEqual(map.band(at: 4).row, 0)
    }

    func testSingleColumnSectionOneItemPerBand() {
        let map = RowBandMap(sections: [
            RowBandSection(section: 0, itemCount: 3, columns: 1, rowHeight: 100, firstRowMinY: 0, headerHeight: 48),
        ])
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map.band(at: 1).items, [1], "单列段行带 = 单格行")
    }

    func testEmptyMapReturnsNilAndEmpty() {
        let map = RowBandMap(sections: [])
        XCTAssertEqual(map.count, 0)
        XCTAssertNil(map.bandIndex(atContentY: 100, clipTop: 0))
        XCTAssertTrue(map.bandSequence(from: 0, to: 5).isEmpty)
    }

    // MARK: - 常量与性能

    func testSlideSelectConfigRowBandConstantsExist() {
        XCTAssertGreaterThan(SlideSelectConfig.rowBandSnapTolerance, 0, "吸附容差常量在位（禁散落魔法数字）")
        XCTAssertEqual(SlideSelectConfig.rowBandMaxExpandPerFrame, 0, "单帧行带展开上限默认 0 = 不限（docs/42 §10.2）")
    }

    func testBuildAndThousandQueriesWithinBudget() {
        var sections: [RowBandSection] = []
        for s in 0..<40 {
            sections.append(RowBandSection(section: s, itemCount: 500, columns: 3, rowHeight: 120,
                                           firstRowMinY: Double(100 + s * 20_240), headerHeight: 48))
        }
        let start = ContinuousClock.now
        let map = RowBandMap(sections: sections)
        var sink = 0
        for i in 0..<1000 {
            let y = Double((i * 7919) % 1_600_000)
            if let b = map.bandIndex(atContentY: y, clipTop: 48) { sink &+= b }
        }
        for i in 0..<100 {
            let from = i % map.count
            let to = min(map.count - 1, from + 166)
            sink &+= map.bandSequence(from: from, to: to).count
        }
        let elapsed = ContinuousClock.now - start
        _ = sink
        XCTAssertEqual(map.count, 40 * 167, "2 万 item → 6680 行带")
        // 本地 Docker swift test 为 debug 构建（-Onone），五连跑实测见 docs/05 变更 40；
        // <5ms 在该环境不可达（M18 T02 先例：预算修订 + 留痕），闸门调整为绝对回归闸 <20ms；
        // docs/42 §5 的 2ms 解析预算由 T07 在 iOS release 环境实测。
        XCTAssertLessThan(elapsed, .milliseconds(20), "建表 + 1000 次 bandIndex + 100 次 bandSequence 绝对回归闸 <20ms")
    }
}
