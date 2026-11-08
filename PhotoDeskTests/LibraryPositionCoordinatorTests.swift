// MARK: - 职责说明：位置记忆 v4 协调器单测（docs/22 §4.6）——
// 零 bounds 重试、旧防抖保存不得覆盖新锚点、恢复期零回写、状态机 done 收敛。

import XCTest
import UIKit
@testable import PhotoDesk
import PhotoDeskCore

@MainActor
final class LibraryPositionCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "PositionCoordinator-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if !suiteName.isEmpty {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    private func snapshot(_ anchor: String,
                          visualY: Double = 40,
                          queryKey: String = "scope.all") -> LibraryPositionSnapshot {
        LibraryPositionSnapshot(queryKey: queryKey,
                                anchorAssetID: anchor,
                                anchorVisualY: visualY,
                                anchorSectionID: "2026-11",
                                anchorItemIndex: 3,
                                contentOffsetY: 900,
                                contentHeight: 5_000,
                                viewportHeight: 844)
    }

    func testStaleSaveTimerDoesNotOverwriteNewAnchor() {
        let store = LibraryPositionStore(defaults: defaults)
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.scheduleSave(reason: "old", snapshot: snapshot("old-anchor"), debounce: 0.2)
        coordinator.saveNow(reason: "new", snapshot: snapshot("new-anchor"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "new-anchor")

        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "new-anchor",
                       "旧 revision 的防抖保存必须被丢弃，不得覆盖新锚点")
    }

    func testRestoreInFlightBlocksAllWrites() {
        let store = LibraryPositionStore(defaults: defaults)
        store.save(LibraryPosition(assetID: "saved-anchor",
                                   sectionID: "2026-11",
                                   itemIndexInSection: 2,
                                   offsetRatio: 0.5,
                                   savedAt: Date()),
                   queryKey: "scope.all")
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        XCTAssertTrue(coordinator.isRestoreInFlight, "begin 后必须处于恢复中")

        coordinator.saveNow(reason: "intermediate", snapshot: snapshot("new-position"))
        XCTAssertEqual(store.load(queryKey: "scope.all")?.anchorAssetID, "saved-anchor",
                       "恢复期内的任何保存都必须被拒绝，锚点不能被中间位置覆盖")
    }

    func testRestoreRetriesAfterZeroBounds() {
        let store = LibraryPositionStore(defaults: defaults)
        store.save(LibraryPosition(anchorAssetID: "target",
                                   anchorVisualY: 40,
                                   anchorContentOffsetY: 900,
                                   assetID: "target",
                                   sectionID: "2026-11",
                                   itemIndexInSection: 3,
                                   offsetRatio: 0.2,
                                   contentHeight: 5_000,
                                   viewportHeight: 844,
                                   savedAt: Date()),
                   queryKey: "scope.all")
        let coordinator = LibraryPositionCoordinator(store: store)
        coordinator.beginRestore(queryKey: "scope.all")
        XCTAssertEqual(coordinator.phase, .waitingSnapshot)

        var actualOffset: Double = 0
        func context(bounds: CGSize) -> LibraryPositionRestoreContext {
            LibraryPositionRestoreContext(
                bounds: bounds,
                numberOfSections: 1,
                isIndexComplete: true,
                contentHeight: 5_000,
                viewportHeight: 844,
                adjustedTop: 0,
                bottomInset: 0,
                anchorMinY: { id in id == "target" ? 1_000 : nil },
                sectionMinY: { _, _ in nil },
                applyOffset: { actualOffset = $0 },
                actualOffsetY: { actualOffset }
            )
        }

        coordinator.attemptRestore(context: context(bounds: .zero))
        XCTAssertEqual(coordinator.phase, .waitingLayout, "bounds=0 必须停在 waitingLayout，不能 done")

        coordinator.attemptRestore(context: context(bounds: CGSize(width: 390, height: 844)))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, coordinator.phase != .done {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(coordinator.phase, .done, "bounds 就绪后必须重试并完成")
        XCTAssertEqual(actualOffset, 960, accuracy: 0.5, "target = minY 1000 - visualY 40")
    }
}
