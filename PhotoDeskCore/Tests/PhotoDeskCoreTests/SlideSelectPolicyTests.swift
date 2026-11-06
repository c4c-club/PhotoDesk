import XCTest
@testable import PhotoDeskCore

final class SlideSelectPolicyTests: XCTestCase {
    private let a = SlideSelectCell(section: 0, item: 0)
    private let b = SlideSelectCell(section: 0, item: 1)
    private let c = SlideSelectCell(section: 0, item: 2)

    func testHorizontalWinsOnlyWhenStrictlyGreater() {
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: 12, dy: 3, wasLocked: false), .horizontal)
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: -12, dy: -3, wasLocked: false), .horizontal)
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: 12, dy: 12, wasLocked: false), .verticalLocked)
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: 2, dy: 12, wasLocked: false), .verticalLocked)
    }

    func testVerticalLockNeverReactivatesInSameGesture() {
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: 20, dy: 1, wasLocked: true), .verticalLocked)
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: 0, dy: 0, wasLocked: true), .none)
    }

    func testZeroAndNonFiniteNeverActivate() {
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: 0, dy: 0, wasLocked: false), .none)
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: .nan, dy: 1, wasLocked: false), .verticalLocked)
        XCTAssertEqual(SlideSelectPolicy.shouldActivate(dx: .infinity, dy: 2, wasLocked: false), .verticalLocked)
    }

    func testVisitedCellsBecomeSelected() {
        let result = SlideSelectPolicy.resolvedSelection(originallySelected: [], visited: [a, b, c])
        XCTAssertEqual(result[a], true)
        XCTAssertEqual(result[b], true)
        XCTAssertEqual(result[c], true)
    }

    func testOriginallySelectedCellsAreNeverCleared() {
        let result = SlideSelectPolicy.resolvedSelection(originallySelected: [a], visited: [a, b, a, b])
        XCTAssertEqual(result[a], true)
        XCTAssertEqual(result[b], false)
    }

    func testSlidingBackRestoresSnapshotForUnselectedCells() {
        let result = SlideSelectPolicy.resolvedSelection(originallySelected: [], visited: [a, b, c, a, b])
        XCTAssertEqual(result[a], false)
        XCTAssertEqual(result[b], false)
        XCTAssertEqual(result[c], true)
    }

    func testThirdPassSelectsAgain() {
        let result = SlideSelectPolicy.resolvedSelection(originallySelected: [], visited: [a, b, a, b, a])
        XCTAssertEqual(result[a], true)
        XCTAssertEqual(result[b], false)
    }

    func testDeduplicatedKeepsConsecutiveOrderOnly() {
        let cells = [a, a, b, b, a, c, c]
        XCTAssertEqual(SlideSelectPolicy.deduplicated(cells), [a, b, a, c])
    }

    func testEmptyVisitedHasNoSelectionWrites() {
        XCTAssertTrue(SlideSelectPolicy.resolvedSelection(originallySelected: [], visited: []).isEmpty)
        XCTAssertEqual(SlideSelectPolicy.deduplicated([]), [])
    }

    func testTopEdgeVelocityIsNegativeAndProportional() {
        let atEdge = SlideSelectPolicy.edgeVelocity(fingerY: 0, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        let nearEdge = SlideSelectPolicy.edgeVelocity(fingerY: 30, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        XCTAssertLessThan(atEdge, 0)
        XCTAssertLessThan(nearEdge, 0)
        XCTAssertGreaterThan(atEdge.magnitude, nearEdge.magnitude)
        XCTAssertGreaterThanOrEqual(atEdge.magnitude, 1)
        XCTAssertLessThanOrEqual(atEdge.magnitude, 18)
    }

    func testBottomEdgeVelocityIsPositiveAndProportional() {
        let atEdge = SlideSelectPolicy.edgeVelocity(fingerY: 800, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        let nearEdge = SlideSelectPolicy.edgeVelocity(fingerY: 780, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18)
        XCTAssertGreaterThan(atEdge, 0)
        XCTAssertGreaterThan(nearEdge, 0)
        XCTAssertGreaterThan(atEdge, nearEdge)
        XCTAssertLessThanOrEqual(atEdge, 18)
    }

    func testOutsideBufferHasZeroVelocity() {
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 61, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 739, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 400, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
    }

    func testInvalidBufferOrStepsReturnZero() {
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 10, top: 0, bottom: 800, buffer: 0, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: .nan, top: 0, bottom: 800, buffer: 60, minStep: 1, maxStep: 18), 0)
        XCTAssertEqual(SlideSelectPolicy.edgeVelocity(fingerY: 10, top: 0, bottom: 800, buffer: 60, minStep: 18, maxStep: 1), 0)
    }

    func testClampedOffsetKeepsBounds() {
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: 5, min: -44, max: 900), 105)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: -1000, min: -44, max: 900), -44)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: 1000, min: -44, max: 900), 900)
    }

    func testClampedOffsetHandlesReversedAndNonFiniteInputs() {
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: 5, min: 900, max: -44), 105)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: .nan, delta: 5, min: -44, max: 900), -44)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: .infinity, min: -44, max: 900), 900)
        XCTAssertEqual(SlideSelectPolicy.clampedOffset(current: 100, delta: -.infinity, min: -44, max: 900), -44)
    }
}
