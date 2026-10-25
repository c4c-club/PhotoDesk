// MARK: - 职责说明：ExportRenderer 集成测试（docs/05 M6 验收）——
// 合成 JPEG（带 GPS 的 EXIF）→ 导出（剥离/保留）→ CGImageSource 读回验证：
// 长边 2048 尺寸一致、quality 生效（文件存在）、stripLocation 后无 GPS、保留时 GPS 在。
// 纯文件进出（不依赖相册授权）。

import XCTest
import ImageIO
import PhotoDeskCore
import UniformTypeIdentifiers
@testable import PhotoDesk

final class ExportRendererTests: XCTestCase {
    private var sourceURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString).jpg")
        try Self.writeSampleJPEG(to: sourceURL, width: 800, height: 600, withGPS: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceURL)
    }

    /// 合成 JPEG：纯色 800×600（scale=1，避免 Retina 3× 放大）+ EXIF（含 GPS DMS）
    private static func writeSampleJPEG(to url: URL, width: Int, height: Int, withGPS: Bool) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // 关键：默认跟随屏幕 scale（模拟器 3×），像素会变 2400×1800
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = image.cgImage else { throw ExportError.encodeFailed }

        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [String: Any] = [
            kCGImagePropertyPixelWidth as String: width,
            kCGImagePropertyPixelHeight as String: height,
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2026:10:03 14:25:30",
            ],
        ]
        if withGPS {
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: [37, 20, 24.0],
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: [121, 28, 48.0],
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ]
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// 读回 GPS 纬度（DMS 数组 → 十进制；十进制直读；无 GPS 返回 nil）
    private func gpsLatitude(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude as String] else { return nil }
        if let value = latitude as? Double { return value }
        if let dms = latitude as? [Any], dms.count >= 2,
           let deg = dms[0] as? Double ?? (dms[0] as? NSNumber)?.doubleValue,
           let min = dms[1] as? Double ?? (dms[1] as? NSNumber)?.doubleValue {
            let sec = dms.count >= 3 ? ((dms[2] as? Double) ?? (dms[2] as? NSNumber)?.doubleValue ?? 0) : 0
            return deg + min / 60 + sec / 3600
        }
        return nil
    }

    private func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        let w = properties[kCGImagePropertyPixelWidth as String] as? Int
        let h = properties[kCGImagePropertyPixelHeight as String] as? Int
        return (w ?? 0, h ?? 0)
    }

    // MARK: - 用例

    func testExportLongEdge2048PreservesGPS() throws {
        let url = try ExportRenderer.export(from: sourceURL,
                                            options: ExportOptions(format: .jpeg,
                                                                   longEdge: .edge2048,
                                                                   quality: 0.8,
                                                                   stripLocation: false))
        let size = try XCTUnwrap(pixelSize(of: url))
        XCTAssertEqual(size.width, 2048)          // 长边 2048（横图）
        XCTAssertEqual(size.height, 1536)         // 4:3 保持
        XCTAssertEqual(gpsLatitude(of: url) ?? 0, 37.34, accuracy: 0.01)   // GPS 保留
        try? FileManager.default.removeItem(at: url)
    }

    func testStripLocationRemovesGPS() throws {
        let url = try ExportRenderer.export(from: sourceURL,
                                            options: ExportOptions(format: .jpeg,
                                                                   longEdge: .edge2048,
                                                                   quality: 0.8,
                                                                   stripLocation: true))
        XCTAssertNil(gpsLatitude(of: url), "去除位置信息后 EXIF 不应有 GPS")
        try? FileManager.default.removeItem(at: url)
    }

    func testOriginalLongEdgeKeepsSize() throws {
        let url = try ExportRenderer.export(from: sourceURL,
                                            options: ExportOptions(format: .jpeg,
                                                                   longEdge: .original,
                                                                   quality: 0.8))
        let size = try XCTUnwrap(pixelSize(of: url))
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
        try? FileManager.default.removeItem(at: url)
    }

    func testEditorTransformApplied() throws {
        // 裁剪一半 + 旋转 90°：输出 300×400（原 800×600 → 显示 600×800 → 裁 0.5 → 300×400）
        let transform = PhotoDeskCore.EditorTransform(cropX: 0, cropY: 0,
                                                      cropWidth: 0.5, cropHeight: 0.5,
                                                      quarterTurns: 1)
        let url = try ExportRenderer.export(from: sourceURL,
                                            options: ExportOptions(format: .jpeg,
                                                                   longEdge: .original,
                                                                   quality: 0.8),
                                            transform: transform)
        let size = try XCTUnwrap(pixelSize(of: url))
        XCTAssertEqual(size.width, 300)
        XCTAssertEqual(size.height, 400)
        try? FileManager.default.removeItem(at: url)
    }

    func testExportFromMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).jpg")
        XCTAssertThrowsError(try ExportRenderer.export(from: missing,
                                                       options: ExportOptions()))
    }
}
