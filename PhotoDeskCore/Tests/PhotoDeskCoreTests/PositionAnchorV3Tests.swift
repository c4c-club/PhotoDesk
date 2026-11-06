// MARK: - 职责说明：位置锚点 v3 单测——v1/v2 解码兼容、视觉锚点像素恢复、逐级 fallback、恢复期零回写门禁；纯 Linux swift test 可跑。

import XCTest
@testable import PhotoDeskCore

final class PositionAnchorV3Tests: XCTestCase {
    private func v2JSON() -> Data {
        let json = """
        {"assetID":"old-asset","sectionID":"2026-11","itemIndexInSection":7,"offsetRatio":0.42,"savedAt":0,"schemaVersion":2}
        """
        return Data(json.utf8)
    }

    private func v1JSON() -> Data {
        let json = """
        {"assetID":"v1-asset","sectionID":"2024-05","offsetRatio":0.1,"savedAt":0}
        """
        return Data(json.utf8)
    }

    func testCurrentSchemaVersionIsThree() {
        XCTAssertEqual(PositionAnchorPolicy.schemaVersion, 3)
        let anchor = PositionAnchorV3(
            anchorAssetID: "a",
            anchorVisualY: 12,
            anchorContentOffsetY: 1000,
            assetID: "a",
            sectionID: "s"
        )
        XCTAssertEqual(anchor.schemaVersion, 3)
    }

    func testV2DecodeFallsBackToLegacyAssetFields() throws {
        let anchor = try JSONDecoder().decode(PositionAnchorV3.self, from: v2JSON())
        XCTAssertEqual(anchor.schemaVersion, 2)
        XCTAssertEqual(anchor.anchorAssetID, "old-asset")
        XCTAssertEqual(anchor.assetID, "old-asset")
        XCTAssertEqual(anchor.sectionID, "2026-11")
        XCTAssertEqual(anchor.itemIndexInSection, 7)
        XCTAssertEqual(anchor.offsetRatio, 0.42)
        XCTAssertEqual(anchor.anchorVisualY, 0)
        XCTAssertEqual(anchor.anchorContentOffsetY, 0)
    }

    func testV1DecodeUsesSafeDefaults() throws {
        let anchor = try JSONDecoder().decode(PositionAnchorV3.self, from: v1JSON())
        XCTAssertEqual(anchor.schemaVersion, 1)
        XCTAssertEqual(anchor.anchorAssetID, "v1-asset")
        XCTAssertEqual(anchor.itemIndexInSection, 0)
        XCTAssertEqual(anchor.sectionID, "2024-05")
    }

    func testV3EncodeDecodeRoundTripPreservesAnchor() throws {
        let original = PositionAnchorV3(
            anchorAssetID: "asset-42",
            anchorVisualY: 37.5,
            anchorContentOffsetY: 2480,
            assetID: "asset-42",
            sectionID: "2026-11",
            itemIndexInSection: 5,
            offsetRatio: 0.8,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PositionAnchorV3.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.anchorVisualY, 37.5)
        XCTAssertEqual(decoded.anchorContentOffsetY, 2480)
    }

    func testVisualYIsCellMinYMinusContentOffset() {
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: 1000, contentOffsetY: 960), 40)
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: 960, contentOffsetY: 1000), -40)
        XCTAssertEqual(PositionAnchorPolicy.visualY(cellMinY: .nan, contentOffsetY: 100), 0)
    }

    func testRestoreUsesPixelOffsetNotCentered() {
        let anchor = PositionAnchorV3(
            anchorAssetID: "a", anchorVisualY: 40, anchorContentOffsetY: 960,
            assetID: "a", sectionID: "s"
        )
        let result = PositionAnchorPolicy.resolve(
            anchor: anchor,
            assetCellMinY: 1000,
            sectionCellMinY: nil,
            contentHeight: 5000,
            viewportHeight: 800,
            adjustedTop: 44,
            bottomInset: 0
        )
        XCTAssertEqual(result.strategy, .asset)
        XCTAssertEqual(result.offsetY, 960, accuracy: 0.001)
    }

    func testMissingAssetFallsBackToSectionThenRatio() {
        let anchor = PositionAnchorV3(
            anchorAssetID: "missing", anchorVisualY: 40, anchorContentOffsetY: 900,
            assetID: "missing", sectionID: "2026-11", itemIndexInSection: 3, offsetRatio: 0.5
        )
        let section = PositionAnchorPolicy.resolve(
            anchor: anchor, assetCellMinY: nil, sectionCellMinY: 1200,
            contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0
        )
        XCTAssertEqual(section.strategy, .section)
        XCTAssertEqual(section.offsetY, 1200)

        let ratio = PositionAnchorPolicy.resolve(
            anchor: anchor, assetCellMinY: nil, sectionCellMinY: nil,
            contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0
        )
        XCTAssertEqual(ratio.strategy, .ratio)
        let expected = -44 + (5000 - 800) * 0.5
        XCTAssertEqual(ratio.offsetY, expected, accuracy: 0.001)
    }

    func testEmptyAnchorHasNoRestoreWork() {
        let anchor = PositionAnchorV3(
            anchorAssetID: "", anchorVisualY: 0, anchorContentOffsetY: 0,
            assetID: "", sectionID: "", offsetRatio: 0
        )
        let result = PositionAnchorPolicy.resolve(
            anchor: anchor, assetCellMinY: nil, sectionCellMinY: nil,
            contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0
        )
        XCTAssertEqual(result.strategy, .none)
        XCTAssertEqual(result.offsetY, 0)
    }

    func testTargetOffsetIsClampedToValidRange() {
        let high = PositionAnchorPolicy.clampedTargetOffsetY(
            99999, contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0
        )
        XCTAssertEqual(high, 4200)
        let low = PositionAnchorPolicy.clampedTargetOffsetY(
            -99999, contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0
        )
        XCTAssertEqual(low, -44)
    }

    func testFinishRequiresLayoutSnapshotAndOffsetApplied() {
        XCTAssertFalse(PositionAnchorPolicy.canFinish(
            boundsWidth: 390, boundsHeight: 800, numberOfSections: 1,
            snapshotDrained: true, offsetApplied: false
        ))
        XCTAssertFalse(PositionAnchorPolicy.canFinish(
            boundsWidth: 390, boundsHeight: 800, numberOfSections: 0,
            snapshotDrained: true, offsetApplied: true
        ))
        XCTAssertFalse(PositionAnchorPolicy.canFinish(
            boundsWidth: 0, boundsHeight: 800, numberOfSections: 1,
            snapshotDrained: true, offsetApplied: true
        ))
        XCTAssertTrue(PositionAnchorPolicy.canFinish(
            boundsWidth: 390, boundsHeight: 800, numberOfSections: 1,
            snapshotDrained: true, offsetApplied: true
        ))
    }

    func testNoWritebackDuringRestoreInFlight() {
        XCTAssertFalse(PositionAnchorPolicy.allowsWriteback(isRestoreInFlight: true))
        XCTAssertTrue(PositionAnchorPolicy.allowsWriteback(isRestoreInFlight: false))
    }

    func testNonFiniteAnchorOffsetIsSafe() {
        let anchor = PositionAnchorV3(
            anchorAssetID: "a", anchorVisualY: .nan, anchorContentOffsetY: .infinity,
            assetID: "a", sectionID: "s"
        )
        let result = PositionAnchorPolicy.resolve(
            anchor: anchor, assetCellMinY: 1000, sectionCellMinY: nil,
            contentHeight: 5000, viewportHeight: 800, adjustedTop: 44, bottomInset: 0
        )
        XCTAssertEqual(result.strategy, .asset)
        XCTAssertEqual(result.offsetY, 1000)
    }
}
