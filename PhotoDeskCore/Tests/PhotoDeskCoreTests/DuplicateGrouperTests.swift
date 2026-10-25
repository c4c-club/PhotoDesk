// MARK: - 职责说明：DuplicateGrouper 单元测试（docs/05 M4 验收）——
// 分桶（宽高比 ±0.02 + |Δt| ≤ 2s）、汉明阈值边界（≤4 高置信 / ≤8 疑似 / >8 不组）、
// 推荐保留比较器（原图 > 面积 > 最新修改）。Docker 与 CI core-linux 双跑。

import XCTest
import Foundation
@testable import PhotoDeskCore

final class DuplicateGrouperTests: XCTestCase {
    private func candidate(id: String,
                           dhash: UInt64,
                           aspect: Double = 1.0,
                           secondsAgo: TimeInterval = 0,
                           pixelArea: Int = 1000,
                           hasEdits: Bool = false,
                           modifiedSecondsAgo: TimeInterval = 0) -> DuplicateCandidate {
        DuplicateCandidate(id: id,
                           dhash: dhash,
                           phash: nil,
                           aspect: aspect,
                           createdAt: Date(timeIntervalSinceNow: -secondsAgo),
                           pixelArea: pixelArea,
                           hasEdits: hasEdits,
                           modificationDate: Date(timeIntervalSinceNow: -modifiedSecondsAgo))
    }

    // MARK: - 基础

    func testHammingDistance() {
        XCTAssertEqual(DuplicateGrouper.hammingDistance(0, 0), 0)
        XCTAssertEqual(DuplicateGrouper.hammingDistance(0, .max), 64)
        XCTAssertEqual(DuplicateGrouper.hammingDistance(0b1010, 0b0110), 2)
    }

    func testSingleAndEmptyInput() {
        XCTAssertTrue(DuplicateGrouper.groups(from: [], distanceThreshold: 8).isEmpty)
        let one = [candidate(id: "a", dhash: 0b1111)]
        XCTAssertTrue(DuplicateGrouper.groups(from: one, distanceThreshold: 8).isEmpty)
    }

    // MARK: - 分桶与阈值

    func testGroupsNearDuplicatesWithinTimeWindow() {
        // 三张同批（|Δt| ≤ 2s）、同比例、汉明距离 1/2 → 一组
        let a = candidate(id: "a", dhash: 0b0000)
        let b = candidate(id: "b", dhash: 0b0001, secondsAgo: 1)
        let c = candidate(id: "c", dhash: 0b0011, secondsAgo: 2)
        let groups = DuplicateGrouper.groups(from: [a, b, c], distanceThreshold: 8)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].members), Set(["a", "b", "c"]))
        XCTAssertLessThanOrEqual(groups[0].minHammingDistance, 4)   // a-b 距离 1 → 高置信
    }

    func testTimeWindowExcluded() {
        // 相差 3s（> 2s 窗口）：即使哈希接近也不组
        let a = candidate(id: "a", dhash: 0b0000, secondsAgo: 0)
        let b = candidate(id: "b", dhash: 0b0001, secondsAgo: 3)
        XCTAssertTrue(DuplicateGrouper.groups(from: [a, b], distanceThreshold: 8).isEmpty)
    }

    func testAspectRatioExcluded() {
        // 宽高比差 0.05（> 0.02）：不组（竖拍 vs 横拍不误判）
        let a = candidate(id: "a", dhash: 0b0000, aspect: 1.0)
        let b = candidate(id: "b", dhash: 0b0001, aspect: 1.05, secondsAgo: 1)
        XCTAssertTrue(DuplicateGrouper.groups(from: [a, b], distanceThreshold: 8).isEmpty)
    }

    func testDistanceThresholdBoundary() {
        let a = candidate(id: "a", dhash: 0)
        // 距离恰 8（疑似重复）：阈值 8 → 组；阈值 7 → 不组
        let distance8 = candidate(id: "b", dhash: 0xFF)
        XCTAssertFalse(DuplicateGrouper.groups(from: [a, distance8], distanceThreshold: 8).isEmpty)
        XCTAssertTrue(DuplicateGrouper.groups(from: [a, distance8], distanceThreshold: 7).isEmpty)
        // 距离 9：阈值 8 → 不组
        let distance9 = candidate(id: "c", dhash: (1 << 8) | 0xFF)
        XCTAssertTrue(DuplicateGrouper.groups(from: [a, distance9], distanceThreshold: 8).isEmpty)
    }

    func testHighConfidenceBadge() {
        let a = candidate(id: "a", dhash: 0)
        let distance2 = candidate(id: "b", dhash: 0b0110, secondsAgo: 1)   // 距离 2 ≤ 4
        let groups = DuplicateGrouper.groups(from: [a, distance2], distanceThreshold: 8)
        XCTAssertLessThanOrEqual(groups[0].minHammingDistance, 4)
    }

    func testChainGroupingTransitivity() {
        // a-b 距离 1、b-c 距离 1（a-c 距离 2）→ 传递闭包成一组（并查集）
        let a = candidate(id: "a", dhash: 0b0000, secondsAgo: 0)
        let b = candidate(id: "b", dhash: 0b0001, secondsAgo: 1)
        let c = candidate(id: "c", dhash: 0b0011, secondsAgo: 2)
        let d = candidate(id: "d", dhash: 0b1111_0000_1111_0000, secondsAgo: 100)   // 完全无关
        let groups = DuplicateGrouper.groups(from: [a, b, c, d], distanceThreshold: 8)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].members), Set(["a", "b", "c"]))
    }

    // MARK: - 推荐保留（原图 > 面积 > 最新修改）

    func testRecommendPrefersOriginalOverEdited() {
        let edited = candidate(id: "edited", dhash: 0, pixelArea: 10_000_000, hasEdits: true)
        let original = candidate(id: "original", dhash: 0, pixelArea: 1000, hasEdits: false)
        XCTAssertEqual(DuplicateGrouper.recommendedKeep([edited, original]).id, "original")
    }

    func testRecommendPrefersLargerArea() {
        let small = candidate(id: "small", dhash: 0, pixelArea: 1000, hasEdits: false)
        let large = candidate(id: "large", dhash: 0, pixelArea: 10_000_000, hasEdits: false)
        XCTAssertEqual(DuplicateGrouper.recommendedKeep([small, large]).id, "large")
    }

    func testRecommendPrefersLatestModification() {
        let older = candidate(id: "older", dhash: 0, pixelArea: 1000,
                              hasEdits: false, modifiedSecondsAgo: 100)
        let newer = candidate(id: "newer", dhash: 0, pixelArea: 1000,
                              hasEdits: false, modifiedSecondsAgo: 5)
        XCTAssertEqual(DuplicateGrouper.recommendedKeep([older, newer]).id, "newer")
    }
}
