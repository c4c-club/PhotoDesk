// MARK: - 职责说明：UndoPolicy 单元测试（docs/05 M3 验收）——
// 撤销窗口边界（恰好等于 window 可撤销 / 超 ε 过期）、Clock 注入、恢复路径判定。
// Docker 与 CI core-linux 双跑。

import XCTest
import Foundation
@testable import PhotoDeskCore

/// 假时钟（docs/03 §8：struct 化注入）
private struct FakeClock: Clock {
    var now: Date
}

final class UndoPolicyTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testWithinWindowAtExactBoundary() {
        let policy = UndoPolicy(window: 5)
        XCTAssertFalse(policy.isExpired(since: epoch, now: epoch.addingTimeInterval(5)),
                       "恰好等于窗口仍可撤销（严格大于才过期）")
    }

    func testExpiredJustPastBoundary() {
        let policy = UndoPolicy(window: 5)
        XCTAssertTrue(policy.isExpired(since: epoch, now: epoch.addingTimeInterval(5.001)))
    }

    func testAlternativeWindows() {
        for window in [3.0, 5.0, 10.0] {
            let policy = UndoPolicy(window: window)
            XCTAssertFalse(policy.isExpired(since: epoch, now: epoch.addingTimeInterval(window)))
            XCTAssertTrue(policy.isExpired(since: epoch, now: epoch.addingTimeInterval(window + 0.1)))
        }
    }

    func testIsWithinWindowWithInjectedClock() {
        let policy = UndoPolicy(window: 5)
        XCTAssertTrue(policy.isWithinWindow(since: epoch, clock: FakeClock(now: epoch.addingTimeInterval(4))))
        XCTAssertFalse(policy.isWithinWindow(since: epoch, clock: FakeClock(now: epoch.addingTimeInterval(6))))
    }

    func testSystemClockReturnsCurrentTime() {
        let clock = SystemClock()
        XCTAssertAbsDiff(clock.now.timeIntervalSinceNow, 0, accuracy: 1.0)
    }
}

/// TrashPolicy 容量淘汰（docs/03 §5.1：上限 2GB、按时间从旧到新）
final class TrashPolicyTests: XCTestCase {
    private func record(bytes: Int64, age: TimeInterval) -> PhotoDeskCore.TrashRecord {
        PhotoDeskCore.TrashRecord(id: UUID(),
                                  byteSize: bytes,
                                  createdAt: Date(timeIntervalSinceNow: -age))
    }

    func testNoEvictionUnderLimit() {
        let a = record(bytes: 400, age: 100)
        let b = record(bytes: 400, age: 10)
        XCTAssertTrue(TrashPolicy.evictionCandidates(from: [a, b], limitBytes: 1000).isEmpty)
    }

    func testEvictsOldestFirst() {
        let a = record(bytes: 600, age: 100)   // 最老
        let b = record(bytes: 600, age: 10)
        let candidates = TrashPolicy.evictionCandidates(from: [a, b], limitBytes: 1000)
        XCTAssertEqual(candidates, [a.id])     // 淘汰最老后总量 600 ≤ 1000
    }

    func testEvictsMultipleWhenNeeded() {
        let a = record(bytes: 800, age: 300)
        let b = record(bytes: 800, age: 200)
        let c = record(bytes: 800, age: 100)
        let candidates = TrashPolicy.evictionCandidates(from: [a, b, c], limitBytes: 1000)
        XCTAssertEqual(candidates, [a.id, b.id])   // 淘汰 a+b 后剩 800 ≤ 1000
    }

    func testExactlyAtLimitNoEviction() {
        let a = record(bytes: 500, age: 100)
        let b = record(bytes: 500, age: 10)
        XCTAssertTrue(TrashPolicy.evictionCandidates(from: [a, b], limitBytes: 1000).isEmpty)
    }

    func testEmptyInput() {
        XCTAssertTrue(TrashPolicy.evictionCandidates(from: [], limitBytes: 1000).isEmpty)
    }
}

private func XCTAssertAbsDiff<T: FloatingPoint>(_ a: T, _ b: T, accuracy: T, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThan(abs(a - b), accuracy, file: file, line: line)
}
