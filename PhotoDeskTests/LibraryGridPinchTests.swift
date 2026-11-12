// MARK: - 职责说明：GridPinchTransaction 事务壳矩阵（docs/28 §4.4.4，M16 T02）——
// 模拟 200 次 target 变更：任意时刻最多一个在途过渡、最终列数一致、锚点 assetID 不可变、
// 手势生命周期（end/isBusy）。真机手势矩阵在 GridPinchUITests。
// 红→绿口径：GridPinchTransaction 落地前无法编译（red-library.txt 实录）。

import XCTest
@testable import PhotoDesk

@MainActor
final class LibraryGridPinchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 200 次快速变更

    /// 200 次快速 target 变更：单飞互斥、终态一致、锚点 assetID 不变
    func test200RapidTargetChangesKeepSingleFlightAndAnchor() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-anchor-200", startColumns: 3, scale: 1)
        var lastCommitted = 3
        var commitCount = 0
        for round in 0..<200 {
            // 快速反向扫：scale 在 0.55...2.4 来回（覆盖 2↔5 全列域）
            let scale = round % 2 == 0 ? 0.55 + Double(round % 6) * 0.1 : 2.4 - Double(round % 6) * 0.1
            if tx.changed(scale: scale) != nil {
                // 提交前在途必须为空：同一时刻最多一个布局过渡
                XCTAssertNil(tx.inFlightColumns, "第 \(round) 轮提交前不得已有在途过渡")
                if let target = tx.markInFlight() {
                    lastCommitted = target
                    commitCount += 1
                    _ = tx.transitionFinished()
                    XCTAssertEqual(tx.currentColumns, lastCommitted, "过渡完成后机器列数必须一致")
                }
            }
            XCTAssertFalse(tx.isBusy, "每轮收尾后不得残留事务（第 \(round) 轮）")
        }
        XCTAssertGreaterThan(commitCount, 10, "200 次变更应产生足够多的一次性提交")
        XCTAssertEqual(tx.currentColumns, lastCommitted)
        XCTAssertFalse(tx.isBusy)
        XCTAssertEqual(tx.anchorAssetID, "asset-anchor-200", "锚点 assetID 不得被事务改写")
    }

    // MARK: - 单飞互斥与链式消费

    func testInFlightBlocksCommitAndChainsPending() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-a", startColumns: 3, scale: 1)
        XCTAssertEqual(tx.changed(scale: 1.5), 2)
        XCTAssertEqual(tx.markInFlight(), 2)
        // 在途期间继续变更：只挂链，不得二次提交
        for scale in [0.55, 0.8, 1.1, 1.7, 2.2] {
            _ = tx.changed(scale: scale)
            XCTAssertNil(tx.markInFlight(), "在途期间不得再提交")
        }
        XCTAssertTrue(tx.isBusy)
        let chained = tx.transitionFinished()
        if let chained {
            XCTAssertTrue((2...5).contains(chained), "消费结果必须在 2...5")
            XCTAssertEqual(tx.currentColumns, chained)
            XCTAssertEqual(tx.inFlightColumns, chained, "接续的过渡立即进入在途（单飞链）")
        }
        _ = tx.transitionFinished()
        XCTAssertFalse(tx.isBusy)
    }

    // MARK: - 锚点身份

    func testAnchorAssetIDImmutableAcrossTransaction() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-XYZ", startColumns: 3, scale: 1)
        _ = tx.changed(scale: 1.5)
        _ = tx.markInFlight()
        _ = tx.changed(scale: 0.6)
        XCTAssertEqual(tx.anchorAssetID, "asset-XYZ")
        _ = tx.transitionFinished()
        _ = tx.transitionFinished()
        XCTAssertEqual(tx.anchorAssetID, "asset-XYZ")
        tx.end()
        XCTAssertNil(tx.anchorAssetID, "end 后锚点释放")
        XCTAssertFalse(tx.isActive)
    }

    // MARK: - 回弹带

    func testEndedSnapbackWhenIdleCommitsImmediately() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-b", startColumns: 3, scale: 1)
        _ = tx.changed(scale: 1.5)
        _ = tx.markInFlight()
        _ = tx.transitionFinished()
        XCTAssertEqual(tx.ended(scale: 1.02), 3, "空闲回弹立即提交")
        XCTAssertEqual(tx.currentColumns, 3)
        XCTAssertTrue(tx.isBusy, "回弹提交产生新在途过渡")
        _ = tx.transitionFinished()
        XCTAssertFalse(tx.isBusy)
    }

    func testEndedSnapbackChainsWhileInFlight() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-c", startColumns: 3, scale: 1)
        _ = tx.changed(scale: 1.5)
        _ = tx.markInFlight()
        _ = tx.changed(scale: 0.5)
        XCTAssertNil(tx.ended(scale: 1.03), "在途回弹只挂链")
        XCTAssertEqual(tx.pendingTarget, 3, "最新者胜：回弹目标覆盖挂起")
        XCTAssertEqual(tx.transitionFinished(), 3, "回弹目标接续为在途")
        XCTAssertEqual(tx.inFlightColumns, 3, "接续的回弹过渡立即进入在途（单飞链）")
        _ = tx.transitionFinished()
        XCTAssertFalse(tx.isBusy)
    }

    // MARK: - 生命周期与消毒

    func testGestureEventsIgnoredAfterEnd() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-a", startColumns: 3, scale: 1)
        tx.end()
        XCTAssertNil(tx.changed(scale: 1.5))
        XCTAssertNil(tx.ended(scale: 1.02))
        XCTAssertNil(tx.markInFlight())
        XCTAssertNil(tx.transitionFinished())
        XCTAssertFalse(tx.isActive)
    }

    func testNaNZeroNegativeScaleIgnored() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-a", startColumns: 3, scale: 1)
        XCTAssertNil(tx.changed(scale: .nan))
        XCTAssertNil(tx.changed(scale: 0))
        XCTAssertNil(tx.changed(scale: -2))
        XCTAssertFalse(tx.isBusy)
    }

    func testStartScaleAndColumnsRecordedSanitized() {
        let tx = GridPinchTransaction()
        tx.begin(anchorAssetID: "asset-a", startColumns: 7, scale: .infinity)
        XCTAssertEqual(tx.startScale, 1)
        XCTAssertEqual(tx.startColumns, 5, "起始列数按配置钳制")
    }
}
