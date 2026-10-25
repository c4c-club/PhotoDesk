// MARK: - 职责说明：ExportOptions 单元测试（docs/05 M6 验收）——
// 长边尺寸计算（横/竖/只缩不放）、质量钳制、格式→UTI 映射。Docker 与 CI core-linux 双跑。

import XCTest
import Foundation
@testable import PhotoDeskCore

final class ExportOptionsTests: XCTestCase {
    // MARK: - 长边尺寸（保持宽高比、只缩小不放大）

    func testLandscapeDownscaleTo2048() {
        let size = ExportOptions.outputSize(originalWidth: 4000, originalHeight: 3000, longEdge: .edge2048)
        XCTAssertEqual(size.width, 2048)
        XCTAssertEqual(size.height, 1536)
    }

    func testPortraitDownscaleKeepsAspect() {
        let size = ExportOptions.outputSize(originalWidth: 3024, originalHeight: 4032, longEdge: .edge2048)
        XCTAssertEqual(size.width, 1536)
        XCTAssertEqual(size.height, 2048)
    }

    func testOriginalLongEdgeKeepsSize() {
        let size = ExportOptions.outputSize(originalWidth: 4000, originalHeight: 3000, longEdge: .original)
        XCTAssertEqual(size.width, 4000)
        XCTAssertEqual(size.height, 3000)
    }

    func testNeverUpscales() {
        // 原图长边 800 < 2048：保持原尺寸（只缩小不放大）
        let size = ExportOptions.outputSize(originalWidth: 600, originalHeight: 800, longEdge: .edge2048)
        XCTAssertEqual(size.width, 600)
        XCTAssertEqual(size.height, 800)
    }

    func testMinimumOnePixel() {
        let size = ExportOptions.outputSize(originalWidth: 2, originalHeight: 1, longEdge: .edge4096)
        XCTAssertEqual(size.width, 2)
        XCTAssertEqual(size.height, 1)
    }

    // MARK: - 质量钳制

    func testQualityClamped() {
        XCTAssertEqual(ExportOptions.clampQuality(0.8), 0.8, accuracy: 0.0001)
        XCTAssertEqual(ExportOptions.clampQuality(1.5), 1, accuracy: 0.0001)
        XCTAssertEqual(ExportOptions.clampQuality(-0.2), 0, accuracy: 0.0001)
        let options = ExportOptions(quality: 3)
        XCTAssertEqual(options.quality, 1, accuracy: 0.0001)
    }

    // MARK: - 格式 → UTI

    func testFileTypeMapping() {
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: "public.heic", format: .jpeg), "public.jpeg")
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: nil, format: .png), "public.png")
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: nil, format: .heic), "public.heic")
        // original：沿用源 UTI
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: "public.heic", format: .original), "public.heic")
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: "public.png", format: .original), "public.png")
        // original：未知源回退 JPEG
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: nil, format: .original), "public.jpeg")
        XCTAssertEqual(ExportOptions.fileTypeFor(originalUTI: "com.adobe.raw-image", format: .original), "public.jpeg")
    }

    func testDefaults() {
        let options = ExportOptions()
        XCTAssertEqual(options.format, .jpeg)
        XCTAssertEqual(options.longEdge, .original)
        XCTAssertEqual(options.quality, 0.8, accuracy: 0.0001)
        XCTAssertFalse(options.stripLocation)
    }
}
