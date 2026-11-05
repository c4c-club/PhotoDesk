// MARK: - GridHitRegionTests：二维矩形命中 8 类语义（docs/16 M12 R08 / Phase 6）——
// 空白矩形 / 全包 / 回拖（基线重算子集）/ 乱序 / NaN / 重叠 / 跨 section / 动态列数 + 合并语义。

import XCTest
@testable import PhotoDeskCore

final class GridHitRegionTests: XCTestCase {
    private func cell(_ id: String, _ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 100) -> GridCellRect {
        GridCellRect(id: id, rect: GridRect(x: x, y: y, width: w, height: h))
    }

    // MARK: 1. 空白矩形

    func testZeroSizeRectHitsNothing() {
        let cells = [cell("a", 0, 0), cell("b", 110, 0)]
        let rect = GridRect(from: GridPoint(x: 50, y: 50), to: GridPoint(x: 50, y: 50))
        XCTAssertTrue(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2).isEmpty,
                      "零尺寸拖曳矩形（未移动）不命中任何 cell")
    }

    func testEmptyCellListHitsNothing() {
        let rect = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: 500, y: 500))
        XCTAssertTrue(GridHitRegion.hitIDs(cells: [], rect: rect, threshold: 0.2).isEmpty)
    }

    // MARK: 2. 全包

    func testFullyCoveringRectHitsAllCells() {
        let cells = [cell("a", 0, 0), cell("b", 110, 0), cell("c", 220, 0)]
        let rect = GridRect(from: GridPoint(x: -10, y: -10), to: GridPoint(x: 330, y: 120))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2),
                       Set(["a", "b", "c"]))
    }

    // MARK: 3. 回拖（基线重算：缩小矩形 → 命中集合收缩为子集）

    func testShrinkingRectShrinksHitSet() {
        let cells = [cell("a", 0, 0), cell("b", 110, 0), cell("c", 220, 0)]
        let wide = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: 330, y: 100))
        let wideHits = GridHitRegion.hitIDs(cells: cells, rect: wide, threshold: 0.2)
        XCTAssertEqual(wideHits, Set(["a", "b", "c"]))
        let narrow = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: 60, y: 100))
        let narrowHits = GridHitRegion.hitIDs(cells: cells, rect: narrow, threshold: 0.2)
        XCTAssertEqual(narrowHits, Set(["a"]), "回拖后命中集合必须收缩（基线重算语义）")
        XCTAssertTrue(narrowHits.isSubset(of: wideHits))
    }

    // MARK: 4. 乱序

    func testUnorderedCellsHitCorrectly() {
        let cells = [cell("c", 220, 0), cell("a", 0, 0), cell("b", 110, 0)]
        let rect = GridRect(from: GridPoint(x: 100, y: -5), to: GridPoint(x: 330, y: 105))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2),
                       Set(["b", "c"]), "输入顺序不影响几何命中")
    }

    // MARK: 5. NaN / ∞ 安全

    func testNaNRectHitsNothing() {
        let cells = [cell("a", 0, 0)]
        let rect = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: .nan, y: 100))
        XCTAssertTrue(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2).isEmpty)
        let infinite = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: .infinity, y: 100))
        XCTAssertTrue(GridHitRegion.hitIDs(cells: cells, rect: infinite, threshold: 0.2).isEmpty,
                      "∞ 宽矩形不安全 → 空集")
    }

    func testNaNCellSkippedSafely() {
        let broken = GridCellRect(id: "broken", rect: GridRect(x: .nan, y: 0, width: 100, height: 100))
        let good = cell("good", 0, 0)
        let rect = GridRect(from: GridPoint(x: -10, y: -10), to: GridPoint(x: 200, y: 200))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: [broken, good], rect: rect, threshold: 0.2),
                       Set(["good"]))
    }

    func testInfiniteThresholdClamped() {
        let cells = [cell("a", 0, 0)]
        let rect = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: 100, y: 100))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: .infinity),
                       Set(["a"]), "threshold ∞ 钳制为 1（全包含）")
    }

    // MARK: 6. 重叠 cell（去重语义）

    func testOverlappingCellsBothHitAndDeduplicated() {
        let first = cell("a", 0, 0)
        let second = cell("a", 50, 0)   // 同 id 两帧（复用窗口）重叠
        let rect = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: 150, y: 100))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: [first, second], rect: rect, threshold: 0.2),
                       Set(["a"]), "同 id 命中去重（Set 语义）")
    }

    // MARK: 7. 跨 section（几何判定，不看分组）

    func testCrossSectionCellsHitByGeometry() {
        // 月份 A 的末行与月份 B 的首行在屏幕上相邻（view 坐标连续）
        let cells = [cell("a-last", 0, 700), cell("b-first", 110, 700), cell("a-mid", 0, 300)]
        let rect = GridRect(from: GridPoint(x: 0, y: 650), to: GridPoint(x: 210, y: 810))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2),
                       Set(["a-last", "b-first"]),
                       "跨 section 按 view 坐标几何命中（旧版一维 SelectionRange 无法表达）")
    }

    // MARK: 8. 动态列数（2 列 / 4 列布局）

    func testTwoColumnLayout() {
        let cells = [cell("l0", 0, 0), cell("r0", 195, 0), cell("l1", 0, 195), cell("r1", 195, 195)]
        let rect = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: 295, y: 190))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2),
                       Set(["l0", "r0"]), "2 列布局：第一行命中、第二行不命中")
    }

    func testFourColumnLayout() {
        let w = 97.0
        let cells = (0..<4).map { cell("c\($0)", Double($0) * (w + 2), 0, w, w) }
        let rect = GridRect(from: GridPoint(x: 0, y: 0), to: GridPoint(x: w * 3 + 3, y: w))
        XCTAssertEqual(GridHitRegion.hitIDs(cells: cells, rect: rect, threshold: 0.2),
                       Set(["c0", "c1", "c2"]), "4 列布局：前 3 格命中（c3 面积不足阈值）")
    }

    // MARK: 合并语义（基线重算二选一：写死「锚点初态已选 → 反选」）

    func testMergedSelectionUnionWhenAnchorWasUnselected() {
        let merged = GridHitRegion.mergedSelection(base: ["a"],
                                                   hits: ["b", "c"],
                                                   anchorInitiallySelected: false)
        XCTAssertEqual(merged, Set(["a", "b", "c"]), "锚点初态未选 → 拖过即加选")
    }

    func testMergedSelectionSubtractWhenAnchorWasSelected() {
        let merged = GridHitRegion.mergedSelection(base: ["a", "b", "c"],
                                                   hits: ["b", "c"],
                                                   anchorInitiallySelected: true)
        XCTAssertEqual(merged, Set(["a"]), "锚点初态已选 → 拖过即取消（回拖语义）")
    }

    func testMergedSelectionReselectOnSecondPass() {
        // 拖出去再拖回来：反选语义下 hit 集为空 → 回到基线（可再次加选）
        let base = Set(["a", "b"])
        let draggedOut = GridHitRegion.mergedSelection(base: base, hits: ["a", "b"],
                                                       anchorInitiallySelected: true)
        XCTAssertTrue(draggedOut.isEmpty)
        let draggedBack = GridHitRegion.mergedSelection(base: base, hits: [],
                                                        anchorInitiallySelected: true)
        XCTAssertEqual(draggedBack, base, "每帧从基线重算：hit 为空 = 回到基线")
    }
}
