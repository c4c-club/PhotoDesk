// MARK: - 职责说明：编辑 ViewModel（docs/05 M6 任务 6.1/6.2）——
// 状态：EditorTransform（几何）+ RenderAdjustments（五滑杆）+ 预览渲染（CIImage 链）。
// 保存：另存（默认，ExportRenderer 渲染 → PhotoWriter.saveNewImage）/ 覆盖（PHContentEditingOutput +
// adjustmentData，系统保留可还原）/ 还原（revertToOriginal）。全尺寸渲染经 ExportRenderer（文件进文件出）。

import Foundation
import CoreImage
import PhotoDeskCore
import UIKit

@MainActor
final class EditorViewModel: ObservableObject {
    let item: PhotoItem

    @Published private(set) var transform = PhotoDeskCore.EditorTransform()
    @Published private(set) var adjustments = RenderAdjustments()
    /// 当前渲染预览（含几何+调整，不含裁剪遮罩——遮罩由 VC 叠加）
    @Published private(set) var preview: UIImage?
    @Published private(set) var selectedAspect: PhotoDeskCore.CropAspectRatio = .free
    @Published private(set) var isLoading = true
    /// 原件是否含本 App 的历史编辑（「还原」按钮可用性）
    @Published private(set) var canRevert = false

    var transformWithoutCrop: PhotoDeskCore.EditorTransform {
        var t = transform
        t.cropX = 0; t.cropY = 0; t.cropWidth = 1; t.cropHeight = 1
        return t
    }

    private let writer: PhotoWriterProtocol
    private let settings: SettingsStore
    private var fullSizeURL: URL?
    private var previewBase: UIImage?
    private var creationDate: Date?
    private let ciContext = CIContext(options: [:])

    /// 预览渲染基准边（像素）
    private let previewLongEdge: CGFloat = 1400

    init(item: PhotoItem, writer: PhotoWriterProtocol, settings: SettingsStore) {
        self.item = item
        self.writer = writer
        self.settings = settings
    }

    // MARK: - 加载

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
        guard let asset = assets.firstObject else { return }

        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = settings.autoDownloadOriginal
        let input: PHContentEditingInput? = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input)
            }
        }
        guard let input else { return }
        fullSizeURL = input.fullSizeImageURL
        creationDate = asset.creationDate
        canRevert = input.adjustmentData != nil

        // 预览底图（长边 1400）
        if let url = input.fullSizeImageURL,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways as String: true,
               kCGImageSourceThumbnailMaxPixelSize as String: Int(previewLongEdge),
           ] as CFDictionary) {
            previewBase = UIImage(cgImage: cgImage)
            renderPreview()
        }
    }

    // MARK: - 几何与调整

    func rotate() {
        transform.rotate90Clockwise()
        renderPreview()
    }

    func flipHorizontally() {
        transform.flipHorizontally()
        renderPreview()
    }

    func applyAspect(_ preset: PhotoDeskCore.CropAspectRatio, displayAspect: Double) {
        selectedAspect = preset
        let ratio = preset == .original ? displayAspect : preset.ratio
        transform = PhotoDeskCore.EditorTransform.centeredCropRect(for: ratio, displayAspect: displayAspect)
        // 保留旋转/翻转状态
        transform.quarterTurns = self.transform.quarterTurns
        transform.isHorizontallyFlipped = self.transform.isHorizontallyFlipped
        renderPreview()
    }

    /// 滑杆更新（VC 归一值 → RenderAdjustments）
    func updateAdjustments(brightness: Double, contrast: Double, saturation: Double,
                           temperature: Double, sharpness: Double) {
        adjustments = RenderAdjustments.fromSliders(brightness: brightness,
                                                    contrast: contrast,
                                                    saturation: saturation,
                                                    temperature: temperature,
                                                    sharpness: sharpness)
        renderPreview()
    }

    func resetAll() {
        transform = .init(quarterTurns: transform.quarterTurns)
        adjustments = .neutral
        selectedAspect = .free
        renderPreview()
    }

    /// 裁剪遮罩回调：设置归一化裁剪矩形（保留旋转/翻转；手动裁剪后脱离比例预设）
    func setCrop(cropX: Double, cropY: Double, cropWidth: Double, cropHeight: Double) {
        transform.cropX = cropX
        transform.cropY = cropY
        transform.cropWidth = cropWidth
        transform.cropHeight = cropHeight
        selectedAspect = .free
    }

    /// 预览渲染（CIImage：旋转→翻转；裁剪由 VC 遮罩叠加，不在预览像素里裁）
    func renderPreview() {
        guard let base = previewBase, let cgImage = base.cgImage else { return }
        var ciImage = CIImage(cgImage: cgImage)
        for _ in 0..<transform.quarterTurns {
            ciImage = ciImage.oriented(.right)
        }
        if transform.isHorizontallyFlipped {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -ciImage.extent.width, y: 0))
        }
        ciImage = applyAdjustments(to: ciImage, adjustments: adjustments)
        if let rendered = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            preview = UIImage(cgImage: rendered)
        }
    }

    private func applyAdjustments(to ciImage: CIImage, adjustments: RenderAdjustments) -> CIImage {
        var image = ciImage
        if adjustments.brightness != 0 || adjustments.contrast != 1 || adjustments.saturation != 1 {
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(adjustments.brightness, forKey: kCIInputBrightnessKey)
            filter?.setValue(adjustments.contrast, forKey: kCIInputContrastKey)
            filter?.setValue(adjustments.saturation, forKey: kCIInputSaturationKey)
            if let output = filter?.outputImage { image = output }
        }
        if adjustments.temperature != 6500 {
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: adjustments.temperature, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
            if let output = filter?.outputImage { image = output }
        }
        if adjustments.sharpness > 0 {
            let filter = CIFilter(name: "CISharpenLuminance")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(adjustments.sharpness, forKey: "inputSharpness")
            if let output = filter?.outputImage { image = output }
        }
        return image
    }

    // MARK: - 保存（另存 / 覆盖 / 还原）

    /// 另存为新照片（默认，不破坏原图）
    func saveCopy() async throws {
        guard let fullSizeURL else { throw ExportError.cannotLoadImage }
        let options = PhotoDeskCore.ExportOptions(format: .jpeg, longEdge: .original, quality: 0.9)
        let rendered = try ExportRenderer.export(from: fullSizeURL,
                                                 options: options,
                                                 transform: transform,
                                                 adjustments: renderAdjustments())
        _ = try await writer.saveNewImage(fromFile: rendered, creationDate: creationDate)
    }

    /// 覆盖原件（PHContentEditingOutput；系统相册保留「还原」能力）
    func saveOverwrite() async throws {
        guard let fullSizeURL else { throw ExportError.cannotLoadImage }
        let transform = self.transform
        let adjustments = self.adjustments
        let data = try JSONEncoder().encode(EditorAdjustmentData(transform: transform.payload,
                                                                 adjustments: adjustments))
        try await writer.overwriteWithAdjustment(assetID: item.id, adjustmentData: data) { outputURL in
            let tmp = try ExportRenderer.export(from: fullSizeURL,
                                                options: PhotoDeskCore.ExportOptions(format: .jpeg,
                                                                                     longEdge: .original,
                                                                                     quality: 0.9),
                                                transform: transform,
                                                adjustments: adjustments)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: tmp, to: outputURL)
        }
    }

    /// 还原到原始状态
    func revert() async throws {
        try await writer.revertToOriginal(assetID: item.id)
        canRevert = false
        await load()
    }
}

/// PHAdjustmentData 载荷（重启后系统把 data 交回 App 才能复现编辑；M6 先保证可序列化）
struct EditorAdjustmentData: Codable {
    var transform: TransformPayload
    var adjustments: Adjustments

    struct TransformPayload: Codable {
        var cropX: Double, cropY: Double, cropWidth: Double, cropHeight: Double
        var quarterTurns: Int
        var isHorizontallyFlipped: Bool
    }
}

extension PhotoDeskCore.EditorTransform {
    init(payload: EditorAdjustmentData.TransformPayload) {
        self.init(cropX: payload.cropX, cropY: payload.cropY,
                  cropWidth: payload.cropWidth, cropHeight: payload.cropHeight,
                  quarterTurns: payload.quarterTurns,
                  isHorizontallyFlipped: payload.isHorizontallyFlipped)
    }

    var payload: EditorAdjustmentData.TransformPayload {
        EditorAdjustmentData.TransformPayload(cropX: cropX, cropY: cropY,
                                              cropWidth: cropWidth, cropHeight: cropHeight,
                                              quarterTurns: quarterTurns,
                                              isHorizontallyFlipped: isHorizontallyFlipped)
    }
}

private extension EditorViewModel {
    func renderAdjustments() -> RenderAdjustments { adjustments }
}
