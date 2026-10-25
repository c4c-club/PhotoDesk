// MARK: - 职责说明：EXIF/元数据解析（docs/05 M5 任务 5.6）——
// CGImageSourceCopyPropertiesAtIndex 的属性字典 → 强类型字段。纯解析（ImageIO 字典输入），
// 可用合成字典单测（MetadataParserTests）；GPS 度分秒元组 → 十进制换算在此完成。
// 取图（requestContentEditingInput → CGImageSource）在 MetadataView 侧，本类不做 I/O。

import Foundation
import ImageIO

struct MetadataFields: Equatable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var deviceModel: String?
    var lensModel: String?
    /// 光圈值（f/2.8 形式展示，原始存 FNumber）
    var fNumber: Double?
    /// 快门（"1/125 s" 形式展示，原始存 ExposureTime 秒）
    var exposureTime: Double?
    var iso: Int?
    /// 焦距 mm
    var focalLength: Double?
    /// 是否闪光
    var didFireFlash: Bool?
    var dateTimeOriginal: Date?
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var fileExtension: String?
}

enum MetadataParser {
    /// 属性字典（CGImageSourceCopyPropertiesAtIndex 输出；合成测试字典同构）
    static func parse(properties: [String: Any]) -> MetadataFields {
        var fields = MetadataFields()
        fields.pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int
        fields.pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int

        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            fields.deviceModel = tiff[kCGImagePropertyTIFFModel as String] as? String
            if fields.deviceModel == nil {
                fields.deviceModel = tiff[kCGImagePropertyTIFFMake as String] as? String
            }
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            fields.lensModel = exif[kCGImagePropertyExifLensModel as String] as? String
            fields.fNumber = doubleValue(exif[kCGImagePropertyExifFNumber as String])
            fields.exposureTime = doubleValue(exif[kCGImagePropertyExifExposureTime as String])
            fields.iso = intValue(exif[kCGImagePropertyExifISOSpeedRatings as String])
            fields.focalLength = doubleValue(exif[kCGImagePropertyExifFocalLength as String])
            fields.didFireFlash = flashDidFire(exif[kCGImagePropertyExifFlash as String])
            fields.dateTimeOriginal = dateStringValue(exif[kCGImagePropertyExifDateTimeOriginal as String])
        }
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            fields.gpsLatitude = dmsToDecimal(gps[kCGImagePropertyGPSLatitude as String],
                                              ref: gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
                                              positiveRef: "N")
            fields.gpsLongitude = dmsToDecimal(gps[kCGImagePropertyGPSLongitude as String],
                                               ref: gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
                                               positiveRef: "E")
        }
        return fields
    }

    // MARK: - 展示格式化

    static func apertureText(_ fNumber: Double?) -> String? {
        guard let fNumber else { return nil }
        return String(format: "f/%.1f", fNumber)
    }

    static func shutterText(_ exposure: Double?) -> String? {
        guard let exposure, exposure > 0 else { return nil }
        if exposure >= 1 {
            return String(format: "%.1f s", exposure)
        }
        return "1/\(Int((1 / exposure).rounded())) s"
    }

    // MARK: - 私有（类型清洗 + GPS DMS 换算）

    private static func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? NSNumber { return value.intValue }
        // ISOSpeedRatings 可能是数组（EXIF 规范允许）
        if let array = any as? [Any], let first = array.first {
            return intValue(first)
        }
        return nil
    }

    /// Flash 位域：bit 0 = fired（EXIF 规格）
    private static func flashDidFire(_ any: Any?) -> Bool? {
        guard let value = intValue(any) else { return nil }
        return (value & 0x1) == 0x1
    }

    /// EXIF 时间 "yyyy:MM:dd HH:mm:ss" → Date
    private static func dateStringValue(_ any: Any?) -> Date? {
        guard let string = any as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }

    /// GPS 度分秒（(度, 分, 秒) 元组或已十进制）→ 带南北/东西符号的十进制
    private static func dmsToDecimal(_ value: Any?, ref: String?, positiveRef: String) -> Double? {
        // 元组在属性字典里表现为 (deg, min, sec) 的 NSArray
        if let dms = value as? [Any], dms.count >= 2,
           let deg = doubleValue(dms[0]), let min = doubleValue(dms[1]) {
            let sec = dms.count >= 3 ? (doubleValue(dms[2]) ?? 0) : 0
            let decimal = deg + min / 60 + sec / 3600
            return (ref == negativeRef(positiveRef)) ? -decimal : decimal
        }
        // 部分来源直接给十进制
        if let decimal = doubleValue(value) {
            return (ref == negativeRef(positiveRef)) ? -decimal : decimal
        }
        return nil
    }

    private static func negativeRef(_ positiveRef: String) -> String {
        positiveRef == "N" ? "S" : "W"
    }
}
