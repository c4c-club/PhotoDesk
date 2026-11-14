// MARK: - 职责说明：MarqueeHitResolver 矩形命中纯函数单测（M17 T03，docs/32 §2.4/§4.1）——
// 「矩形 + 一组真实 cell frame → 命中 id 集合」全部语义：闭区间相交、自动归一 + 1pt 扩展、
// clipTop 粘性头裁剪（抬后为空返回空集）、非有限值/退化 frame 安全、乱序 cells、
// 同 id 重复折叠、2 万 frame 性能预算（CI 容器放宽到 20ms，卡内许可）。
// 网格约定与旧 MarqueeSelectionPolicyTests 一致：cell 100×100、间距 10 → 列距/行距 110。

import XCTest
@testable import PhotoDeskCore

final class MarqueeHitResolverTests: XCTestCase {

    // MARK: - helpers

    private func frame(_ id: String, x: Double, y: Double,
                       w: Double = 100, h: Double = 100) -> CellFrame {
        CellFrame(id: id, minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    /// 3×3 网格（列 x: 0/110/220，行 y: 0/110/220），id = "c\(row)-\(col)"
    private func grid3() -> [CellFrame] {
        var cells: [CellFrame] = []
        for row in 0..<3 {
            for col in 0..<3 {
                cells.append(frame("c\(row)-\(col)", x: Double(col * 110), y: Double(row * 110)))
            }
        }
        return cells
    }

    private func hit(_ ax: Double, _ ay: Double, _ cx: Double, _ cy: Double,
                     cells: [CellFrame], clipTop: Double? = nil) -> Set<String> {
        MarqueeHitResolver.hit(HitRect(anchor: (ax, ay), current: (cx, cy)),
                               cells: cells, clipTop: clipTop)
    }

    // MARK: - 基础相交

    func testEmptyCellsReturnsEmpty() {
        XCTAssertTrue(hit(0, 0, 500, 500, cells: []).isEmpty, "空数组 → 空集")
    }

    func testSingleCellExactBoundsHit() {
        let result = hit(0, 0, 100, 100, cells: [frame("a", x: 0, y: 0)])
        XCTAssertEqual(result, ["a"])
    }

    func testZeroSizeRectAtCellCenterHitsViaExpansion() {
        // 起手语义：anchor == current 的零尺寸矩形扩展 1pt 后命中手指下的 cell
        let result = hit(50, 50, 50, 50, cells: [frame("a", x: 0, y: 0)])
        XCTAssertEqual(result, ["a"])
    }

    func testOnePtExpansionBridgesOnePtGap() {
        // 原始矩形右缘 109（距相邻 cell 左缘 110 差 1pt）：扩展后 110 触达 → 两格都命中
        let result = hit(0, 0, 109, 100, cells: [frame("a", x: 0, y: 0), frame("b", x: 110, y: 0)])
        XCTAssertEqual(result, ["a", "b"], "1pt 扩展必须补上单帧采样与 cell 缘的亚 pt 误差")
    }

    func testPartialIntersectionHits() {
        // 矩形只覆盖 cell 左半（x 0..49）→ 命中
        let result = hit(0, 10, 49, 90, cells: [frame("a", x: 0, y: 0)])
        XCTAssertEqual(result, ["a"])
    }

    func testRectContainingCellsHitsAll() {
        let result = hit(-10, -10, 340, 340, cells: grid3())
        XCTAssertEqual(result.count, 9)
    }

    func testCellContainingRectStillHits() {
        // 被包含：超大 cell 完全包住矩形
        let big = frame("big", x: 0, y: 0, w: 1000, h: 1000)
        let result = hit(10, 10, 20, 20, cells: [big])
        XCTAssertEqual(result, ["big"])
    }

    func testTouchingEdgesCountAsIntersection() {
        // 闭区间语义：rect.maxX 恰好等于 cell.minX → 命中
        let result = hit(100, 0, 110, 100, cells: [frame("b", x: 110, y: 0)])
        XCTAssertEqual(result, ["b"])
    }

    // MARK: - 输入顺序 / 重复 id

    func testUnsortedCellsProduceSameResult() {
        let sorted = grid3()
        let shuffled = sorted.reversed() + [sorted[4]]
        let a = hit(-10, -10, 340, 340, cells: sorted)
        let b = hit(-10, -10, 340, 340, cells: shuffled)
        XCTAssertEqual(a, b, "cells 允许乱序")
    }

    func testDuplicateIdFramesCollapseToSingleId() {
        let result = hit(0, 0, 200, 100, cells: [frame("dup", x: 0, y: 0), frame("dup", x: 110, y: 0)])
        XCTAssertEqual(result, ["dup"], "同 id 两帧同命中 → Set 折叠为一个")
    }

    func testDuplicateIdAnyFrameHitsCounts() {
        // 同 id 一帧在矩形内、一帧在矩形外：任一帧命中即计入
        let result = hit(0, 0, 100, 100, cells: [frame("dup", x: 0, y: 0), frame("dup", x: 5000, y: 5000)])
        XCTAssertEqual(result, ["dup"])
    }

    func testCrossSectionFramesHitTogether() {
        // 「跨段」：相距极远的两帧同被矩形命中
        let cells = [frame("s0", x: 0, y: 0), frame("s9", x: 0, y: 5000)]
        let result = hit(0, 0, 100, 5000, cells: cells)
        XCTAssertEqual(result, ["s0", "s9"])
    }

    // MARK: - 反向拖（归一）

    func testReverseDragNormalizesToForwardResult() {
        let forward = hit(10, 10, 300, 300, cells: grid3())
        let reverse = hit(300, 300, 10, 10, cells: grid3())
        XCTAssertEqual(reverse, forward, "反向拖自动归一，结果与正向一致")
    }

    func testHorizontalReverseNormalizes() {
        let forward = hit(10, 0, 300, 100, cells: grid3())
        let reverse = hit(300, 0, 10, 100, cells: grid3())
        XCTAssertEqual(reverse, forward)
    }

    func testHitRectNormalizationIsValueSemantics() {
        // 同一几何的两种输入顺序 → Equatable 相等（自动归一在 init 完成）
        XCTAssertEqual(HitRect(anchor: (0, 0), current: (100, 100)),
                       HitRect(anchor: (100, 100), current: (0, 0)))
    }

    // MARK: - 非有限 / 退化输入

    func testNaNRectReturnsEmpty() {
        let rect = HitRect(anchor: (.nan, 0), current: (100, 100))
        XCTAssertTrue(MarqueeHitResolver.hit(rect, cells: grid3()).isEmpty, "NaN 矩形 → 空集")
    }

    func testInfinityRectReturnsEmpty() {
        let rect = HitRect(anchor: (0, 0), current: (.infinity, 100))
        XCTAssertTrue(MarqueeHitResolver.hit(rect, cells: grid3()).isEmpty, "∞ 矩形 → 空集")
    }

    func testNonFiniteCellFrameSkipped() {
        let broken = CellFrame(id: "nan", minX: 0, minY: 0, maxX: 100, maxY: .nan)
        let infinite = CellFrame(id: "inf", minX: 0, minY: 0, maxX: .infinity, maxY: 100)
        let good = frame("good", x: 0, y: 0)
        let result = hit(0, 0, 100, 100, cells: [broken, infinite, good])
        XCTAssertEqual(result, ["good"], "非有限 frame 一律跳过，不得产生幽灵命中")
    }

    func testDegenerateCellFrameSkipped() {
        // 退化 frame（maxX < minX）：跳过不命中
        let degenerate = CellFrame(id: "bad", minX: 100, minY: 0, maxX: 0, maxY: 100)
        let result = hit(0, 0, 200, 200, cells: [degenerate])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - clipTop 粘性头裁剪

    func testClipTopClipsCellsAboveStickyHeader() {
        // 行 0（y 0..100）被钉住头遮住：clipTop=110 抬高矩形上边 → 只剩行 1
        let result = hit(0, 0, 100, 210, cells: grid3(), clipTop: 110)
        XCTAssertEqual(result, ["c1-0", "c1-1", "c1-2"], "行 0 被粘性头遮住：clipTop=110 后只剩行 1")
    }

    func testClipTopFullClipReturnsEmpty() {
        let result = hit(0, 0, 100, 100, cells: [frame("a", x: 0, y: 0)], clipTop: 10000)
        XCTAssertTrue(result.isEmpty, "clipTop 抬过全部内容 → 空集")
    }

    func testClipTopBelowRectTopIsNoOp() {
        let noClip = hit(0, 0, 100, 220, cells: grid3())
        let withClip = hit(0, 0, 100, 220, cells: grid3(), clipTop: -50)
        XCTAssertEqual(withClip, noClip, "clipTop 低于矩形上边时不改变结果")
    }

    func testClipTopPastRectBottomReturnsEmpty() {
        // 抬后矩形为空（minY > maxY）→ 空集，不得产生越界命中
        let result = hit(0, 60, 100, 200, cells: grid3(), clipTop: 500)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - 性能（docs/33 T03：2 万 frame；CI 容器预算放宽到 20ms 并在此说明）

    func testPerf20000FramesUnderBudget() {
        var cells: [CellFrame] = []
        cells.reserveCapacity(20000)
        for index in 0..<20000 {
            let col = index % 200
            let row = index / 200
            cells.append(frame("c-\(index)", x: Double(col * 110), y: Double(row * 110)))
        }
        let rect = HitRect(anchor: (0, 0), current: (319, 219))
        let started = Date()
        let result = MarqueeHitResolver.hit(rect, cells: cells)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result.count, 9, "矩形覆盖 3×3 网格；命中数正确才证明没走捷径")
        XCTAssertLessThan(elapsed, 0.02,
                          "2 万 frame 线性命中须 < 20ms（5ms 预算在 CI 容器 debug 构建下不稳，按卡内许可放宽，docs/33 T03）")
    }
}
