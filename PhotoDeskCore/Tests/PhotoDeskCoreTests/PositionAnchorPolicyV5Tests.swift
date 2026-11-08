// MARK: - PositionAnchorPolicyV5Tests：v5 恢复几何策略（docs/25 §5.5–5.6 / M15 P0-2）——
// 不变量：① 负 visualY 合法（部分可见锚点），恢复目标落合法区间不钳顶；② 目标钳制
// [-adjustedTop, contentHeight + bottomInset - viewportHeight]；③ NaN/非有限安全；
// ④ fallback 顺序 asset → section → ratio → none。

import XCTest
@testable import PhotoDeskCore

final class PositionAnchorPolicyV5Tests: XCTestCase {
    // MARK: - visualY

    func testVisualYPositiveForCellBelowTop() {
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: 1200, contentOffsetY: 1000), 200)
    }

    func testVisualYNegativeForPartiallyVisibleCell() {
        // 部分可见锚点：cell 顶边在视口上方 → visualY 为负，保存时不钳制
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: 900, contentOffsetY: 1000), -100)
    }

    func testVisualYNonFiniteIsSafe() {
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: .nan, contentOffsetY: 100), 0)
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: 100, contentOffsetY: .infinity), 0)
    }

    // MARK: - targetOffsetY

    func testTargetOffsetPreservesNegativeVisualY() {
        // minY 900，visualY -100 → 目标 offset 1000：锚点回到视口上方 100pt，不钳到顶
        XCTAssertEqual(PositionAnchorPolicy.targetOffsetY(cellMinY: 900, anchorVisualY: -100), 1000)
    }

    func testTargetOffsetNonFiniteVisualYFallsBackToCellMinY() {
        XCTAssertEqual(PositionAnchorPolicy.targetOffsetY(cellMinY: 1234, anchorVisualY: .nan), 1234)
        XCTAssertEqual(PositionAnchorPolicy.targetOffsetY(cellMinY: .nan, anchorVisualY: 10), 0)
    }

    // MARK: - 钳制

    func testClampedTargetStaysWithinLegalRange() {
        let offset = PositionAnchorPolicy.clampedTargetOffsetY(500,
                                                               contentHeight: 5000,
                                                               viewportHeight: 800,
                                                               adjustedTop: 48,
                                                               bottomInset: 34)
        XCTAssertEqual(offset, 500)
    }

    func testClampedTargetLowerBoundIsNegativeAdjustedTop() {
        // 目标比 -adjustedTop 更小（负 visualY 钳制下界）→ -48
        let offset = PositionAnchorPolicy.clampedTargetOffsetY(-500,
                                                               contentHeight: 5000,
                                                               viewportHeight: 800,
                                                               adjustedTop: 48,
                                                               bottomInset: 34)
        XCTAssertEqual(offset, -48.0)
    }

    func testClampedTargetUpperBoundIsContentBottom() {
        let upper = 5000.0 + 34 - 800
        let offset = PositionAnchorPolicy.clampedTargetOffsetY(99_999,
                                                               contentHeight: 5000,
                                                               viewportHeight: 800,
                                                               adjustedTop: 48,
                                                               bottomInset: 34)
        XCTAssertEqual(offset, upper)
    }

    func testClampedTargetNonFiniteOrZeroBoundsIsSafe() {
        XCTAssertEqual(PositionAnchorPolicy.clampedTargetOffsetY(.nan,
                                                                 contentHeight: 5000,
                                                                 viewportHeight: 800,
                                                                 adjustedTop: 48,
                                                                 bottomInset: 34), 0)
        XCTAssertEqual(PositionAnchorPolicy.clampedTargetOffsetY(100,
                                                                 contentHeight: 0,
                                                                 viewportHeight: 800,
                                                                 adjustedTop: 48,
                                                                 bottomInset: 34), 0)
    }

    // MARK: - ratio fallback

    func testRatioFallbackNaNIsSafe() {
        let offset = PositionAnchorPolicy.ratioOffsetY(ratio: .nan,
                                                       contentHeight: 5000,
                                                       viewportHeight: 800,
                                                       adjustedTop: 48,
                                                       bottomInset: 34)
        XCTAssertEqual(offset, 0, "NaN ratio → 内容顶部 offset 0（合法区间内），不写 NaN")
    }

    func testRatioFallbackClampsRatioToOne() {
        let scrollable = 5000.0 + 34 - 800
        let offset = PositionAnchorPolicy.ratioOffsetY(ratio: 2,
                                                       contentHeight: 5000,
                                                       viewportHeight: 800,
                                                       adjustedTop: 48,
                                                       bottomInset: 34)
        XCTAssertEqual(offset, -48.0 + scrollable, accuracy: 1e-9)
    }

    // MARK: - resolve 顺序

    private func makeAnchor(assetID: String = "a1",
                            sectionID: String = "2024-05",
                            itemIndex: Int = 3,
                            ratio: Double = 0.5) -> PositionAnchorV3 {
        PositionAnchorV3(anchorAssetID: assetID,
                         anchorVisualY: 100,
                         anchorContentOffsetY: 900,
                         assetID: assetID,
                         sectionID: sectionID,
                         itemIndexInSection: itemIndex,
                         offsetRatio: ratio,
                         contentHeight: 5000,
                         viewportHeight: 800)
    }

    func testResolvePrefersAssetAnchor() {
        let result = PositionAnchorPolicy.resolve(anchor: makeAnchor(),
                                                  assetCellMinY: 1000,
                                                  sectionCellMinY: 800,
                                                  contentHeight: 5000,
                                                  viewportHeight: 800,
                                                  adjustedTop: 48,
                                                  bottomInset: 34)
        XCTAssertEqual(result.strategy, .asset)
        XCTAssertEqual(result.offsetY, 900, accuracy: 1e-9)
    }

    func testResolveFallsBackToSectionWhenAssetMissing() {
        let result = PositionAnchorPolicy.resolve(anchor: makeAnchor(),
                                                  assetCellMinY: nil,
                                                  sectionCellMinY: 800,
                                                  contentHeight: 5000,
                                                  viewportHeight: 800,
                                                  adjustedTop: 48,
                                                  bottomInset: 34)
        XCTAssertEqual(result.strategy, .section)
        XCTAssertEqual(result.offsetY, 800, accuracy: 1e-9)
    }

    func testResolveFallsBackToRatioWhenBothMissing() {
        let result = PositionAnchorPolicy.resolve(anchor: makeAnchor(),
                                                  assetCellMinY: nil,
                                                  sectionCellMinY: nil,
                                                  contentHeight: 5000,
                                                  viewportHeight: 800,
                                                  adjustedTop: 48,
                                                  bottomInset: 34)
        XCTAssertEqual(result.strategy, .ratio)
    }

    func testResolveReturnsNoneForEmptyAnchor() {
        let empty = PositionAnchorV3(anchorAssetID: "",
                                     anchorVisualY: 0,
                                     anchorContentOffsetY: 0,
                                     assetID: "",
                                     sectionID: "",
                                     itemIndexInSection: 0,
                                     offsetRatio: 0)
        let result = PositionAnchorPolicy.resolve(anchor: empty,
                                                  assetCellMinY: nil,
                                                  sectionCellMinY: nil,
                                                  contentHeight: 5000,
                                                  viewportHeight: 800,
                                                  adjustedTop: 48,
                                                  bottomInset: 34)
        XCTAssertEqual(result.strategy, .none, "完全空的旧位置不得恢复，也不得回顶")
    }
}
