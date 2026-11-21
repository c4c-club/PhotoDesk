// MARK: - 职责说明：混合命中模式判定单测（M20 T04，docs/49 T04 §2.2/§2.3）——
// hitMode 纯函数行为锁：同带 → cells、纵向跨带占优 → rows、横向占优 → cells、
// 1.2 边界 ≥ 语义、非有限/非法 ratio → cells。ratio 由测试注入（config 常量仅作默认值）。

import XCTest
@testable import PhotoDeskCore

final class SlideSelectHitModeTests: XCTestCase {

    /// 生产默认系数（docs/49 T04 §2.1）
    private let defaultRatio = SlideSelectConfig.rowBandVerticalRatio

    // 同带水平拖动：不做整行展开
    func testSameBandHorizontalReturnsCells() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 200, dy: 10, fromBand: 3, toBand: 3,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells)
    }

    // 同带零长度（起手点未动）：按 cell 命中
    func testSameBandZeroLengthReturnsCells() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 0, dy: 0, fromBand: 7, toBand: 7,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells)
    }

    // 跨带纵向（向下与向上）：整行模式；方向（toBand 相对大小）由调用方 band 序决定
    func testCrossBandVerticalReturnsRows() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 8, dy: 120, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .rows)
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: -8, dy: -120, fromBand: 5, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .rows, "向上跨带同样是整行模式（rows）")
    }

    // 跨带但横向占优：dy 90 略过一行、dx 300 → 90 < 300×1.2 → cell 扫掠
    func testCrossBandHorizontalDominantReturnsCells() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 300, dy: 90, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells)
    }

    // 恰好 1.2 边界：|dy| == |dx| × ratio → rows（≥ 语义）
    func testExactBoundaryRatioReturnsRows() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: 120, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: 1.2),
                       .rows)
    }

    // 1.19 倍：差一点 → cells
    func testBelowBoundaryRatioReturnsCells() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: 119, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: 1.2),
                       .cells)
    }

    // 非有限输入与非正/非有限 ratio：一律 cells，不崩溃
    func testNonFiniteInputsReturnCells() {
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: Double.nan, dy: 100, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells, "NaN dx → cells")
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: Double.nan, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells, "NaN dy → cells")
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: Double.infinity, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells, "∞ dy → cells")
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: -Double.infinity, dy: 100, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: defaultRatio),
                       .cells, "∞ dx → cells")
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: 100, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: Double.nan),
                       .cells, "NaN ratio → cells")
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: 100, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: .infinity),
                       .cells, "∞ ratio → cells")
        XCTAssertEqual(SlideSelectPolicy.hitMode(dx: 100, dy: 100, fromBand: 1, toBand: 2,
                                                 verticalDominanceRatio: 0),
                       .cells, "非正 ratio 视为非法输入 → cells")
    }
}
