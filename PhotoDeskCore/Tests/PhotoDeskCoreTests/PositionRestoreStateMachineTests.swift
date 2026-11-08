// MARK: - 职责说明：PositionRestoreStateMachine 测试（docs/22 §4.6）——
// 阶段迁移、bounds=0 不 done、3 次重试、3s 超时 failed、旧代际被拒、skip。

import XCTest
@testable import PhotoDeskCore

final class PositionRestoreStateMachineTests: XCTestCase {
    func testHappyPathTransitions() {
        var state = PositionRestoreState(maxAttempts: 3, timeout: 3)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.begin(generation: 1), .waitingSnapshot)
        XCTAssertEqual(state.snapshotAvailable(hasSections: true, boundsReady: false), .waitingLayout)
        XCTAssertEqual(state.layoutAvailable(hasSections: true, boundsReady: true,
                                             anchorPresent: true, indexComplete: true), .applying)
        XCTAssertEqual(state.applied(), .verifying)
        XCTAssertEqual(state.verified(ok: true), .done)
        XCTAssertFalse(state.isInFlight)
    }

    func testZeroBoundsNeverBecomesDone() {
        var state = PositionRestoreState()
        state.begin()
        _ = state.snapshotAvailable(hasSections: true, boundsReady: false)
        _ = state.layoutAvailable(hasSections: true, boundsReady: false,
                                  anchorPresent: true, indexComplete: true)
        XCTAssertEqual(state.phase, .waitingLayout)
        XCTAssertTrue(state.isInFlight)
        XCTAssertNotEqual(state.phase, .done)
    }

    func testMissingAnchorWhileIndexingStaysWaitingSnapshot() {
        var state = PositionRestoreState()
        state.begin()
        _ = state.snapshotAvailable(hasSections: true, boundsReady: true)
        _ = state.layoutAvailable(hasSections: true, boundsReady: true,
                                  anchorPresent: false, indexComplete: false)
        XCTAssertEqual(state.phase, .waitingSnapshot)
    }

    func testRetriesThreeTimesThenFails() {
        var state = PositionRestoreState(maxAttempts: 3)
        state.begin()
        _ = state.snapshotAvailable(hasSections: true, boundsReady: true)
        _ = state.applied()
        XCTAssertEqual(state.verified(ok: false), .applying)
        XCTAssertEqual(state.attempts, 1)
        _ = state.applied()
        XCTAssertEqual(state.verified(ok: false), .applying)
        XCTAssertEqual(state.attempts, 2)
        _ = state.applied()
        XCTAssertEqual(state.verified(ok: false), .failed)
        XCTAssertEqual(state.attempts, 3)
        XCTAssertFalse(state.isInFlight)
    }

    func testTimeoutFails() {
        var state = PositionRestoreState(timeout: 3)
        let start = Date(timeIntervalSince1970: 1000)
        state.begin(now: start)
        _ = state.snapshotAvailable(hasSections: true, boundsReady: false, now: start.addingTimeInterval(1))
        XCTAssertEqual(state.phase, .waitingLayout)
        XCTAssertTrue(state.timedOut(now: start.addingTimeInterval(3.01)))
        XCTAssertEqual(state.phase, .failed)
        XCTAssertFalse(state.isInFlight)
    }

    func testOldGenerationIsRejected() {
        var state = PositionRestoreState()
        state.begin(generation: 7)
        XCTAssertTrue(state.accepts(generation: 7))
        XCTAssertFalse(state.accepts(generation: 6), "旧代际保存必须被拒绝")
    }

    func testSkipCompletesWithoutRestore() {
        var state = PositionRestoreState()
        state.begin()
        XCTAssertEqual(state.skip(), .done)
        XCTAssertFalse(state.isInFlight)
    }
}
