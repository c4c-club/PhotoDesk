// MARK: - 职责说明：MetadataParser 单元测试（docs/05 M5 验收）——
// 合成 CGImageSource 属性字典（与真实输出同构）：设备/镜头/光圈/快门/ISO/焦距/闪光 + GPS DMS→十进制
// （含南北/东西符号）+ 数组型 ISO + 日期解析 + 展示格式化。

import XCTest
import ImageIO
@testable import PhotoDesk

final class MetadataParserTests: XCTestCase {
    /// 与 iPhone 实拍 EXIF 同构的合成字典
    private func sampleProperties() -> [String: Any] {
        [
            kCGImagePropertyPixelWidth as String: 4032,
            kCGImagePropertyPixelHeight as String: 3024,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "Apple",
                kCGImagePropertyTIFFModel as String: "iPhone 13 Pro",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifLensModel as String: "iPhone 13 Pro back triple camera 6.86mm f/1.78",
                kCGImagePropertyExifFNumber as String: 1.78,
                kCGImagePropertyExifExposureTime as String: 0.008,      // 1/125 s
                kCGImagePropertyExifISOSpeedRatings as String: [64],    // EXIF 规范允许数组
                kCGImagePropertyExifFocalLength as String: 6.86,
                kCGImagePropertyExifFlash as String: 16,                // bit0 未触发（含 compulsory-off 位）
                kCGImagePropertyExifDateTimeOriginal as String: "2026:10:03 14:25:30",
            ],
            kCGImagePropertyGPSDictionary as String: [
                // CGImageSource 实际输出为 NSArray（度/分/秒）；合成测试用数组保持同构
                kCGImagePropertyGPSLatitude as String: [37, 20, 24.0],   // 37°20'24" N = 37.34
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: [121, 28, 48.0], // 121°28'48" E = 121.48
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ],
        ]
    }

    func testParseFullFields() {
        let fields = MetadataParser.parse(properties: sampleProperties())

        XCTAssertEqual(fields.pixelWidth, 4032)
        XCTAssertEqual(fields.pixelHeight, 3024)
        XCTAssertEqual(fields.deviceModel, "iPhone 13 Pro")
        XCTAssertTrue(fields.lensModel?.contains("triple camera") == true)
        XCTAssertEqual(fields.fNumber ?? 0, 1.78, accuracy: 0.001)
        XCTAssertEqual(fields.exposureTime ?? 0, 0.008, accuracy: 0.0001)
        XCTAssertEqual(fields.iso, 64)                    // 数组型 ISO 取首元素
        XCTAssertEqual(fields.focalLength ?? 0, 6.86, accuracy: 0.001)
        XCTAssertEqual(fields.didFireFlash, false)        // 16 = 0b10000，bit0 = 0
        XCTAssertNotNil(fields.dateTimeOriginal)

        // GPS DMS → 十进制（北纬/东经为正）
        XCTAssertEqual(fields.gpsLatitude ?? 0, 37.34, accuracy: 0.001)
        XCTAssertEqual(fields.gpsLongitude ?? 0, 121.48, accuracy: 0.001)
    }

    func testGPSHemisphereSigns() {
        var properties = sampleProperties()
        var gps = properties[kCGImagePropertyGPSDictionary as String] as! [String: Any]
        gps[kCGImagePropertyGPSLatitudeRef as String] = "S"
        gps[kCGImagePropertyGPSLongitudeRef as String] = "W"
        properties[kCGImagePropertyGPSDictionary as String] = gps

        let fields = MetadataParser.parse(properties: properties)
        // 南纬/西经为负
        XCTAssertEqual(fields.gpsLatitude ?? 0, -37.34, accuracy: 0.001)
        XCTAssertEqual(fields.gpsLongitude ?? 0, -121.48, accuracy: 0.001)
    }

    func testFlashFiredBit() {
        var properties = sampleProperties()
        var exif = properties[kCGImagePropertyExifDictionary as String] as! [String: Any]
        exif[kCGImagePropertyExifFlash as String] = 9     // 0b1001：bit0 触发
        properties[kCGImagePropertyExifDictionary as String] = exif

        XCTAssertEqual(MetadataParser.parse(properties: properties).didFireFlash, true)
    }

    func testEmptyPropertiesYieldEmptyFields() {
        let fields = MetadataParser.parse(properties: [:])
        XCTAssertNil(fields.deviceModel)
        XCTAssertNil(fields.gpsLatitude)
        XCTAssertNil(fields.iso)
        XCTAssertEqual(fields, MetadataFields())
    }

    func testDisplayFormatting() {
        XCTAssertEqual(MetadataParser.apertureText(1.78), "f/1.8")
        XCTAssertEqual(MetadataParser.shutterText(0.008), "1/125 s")
        XCTAssertEqual(MetadataParser.shutterText(2.0), "2.0 s")
        XCTAssertEqual(MetadataParser.shutterText(1.0), "1.0 s")
        XCTAssertNil(MetadataParser.apertureText(nil))
        XCTAssertNil(MetadataParser.shutterText(0))
    }

    func testDecimalGPSFallback() {
        // 部分来源直接给十进制（无 DMS 元组）
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: -33.8688,
                kCGImagePropertyGPSLatitudeRef as String: "S",
            ],
        ]
        let fields = MetadataParser.parse(properties: properties)
        XCTAssertEqual(fields.gpsLatitude ?? 0, -33.8688, accuracy: 0.0001)
        XCTAssertNil(fields.gpsLongitude)
    }
}
