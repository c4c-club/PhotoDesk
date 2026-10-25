// MARK: - 职责说明：导出选项与尺寸计算（docs/05 M6 任务 6.8）——
// 格式（原图/JPEG/PNG/HEIC）/ 长边（1080/2048/4096/原始）/ 质量（0...1）/ 去位置开关。
// 纯数据与纯计算（Foundation-only，红线 2）；文件编码在 App 侧 ExportRenderer（ImageIO）。
// 约定：长边仅缩小不放大；格式 original 时文件类型沿用源 UTI（回退 JPEG）。

import Foundation

public struct ExportOptions: Equatable {
    public enum Format: String, CaseIterable {
        case original
        case jpeg
        case png
        case heic

        public var displayName: String {
            switch self {
            case .original: return "原图"
            case .jpeg:     return "JPEG"
            case .png:      return "PNG"
            case .heic:     return "HEIC"
            }
        }
    }

    public enum LongEdge: Equatable, CaseIterable {
        case edge1080
        case edge2048
        case edge4096
        case original

        public var pixels: Int? {
            switch self {
            case .edge1080: return 1080
            case .edge2048: return 2048
            case .edge4096: return 4096
            case .original: return nil
            }
        }

        public var displayName: String {
            guard let pixels else { return "原始尺寸" }
            return "\(pixels) px"
        }
    }

    public var format: Format
    public var longEdge: LongEdge
    /// 压缩质量 0...1（PNG 无损，忽略）
    public var quality: Double
    /// 去除位置信息（导出前抹掉 GPS）
    public var stripLocation: Bool

    public init(format: Format = .jpeg, longEdge: LongEdge = .original,
                quality: Double = 0.8, stripLocation: Bool = false) {
        self.format = format
        self.longEdge = longEdge
        self.quality = Self.clampQuality(quality)
        self.stripLocation = stripLocation
    }

    public static func clampQuality(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// 目标像素尺寸（保持宽高比；仅缩小不放大；至少 1px）
    /// - Returns: (width, height)
    public static func outputSize(originalWidth: Int, originalHeight: Int,
                                  longEdge: LongEdge) -> (width: Int, height: Int) {
        guard let limit = longEdge.pixels, limit > 0,
              originalWidth > 0, originalHeight > 0 else {
            return (max(1, originalWidth), max(1, originalHeight))
        }
        let longSide = max(originalWidth, originalHeight)
        guard longSide > limit else {
            return (max(1, originalWidth), max(1, originalHeight))   // 只缩小不放大
        }
        let scale = Double(limit) / Double(longSide)
        return (max(1, Int((Double(originalWidth) * scale).rounded())),
                max(1, Int((Double(originalHeight) * scale).rounded())))
    }

    /// 目标文件 UTI（CGImageDestination 用）。original 时按源 UTI，未知回退 JPEG。
    public static func fileTypeFor(originalUTI: String?, format: Format) -> String {
        switch format {
        case .jpeg: return "public.jpeg"
        case .png:  return "public.png"
        case .heic: return "public.heic"
        case .original:
            guard let originalUTI, !originalUTI.isEmpty else { return "public.jpeg" }
            switch originalUTI {
            case "public.png": return "public.png"
            case "public.heic": return "public.heic"
            default: return "public.jpeg"
            }
        }
    }
}
