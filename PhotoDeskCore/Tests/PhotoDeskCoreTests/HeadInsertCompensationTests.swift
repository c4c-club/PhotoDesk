// MARK: - HeadInsertCompensationTests：head 回填前插补偿纯策略（docs/28 §5.5 步骤 4 / M16 T03）——
// 每 head 批次前插后：delta = after − before；插入项在锚点上方 → offset += delta，否则不变；
// 非有限/负 delta 拒绝；钳制 [0, maxOffsetY]。多批走 Ledger 累计。

import XCTest
@testable import PhotoDeskCore

final class HeadInsertCompensationTests: XCTestCase {
    private func adjust(beforeY: Double, before: Double, after: Double,
                        above: Bool = true, maxY: Double = 10_000) -> Double {
        HeadInsertCompensationPolicy.adjustedOffsetY(beforeY: beforeY,
                                                     contentHeightBefore: before,
                                                     contentHeightAfter: after,
                                                     insertedAboveAnchor: above,
                                                     maxOffsetY: maxY)
    }

    func testAboveInsertShiftsOffsetByDelta() {
        XCTAssertEqual(adjust(beforeY: 900, before: 5_000, after: 5_800), 1_700,
                       "上方插入 800pt → offset += delta")
    }

    func testBelowInsertKeepsOffset() {
        XCTAssertEqual(adjust(beforeY: 900, before: 5_000, after: 5_800, above: false), 900,
                       "插入在锚点下方 → 视觉位置不受影响，offset 不变")
    }

    func testZeroDeltaIsNoOp() {
        XCTAssertEqual(adjust(beforeY: 900, before: 5_000, after: 5_000), 900)
    }

    func testNegativeDeltaIsRejected() {
        XCTAssertEqual(adjust(beforeY: 900, before: 5_000, after: 4_800), 900,
                       "负 delta（内容变矮）不是前插语义 → 拒绝调整")
    }

    func testNonFiniteDeltaIsRejected() {
        XCTAssertEqual(adjust(beforeY: 900, before: 5_000, after: .infinity), 900)
        XCTAssertEqual(adjust(beforeY: 900, before: .nan, after: 5_000), 900)
    }

    func testNonFiniteBeforeYFallsBackToZero() {
        XCTAssertEqual(adjust(beforeY: .nan, before: 5_000, after: 5_800), 0,
                       "offset 损坏 → 保守回 0（顶部），绝不写 NaN")
    }

    func testUpperClampToMaxOffset() {
        XCTAssertEqual(adjust(beforeY: 9_900, before: 10_000, after: 11_000, maxY: 10_000), 10_000,
                       "补偿后超过可滚动上界 → 钳制到 maxOffsetY")
    }

    func testLowerClampToZero() {
        XCTAssertEqual(adjust(beforeY: 0, before: 0, after: 0, maxY: 10_000), 0, "下界 0")
        XCTAssertEqual(adjust(beforeY: -50, before: 5_000, after: 5_800, maxY: 10_000), 750,
                       "橡皮带上界负值补偿后仍按 delta 平移（-50+800=750）")
    }

    func testNegativeMaxOffsetTreatedAsZero() {
        XCTAssertEqual(adjust(beforeY: 900, before: 5_000, after: 5_800, maxY: -10), 900,
                       "maxOffset 非法 → 钳制空间为 0，offset 保持原值")
    }

    func testLedgerAccumulatesMultipleBatches() {
        var ledger = HeadInsertCompensationPolicy.Ledger(initialY: 900, maxOffsetY: 10_000)
        ledger.append(delta: 300, insertedAboveAnchor: true)
        ledger.append(delta: 500, insertedAboveAnchor: true)
        XCTAssertEqual(ledger.offsetY, 1_700, "多批上方插入 → delta 逐批累计")
        XCTAssertEqual(ledger.appliedDeltas, [300, 500])
    }

    func testLedgerIgnoresBelowInsertsAndBadDeltas() {
        var ledger = HeadInsertCompensationPolicy.Ledger(initialY: 900, maxOffsetY: 10_000)
        ledger.append(delta: 300, insertedAboveAnchor: false)
        ledger.append(delta: -50, insertedAboveAnchor: true)
        ledger.append(delta: .nan, insertedAboveAnchor: true)
        XCTAssertEqual(ledger.offsetY, 900, "下方插入与非法 delta 均不调整")
        XCTAssertTrue(ledger.appliedDeltas.isEmpty)
    }

    func testLedgerClampsToMaxOffset() {
        var ledger = HeadInsertCompensationPolicy.Ledger(initialY: 9_800, maxOffsetY: 10_000)
        ledger.append(delta: 900, insertedAboveAnchor: true)
        XCTAssertEqual(ledger.offsetY, 10_000, "累计超界 → 钳制")
    }

    func testLedgerInitClampsNegativeMaxOffset() {
        let ledger = HeadInsertCompensationPolicy.Ledger(initialY: 900, maxOffsetY: -5)
        XCTAssertEqual(ledger.offsetY, 0, "非法 maxOffset → 空间为 0")
    }
}