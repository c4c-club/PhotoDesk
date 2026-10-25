// MARK: - 职责说明：包级冒烟测试——验证 PhotoDeskCore 可导入、全部占位模块可编译可链接（M0 骨架验收，
// 本机 Docker swift:6.0-noble 与 CI core-linux 共用）。业务逻辑的正式单测自 P1/P4 随实现补充。

import XCTest
import PhotoDeskCore

final class SmokeTests: XCTestCase {
    func testPackageImportsAndAllPlaceholdersLink() {
        XCTAssertFalse(PhotoDeskCoreInfo.placeholderVersion.isEmpty)

        // 手势判定（P2 已实现）：横向不判向；500pt 垂直位移必锁
        let resolver = SwipeResolver(config: SwipeConfig(distanceThreshold: 120,
                                                         velocityThreshold: 700,
                                                         minDistanceForVelocity: 40,
                                                         confirmRequired: true))
        XCTAssertNil(resolver.direction(dx: 100, dy: 0))
        XCTAssertTrue(resolver.isLocked(dx: 0, dy: 500, vx: 0, vy: 1000))
        XCTAssertEqual(resolver.direction(dx: 0, dy: -500), .up)
        XCTAssertEqual(Sensitivity.allCases.count, 3)

        // 撤销 / 分组占位
        XCTAssertFalse(UndoPolicy(window: 5).isExpired(since: Date(), now: Date()))
        XCTAssertTrue(DateSectionizer.sections(ids: [], dates: [], granularity: .month).isEmpty)

        // 哈希 / 去重 / 回收站淘汰占位
        XCTAssertNil(DHash.compute(grayscale: [0, 255], width: 2, height: 1))
        XCTAssertNil(PHash.compute(grayscale: [0, 255], width: 2, height: 1))
        XCTAssertEqual(DuplicateGrouper.hammingDistance(0, 0), 0)
        XCTAssertTrue(TrashPolicy.evictionCandidates(from: [], limitBytes: 1024).isEmpty)
    }
}
