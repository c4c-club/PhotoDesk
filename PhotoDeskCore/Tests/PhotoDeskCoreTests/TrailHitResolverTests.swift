// MARK: - TrailHitResolverTests：指尖线段×cell 扫掠命中红/绿（M18 T03，docs/38 §2/§4、docs/37 §4/§7）——
// 语义锁：orderedIDs(from:to:cells:clipTop:expansion:epsilon:) 按「进入参数 t 升序、同 t 按 id 升序」
// 输出命中序列；反向线段产出反向序列（T05 回滑截断前提）；零长度命中起手 cell；
// 快速跨格补扫无遗漏；clipTop 粘性头遮挡（半裁 cell 仍可命中其头下部分、全裁不命中、低于线段顶不生效）；
// 非有限 from/to → 空序列；负宽/退化/非有限 frame 逐个跳过；expansion < 0 钳 0。
// 网格约定沿旧 MarqueeHitResolverTests：cell 100×100、间距 10（列/行距 110）。

import XCTest
@testable import PhotoDeskCore

final class TrailHitResolverTests: XCTestCase {

    // MARK: - helpers

    private func frame(_ id: String, x: Double, y: Double,
                       w: Double = 100, h: Double = 100) -> GridCellFrame {
        GridCellFrame(id: id, minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    /// 水平带状连续网格：列 x 0/100/200/300/400（无间隙 100 宽，y 0..200 单行带）
    private func band(_ n: Int) -> [GridCellFrame] {
        let names = Array(["A", "B", "C", "D", "E"][0..<min(n, 5)])
        return names.enumerated().map { i, name in
            GridCellFrame(id: name, minX: Double(i * 100), minY: 0, maxX: Double((i + 1) * 100), maxY: 200)
        }
    }

    private func order(_ from: (Double, Double), _ to: (Double, Double),
                       cells: [GridCellFrame], clipTop: Double? = nil,
                       expansion: Double = 0, epsilon: Double = 0.5) -> [String] {
        TrailHitResolver.orderedIDs(from: GridPoint(x: from.0, y: from.1),
                                    to: GridPoint(x: to.0, y: to.1),
                                    cells: cells, clipTop: clipTop,
                                    expansion: expansion, epsilon: epsilon)
    }

    // MARK: - 方向与顺序

    func testHorizontalSegmentHitsInOrder() {
        XCTAssertEqual(order((10, 100), (290, 100), cells: band(3)), ["A", "B", "C"])
    }

    func testVerticalSegmentHitsInOrder() {
        let col = [frame("r0", x: 0, y: 0), frame("r1", x: 0, y: 110), frame("r2", x: 0, y: 220)]
        XCTAssertEqual(order((50, 10), (50, 250), cells: col), ["r0", "r1", "r2"])
    }

    func testDiagonalSegmentHitsInOrder() {
        XCTAssertEqual(order((10, 10), (290, 190), cells: band(3)), ["A", "B", "C"])
    }

    func testReverseSegmentProducesReverseOrder() {
        let forward = order((10, 10), (290, 190), cells: band(3))
        let backward = order((290, 190), (10, 10), cells: band(3))
        XCTAssertEqual(backward, forward.reversed(), "反向线段必须产出反向 id 序列（回滑前提）")
        XCTAssertEqual(backward, ["C", "B", "A"])
    }

    func testZeroLengthSegmentHitsStartCell() {
        XCTAssertEqual(order((50, 50), (50, 50), cells: band(1)), ["A"], "零长度线段命中起手 cell")
    }

    func testFastFrameCrossesFiveCellsInOrder() {
        XCTAssertEqual(order((10, 100), (490, 100), cells: band(5)), ["A", "B", "C", "D", "E"],
                       "快速一帧跨 5 格必须按经过顺序全部补扫")
    }

    // MARK: - 扩展与边界

    func testEdgeTouchWithinExpansionHits() {
        // 线段距 cell 右缘外侧 0.5pt：expansion=1 扩展后命中；expansion=0 不命中
        let cell = [frame("a", x: 0, y: 0, w: 100, h: 100)]
        XCTAssertEqual(order((100.5, 50), (100.5, 50), cells: cell, expansion: SlideSelectConfig.hitExpansion), ["a"])
        XCTAssertTrue(order((100.5, 50), (100.5, 50), cells: cell, expansion: 0).isEmpty,
                      "expansion=0 时贴边外侧不命中（扩展语义生效）")
    }

    func testSegmentCompletelyOutsideHitsNothing() {
        XCTAssertTrue(order((500, 500), (900, 900), cells: band(3)).isEmpty)
    }

    func testNegativeExpansionClampedToZero() {
        let cell = [frame("a", x: 0, y: 0, w: 100, h: 100)]
        let clamped = order((100.5, 50), (100.5, 50), cells: cell, expansion: -5)
        let zero = order((100.5, 50), (100.5, 50), cells: cell, expansion: 0)
        XCTAssertEqual(clamped, zero, "expansion < 0 必须钳到 0（与 0 等价）")
        XCTAssertTrue(clamped.isEmpty)
    }

    // MARK: - 乱序 / 重复 / 平局

    func testUnorderedAndDuplicateCellsDeterministic() {
        let cells = [frame("dup", x: 300, y: 0), frame("B", x: 100, y: 0),
                     frame("dup", x: 0, y: 0), frame("A", x: 0, y: 0)]
        XCTAssertEqual(order((10, 100), (390, 100), cells: cells), ["A", "dup", "B"],
                       "同 id 重复 frame 去重保序（首个 tMin），乱序 cells 结果确定")
    }

    func testSameTMinTieSortedByID() {
        // 两个不同 id 的 frame 完全重叠且都包含线段起点 → tMin 相同 → 按 id 升序
        let cells = [frame("X", x: 0, y: 0), frame("W", x: 0, y: 0)]
        XCTAssertEqual(order((50, 50), (50, 50), cells: cells), ["W", "X"], "同 tMin 平局按 id 升序，结果确定")
    }

    // MARK: - clipTop 粘性头遮挡

    func testClipTopPartiallyOccludedCell() {
        // P(0..100) 全在遮挡区，Q(100..200) 跨 clipTop=110：Q 的头下部分仍可命中
        let cells = [frame("P", x: 0, y: 0, w: 100, h: 100), frame("Q", x: 0, y: 100, w: 100, h: 100)]
        XCTAssertEqual(order((50, 0), (50, 190), cells: cells, clipTop: 110), ["Q"],
                       "半裁 cell 仍可命中其头下部分；全裁 cell 不可命中")
    }

    func testClipTopFullyOccludedSegment() {
        let cells = [frame("A", x: 0, y: 0, w: 100, h: 100)]
        XCTAssertTrue(order((50, 0), (50, 90), cells: cells, clipTop: 110).isEmpty,
                      "线段完全落在遮挡区 → 空")
    }

    func testClipTopBelowSegmentTopNoEffect() {
        let cells = band(3)
        let withClip = order((10, 100), (290, 100), cells: cells, clipTop: 50)
        let withoutClip = order((10, 100), (290, 100), cells: cells, clipTop: nil)
        XCTAssertEqual(withClip, withoutClip, "clipTop 低于线段顶部时不生效")
    }

    // MARK: - 非有限与非法输入

    func testNaNFromOrToReturnsEmpty() {
        let cells = band(3)
        XCTAssertTrue(order((Double.nan, 100), (290, 100), cells: cells).isEmpty, "NaN from → 空")
        XCTAssertTrue(order((10, 100), (Double.nan, 100), cells: cells).isEmpty, "NaN to → 空")
        XCTAssertTrue(order((10, Double.nan), (290, Double.nan), cells: cells).isEmpty, "NaN y → 空")
    }

    func testInfinityFromOrToReturnsEmpty() {
        let cells = band(3)
        XCTAssertTrue(order((Double.infinity, 100), (290, 100), cells: cells).isEmpty, "+∞ from → 空")
        XCTAssertTrue(order((10, 100), (-Double.infinity, 100), cells: cells).isEmpty, "−∞ to → 空")
    }

    func testInvalidFramesSkipped() {
        let cells = [frame("ok", x: 0, y: 0, w: 100, h: 100),
                     GridCellFrame(id: "negW", minX: 200, minY: 0, maxX: 100, maxY: 100),
                     GridCellFrame(id: "negH", minX: 300, minY: 100, maxX: 400, maxY: 0),
                     GridCellFrame(id: "nan", minX: .nan, minY: 0, maxX: 500, maxY: 100),
                     GridCellFrame(id: "inf", minX: 600, minY: 0, maxX: .infinity, maxY: 100)]
        XCTAssertEqual(order((10, 50), (90, 50), cells: cells), ["ok"],
                       "负宽/负高/非有限 frame 逐个跳过，不崩溃不影响合法命中")
    }

    func testNearVerticalSegmentUsesDegenerateBranch() {
        // |dx| = 0.4 ≤ epsilon(0.5)：走垂直退化分支，x 视为恒定，按 y 顺序命中整列
        let col = [frame("r0", x: 0, y: 0), frame("r1", x: 0, y: 110), frame("r2", x: 0, y: 220)]
        XCTAssertEqual(order((50, 10), (50.4, 250), cells: col, epsilon: SlideSelectConfig.segmentEpsilon),
                       ["r0", "r1", "r2"])
    }

    // MARK: - 性能（docs/38 §4：2 万 frame <20ms；M17 T03 同款预算与容器口径）

    func testPerfTwentyThousandFramesUnderBudget() {
        var cells: [GridCellFrame] = []
        cells.reserveCapacity(20000)
        for index in 0..<20000 {
            let col = index % 200
            let row = index / 200
            cells.append(frame("c-\(index)", x: Double(col * 110), y: Double(row * 110)))
        }
        let started = Date()
        let result = order((55, 10), (55, 990), cells: cells)   // 垂直跨 10 行
        let elapsedMs = Date().timeIntervalSince(started) * 1000
        XCTAssertEqual(result.count, 10, "命中数正确才证明没走捷径")
        XCTAssertEqual(result.first, "c-0", "t 升序：第一行先于后面行")
        XCTAssertLessThan(elapsedMs, 20, "2 万 frame 线段扫掠须 <20ms（实际 \(elapsedMs)ms）")
    }
}
