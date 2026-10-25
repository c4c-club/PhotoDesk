// MARK: - 职责说明：手势引擎（App 侧状态机）单测——判定纯逻辑在 PhotoDeskCore（Docker 全量覆盖），
// 这里验证 App 侧三件事：灵敏度 → SwipeConfig 映射、方向锁粘性（判向后不再改判）、finish 只在锁定时给出方向。

import XCTest
import PhotoDeskCore
@testable import PhotoDesk

final class SwipeResolverTests: XCTestCase {
    func testEngineConfigFromSensitivity() {
        let standard = SwipeGestureEngine.config(for: .standard, confirmDestructive: true)
        XCTAssertEqual(standard.distanceThreshold, 120)
        XCTAssertEqual(standard.velocityThreshold, 700)
        XCTAssertEqual(standard.minDistanceForVelocity, 40)
        XCTAssertTrue(standard.confirmRequired)

        let comfortable = SwipeGestureEngine.config(for: .comfortable, confirmDestructive: false)
        XCTAssertEqual(comfortable.distanceThreshold, 80)
        XCTAssertEqual(comfortable.velocityThreshold, 500)
        XCTAssertFalse(comfortable.confirmRequired)
    }

    func testEngineVerticalLockAndFinish() {
        let engine = SwipeGestureEngine(config: SwipeGestureEngine.config(for: .standard, confirmDestructive: true))
        engine.begin()
        // 慢速长距上滑：锁 up
        let output = engine.update(translation: CGSize(width: 5, height: -200), velocity: CGSize(width: 0, height: -300))
        XCTAssertEqual(output.direction, .up)
        XCTAssertTrue(output.locked)
        XCTAssertEqual(output.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(engine.finish(), .up)
        XCTAssertEqual(engine.phase, .idle)   // finish 后回 idle
    }

    func testEngineFinishNilWhenNotLocked() {
        let engine = SwipeGestureEngine(config: SwipeGestureEngine.config(for: .standard, confirmDestructive: true))
        engine.begin()
        // 慢速短距（< 120 且速度 0）：有方向无锁定
        let output = engine.update(translation: CGSize(width: 0, height: -80), velocity: .zero)
        XCTAssertEqual(output.direction, .up)
        XCTAssertFalse(output.locked)
        XCTAssertNil(engine.finish())
    }

    func testEngineHorizontalHandoff() {
        let engine = SwipeGestureEngine(config: SwipeGestureEngine.config(for: .standard, confirmDestructive: true))
        engine.begin()
        let output = engine.update(translation: CGSize(width: 150, height: 10), velocity: CGSize(width: 800, height: 0))
        XCTAssertTrue(output.isHorizontal)
        XCTAssertNil(output.direction)
        XCTAssertNil(engine.finish())
    }

    func testEngineDirectionLockIsSticky() {
        let engine = SwipeGestureEngine(config: SwipeGestureEngine.config(for: .standard, confirmDestructive: true))
        engine.begin()
        // 先判向 up（|dy| > 1.5|dx|）；随后横向位移变大也不改判（方向锁，docs/03 §5.1）
        _ = engine.update(translation: CGSize(width: 2, height: -60), velocity: .zero)
        let later = engine.update(translation: CGSize(width: 100, height: -120), velocity: .zero)
        XCTAssertEqual(later.direction, .up)
        XCTAssertFalse(later.isHorizontal)
    }

    func testEngineLockEdgeFiresOnce() {
        let engine = SwipeGestureEngine(config: SwipeGestureEngine.config(for: .standard, confirmDestructive: true))
        engine.begin()
        let first = engine.update(translation: CGSize(width: 0, height: -130), velocity: .zero)   // 越过阈值
        XCTAssertTrue(first.lockEdge)
        let second = engine.update(translation: CGSize(width: 0, height: -160), velocity: .zero)  // 保持锁定
        XCTAssertTrue(second.locked)
        XCTAssertFalse(second.lockEdge)
    }
}
