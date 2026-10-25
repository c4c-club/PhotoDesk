// MARK: - 职责说明：导出/编辑渲染器（docs/05 M6 任务 6.1/6.8）——
// 文件进文件出（不依赖相册授权，可单测）：源文件 → CIImage 链（旋转/翻转 → 裁剪 → 五滑杆调整）
// → 缩放（长边，仅缩小）→ CGImageDestination 编码（保留或剥离 GPS；original 沿源 UTI）→ 临时文件。
// EditorTransform 几何来自 PhotoDeskCore（红线 2）；本类只做 Core Image / ImageIO 适配。

import CoreImage
import Foundation
import ImageIO
import PhotoDeskCore
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case cannotLoadImage
    case encodeFailed
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .cannotLoadImage: return "无法读取原图（iCloud 原件可能未下载）"
        case .encodeFailed:    return "导出编码失败"
        case .outputUnavailable: return "导出结果不可用"
        }
    }
}

/// 编辑调整的滤镜值（Core Image 映射在此，值结构可序列化）
struct RenderAdjustments: Equatable {
    var brightness: Double = 0     // -0.3...0.3
    var contrast: Double = 1       // 0.5...1.5
    var saturation: Double = 1     // 0...2
    var temperature: Double = 6500 // 4000...8000
    var sharpness: Double = 0      // 0...2

    var isNeutral: Bool {
        brightness == 0 && contrast == 1 && saturation == 1 && temperature == 6500 && sharpness == 0
    }

    /// 滑杆 UI（-1...1 归一）→ 参数
    static func fromSliders(brightness: Double, contrast: Double, saturation: Double,
                            temperature: Double, sharpness: Double) -> RenderAdjustments {
        RenderAdjustments(brightness: brightness * 0.3,
                          contrast: 1 + contrast * 0.5,
                          saturation: max(0, 1 + saturation),
                          temperature: 6500 + temperature * 1500,
                          sharpness: max(0, sharpness))
    }
}

enum ExportRenderer {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 渲染并导出
    /// - Parameters:
    ///   - sourceURL: 原件文件 URL（iCloud 未下载时 CGImageSource 失败 → .cannotLoadImage，调用方先下载）
    ///   - options: 导出选项（格式/长边/质量/去 GPS）
    ///   - transform: 编辑几何（旋转/翻转/裁剪；nil = 不做几何）
    ///   - adjustments: 五滑杆调整（nil = 不做调整）
    /// - Returns: 导出文件的临时 URL
    static func export(from sourceURL: URL,
                       options: ExportOptions,
                       transform: PhotoDeskCore.EditorTransform? = nil,
                       adjustments: RenderAdjustments? = nil) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let sourceUTI = CGImageSourceGetType(source) as String?,
              var cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExportError.cannotLoadImage
        }
        let sourceProperties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]

        // 1. CIImage 链：旋转 → 翻转 → 裁剪 → 调整
        if let transform, !transform.isNeutral {
            var ciImage = CIImage(cgImage: cgImage)
            for _ in 0..<transform.quarterTurns {
                ciImage = ciImage.oriented(.right)
            }
            if transform.isHorizontallyFlipped {
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -ciImage.extent.width, y: 0))
            }
            let crop = transform.cropRectPixels(originalWidth: cgImage.width, originalHeight: cgImage.height)
            let cropRect = CGRect(x: CGFloat(crop.x), y: CGFloat(crop.y),
                                  width: CGFloat(crop.width), height: CGFloat(crop.height))
            ciImage = ciImage.cropped(to: cropRect)
                .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            if let rendered = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                cgImage = rendered
            }
        }

        if let adjustments, !adjustments.isNeutral {
            var ciImage = CIImage(cgImage: cgImage)
            let colorControls = CIFilter(name: "CIColorControls")
            colorControls?.setValue(ciImage, forKey: kCIInputImageKey)
            colorControls?.setValue(adjustments.brightness, forKey: kCIInputBrightnessKey)
            colorControls?.setValue(adjustments.contrast, forKey: kCIInputContrastKey)
            colorControls?.setValue(adjustments.saturation, forKey: kCIInputSaturationKey)
            if let controlled = colorControls?.outputImage {
                let temperature = CIFilter(name: "CITemperatureAndTint")
                temperature?.setValue(controlled, forKey: kCIInputImageKey)
                temperature?.setValue(CIVector(x: adjustments.temperature, y: 0), forKey: "inputNeutral")
                temperature?.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
                if let warmed = temperature?.outputImage {
                    ciImage = warmed
                }
            }
            if adjustments.sharpness > 0 {
                let sharpen = CIFilter(name: "CISharpenLuminance")
                sharpen?.setValue(ciImage, forKey: kCIInputImageKey)
                sharpen?.setValue(adjustments.sharpness, forKey: "inputSharpness")
                if let sharpened = sharpen?.outputImage {
                    ciImage = sharpened
                }
            }
            if let rendered = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                cgImage = rendered
            }
        }

        // 2. 长边缩放（仅缩小）
        let (targetW, targetH) = PhotoDeskCore.ExportOptions.outputSize(
            originalWidth: cgImage.width, originalHeight: cgImage.height, longEdge: options.longEdge)
        if targetW != cgImage.width || targetH != cgImage.height {
            let ciImage = CIImage(cgImage: cgImage)
                .transformed(by: CGAffineTransform(scaleX: CGFloat(targetW) / CGFloat(cgImage.width),
                                                   y: CGFloat(targetH) / CGFloat(cgImage.height)))
            if let scaled = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0,
                                                                          width: targetW, height: targetH)) {
                cgImage = scaled
            }
        }

        // 3. 编码（保留 EXIF 但按要求剥离 GPS；original 沿源 UTI 回退 JPEG）
        let fileType = PhotoDeskCore.ExportOptions.fileTypeFor(originalUTI: sourceUTI, format: options.format)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).\(fileExtension(for: fileType))")

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
                                                                fileType as CFString, 1, nil) else {
            throw ExportError.encodeFailed
        }
        var outputProperties = sourceProperties
        outputProperties[kCGImageDestinationLossyCompressionQuality as String] = options.quality
        if options.stripLocation {
            outputProperties[kCGImagePropertyGPSDictionary as String] = kCFNull
        }
        CGImageDestinationAddImage(destination, cgImage, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodeFailed
        }
        return outputURL
    }

    private static func fileExtension(for fileType: String) -> String {
        switch fileType {
        case "public.png": return "png"
        case "public.heic": return "heic"
        default: return "jpg"
        }
    }
}
