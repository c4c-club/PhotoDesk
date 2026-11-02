// MARK: - ReviewSessionTests：入队/去重/改标/恢复/顺序/上限/编解码（docs/09 D16 §8）

import XCTest
@testable import PhotoDeskCore

final class ReviewSessionTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_760_000_000)

    func testMarkDeleteKeepsEnqueueOrder() {
        var session = ReviewSession()
        session.markDelete("a", originIndex: 0, at: t)
        session.markDelete("b", originIndex: 1, at: t)
        session.markDelete("c", originIndex: 2, at: t)
        XCTAssertEqual(session.pendingDeleteIDs, ["a", "b", "c"], "提交按入队顺序")
        XCTAssertTrue(session.pendingHideIDs.isEmpty)
        XCTAssertEqual(session.count, 3)
    }

    func testMarkHideSeparateQueue() {
        var session = ReviewSession()
        session.markHide("h1", originIndex: 0, at: t)
        session.markDelete("d1", originIndex: 1, at: t)
        XCTAssertEqual(session.pendingHideIDs, ["h1"])
        XCTAssertEqual(session.pendingDeleteIDs, ["d1"])
    }

    func testMarkDuplicateIsNoopOnOrder() {
        var session = ReviewSession()
        session.markDelete("a", originIndex: 0, at: t)
        session.markDelete("b", originIndex: 1, at: t)
        session.markDelete("a", originIndex: 2, at: t)   // 重复：替换而非追加
        XCTAssertEqual(session.pendingDeleteIDs, ["b", "a"], "重复标记后 a 排到最后")
        XCTAssertEqual(session.count(of: .delete), 2)
    }

    func testMarkSwitchKindReplacesEntry() {
        var session = ReviewSession()
        session.markDelete("a", originIndex: 0, at: t)
        session.markHide("a", originIndex: 1, at: t)     // 改标：delete → hide
        XCTAssertTrue(session.pendingDeleteIDs.isEmpty)
        XCTAssertEqual(session.pendingHideIDs, ["a"])
        XCTAssertEqual(session.kind(of: "a"), .hide)
    }

    func testUnmark() {
        var session = ReviewSession()
        session.markDelete("a", originIndex: 0, at: t)
        session.markDelete("b", originIndex: 1, at: t)
        session.unmark("a", kind: .delete)
        XCTAssertEqual(session.pendingDeleteIDs, ["b"])
        // 错误类型 unmark 无副作用
        session.unmark("b", kind: .hide)
        XCTAssertEqual(session.pendingDeleteIDs, ["b"])
    }

    func testRemoveCommitted() {
        var session = ReviewSession()
        session.markDelete("a", originIndex: 0, at: t)
        session.markDelete("b", originIndex: 1, at: t)
        session.markHide("c", originIndex: 2, at: t)
        session.removeCommitted(["a", "c"], kind: .delete)   // c 不是 delete：不误伤 hide 队列
        XCTAssertEqual(session.pendingDeleteIDs, ["b"])
        XCTAssertEqual(session.pendingHideIDs, ["c"])
    }

    func testMaxEntriesEnforced() {
        var session = ReviewSession()
        for i in 0..<ReviewSession.maxEntries {
            session.markDelete("id-\(i)", originIndex: i, at: t)
        }
        XCTAssertEqual(session.count, ReviewSession.maxEntries)
        XCTAssertFalse(session.markDelete("overflow", originIndex: 0, at: t), "满员拒绝入队")
        XCTAssertEqual(session.count, ReviewSession.maxEntries)
    }

    func testCodableRoundTrip() throws {
        var session = ReviewSession()
        session.markDelete("a", originIndex: 3, at: t)
        session.markHide("b", originIndex: 4, at: t)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ReviewSession.self, from: data)
        XCTAssertEqual(decoded, session, "杀进程恢复：编解码等价")
        XCTAssertEqual(decoded.pendingDeleteIDs, ["a"])
        XCTAssertEqual(decoded.pendingHideIDs, ["b"])
    }
}
