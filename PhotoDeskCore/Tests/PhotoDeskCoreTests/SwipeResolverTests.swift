// MARK: - 职责说明：SwipeResolver 单元测试（docs/03 §8 / docs/05 M2 任务 2.3）——
// 方向 1.5× 边界、阈值锁定、速度触发、progress 归一、灵敏度档位数值。Docker 与 CI core-linux 双跑。

import XCTest
@testable import PhotoDeskCore

final class SwipeResolverTests: XCTestCase {
    /// 标准（默认）档位：距离 120、速度 700、最小速度距离 40
    private let standard = SwipeConfig(distanceThreshold: 120,
                                       velocityThreshold: 700,
                                       minDistanceForVelocity: 40,
                                       confirmRequired: true)

    // MARK: - 方向判定（|dy| > 1.5|dx|，严格大于）

    func testDirectionPureVertical() {
        let resolver = SwipeResolver(config: standard)
        XCTAssertEqual(resolver.direction(dx: 0, dy: -10), .up)
        XCTAssertEqual(resolver.direction(dx: 0, dy: 10), .down)
    }

    func testDirectionBoundaryExactlyOneAndHalf() {
        let resolver = SwipeResolver(config: standard)
        // |dy| == 1.5|dx|：不满足严格大于 → 让位给横翻页
        XCTAssertNil(resolver.direction(dx: 100, dy: -150))
        XCTAssertNil(resolver.direction(dx: 100, dy: 150))
    }

    func testDirectionJustPastBoundary() {
        let resolver = SwipeResolver(config: standard)
        XCTAssertEqual(resolver.direction(dx: 100, dy: -151), .up)
        XCTAssertEqual(resolver.direction(dx: 100, dy: 151), .down)
    }

    func testDirectionHorizontalReturnsNil() {
        let resolver = SwipeResolver(config: standard)
        XCTAssertNil(resolver.direction(dx: 100, dy: 0))
        XCTAssertNil(resolver.direction(dx: 300, dy: 100))   // 明显横向
    }

    func testDirectionSmallTranslationAmbiguous() {
        let resolver = SwipeResolver(config: standard)
        // 起手阶段位移很小且比值未达 1.5：不判向
        XCTAssertNil(resolver.direction(dx: 4, dy: -5))
    }

    // MARK: - progress（以距离阈值归一，0...1）

    func testProgressLinear() {
        let resolver = SwipeResolver(config: standard)
        XCTAssertEqual(resolver.progress(dx: 0, dy: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(resolver.progress(dx: 0, dy: -60), 0.5, accuracy: 0.0001)
        XCTAssertEqual(resolver.progress(dx: 0, dy: 60), 0.5, accuracy: 0.0001)   // 进度取绝对值
        XCTAssertEqual(resolver.progress(dx: 0, dy: -240), 1.0, accuracy: 0.0001) // 上限 1
        XCTAssertEqual(resolver.progress(dx: 300, dy: 0), 0, accuracy: 0.0001)    // 水平位移不计入
    }

    // MARK: - 锁定（距离达标 或 速度达标 + 距离 ≥ minDistanceForVelocity）

    func testLockedByDistance() {
        let resolver = SwipeResolver(config: standard)
        XCTAssertFalse(resolver.isLocked(dx: 0, dy: 119, vx: 0, vy: 0))
        XCTAssertTrue(resolver.isLocked(dx: 0, dy: 120, vx: 0, vy: 0))
        XCTAssertTrue(resolver.isLocked(dx: 0, dy: -120, vx: 0, vy: 0))  // 方向无关，取绝对值
    }

    func testLockedByVelocity() {
        let resolver = SwipeResolver(config: standard)
        // 速度达标但距离不足（< 40）：不锁
        XCTAssertFalse(resolver.isLocked(dx: 0, dy: -39, vx: 0, vy: -900))
        // 速度达标 + 距离恰达最小距离：锁
        XCTAssertTrue(resolver.isLocked(dx: 0, dy: -40, vx: 0, vy: -900))
        // 快速滑动 100pt（未到距离阈值但 ≥ 40，速度 ≥ 700）：锁
        XCTAssertTrue(resolver.isLocked(dx: 0, dy: -100, vx: 0, vy: -700))
        // 速度差 1：不锁
        XCTAssertFalse(resolver.isLocked(dx: 0, dy: -100, vx: 0, vy: -699))
    }

    func testLockedUsesVerticalAxisOnly() {
        let resolver = SwipeResolver(config: standard)
        // 大水平速度/距离不参与锁定（水平让位给分页器）
        XCTAssertFalse(resolver.isLocked(dx: 500, dy: 0, vx: 2000, vy: 0))
    }

    // MARK: - 灵敏度档位（docs/04 §3.4 舒适/标准/保守）

    func testSensitivityPresets() {
        XCTAssertEqual(Sensitivity.comfortable.distanceThreshold, 80)
        XCTAssertEqual(Sensitivity.standard.distanceThreshold, 120)
        XCTAssertEqual(Sensitivity.conservative.distanceThreshold, 180)
        XCTAssertEqual(Sensitivity.comfortable.velocityThreshold, 500)
        XCTAssertEqual(Sensitivity.standard.velocityThreshold, 700)
        XCTAssertEqual(Sensitivity.conservative.velocityThreshold, 900)
    }

    func testConservativeRequiresLongerDistance() {
        let conservative = SwipeResolver(config: SwipeConfig(distanceThreshold: 180,
                                                             velocityThreshold: 900,
                                                             minDistanceForVelocity: 40,
                                                             confirmRequired: true))
        let standardResolver = SwipeResolver(config: standard)
        // 同样慢速 150pt：标准档已锁，保守档未锁
        XCTAssertTrue(standardResolver.isLocked(dx: 0, dy: 150, vx: 0, vy: 0))
        XCTAssertFalse(conservative.isLocked(dx: 0, dy: 150, vx: 0, vy: 0))
        XCTAssertTrue(conservative.isLocked(dx: 0, dy: 180, vx: 0, vy: 0))
    }
}
