// MARK: - 职责说明：资产元数据服务（M17 T08 X06，docs/31 §3）——
// 字节数/格式（资源通道）与 EXIF（禁网络取件 + ImageIO 解析）全部下沉，Feature 层零
// PhotoKit 类型；解析全部在后台执行（Task.detached），主线程只赋值。
// fileSize KVC 失败回退 0（M1 KVC 崩溃教训保留）。

import Foundation
import Photos
import ImageIO
import UniformTypeIdentifiers

/// 基础信息（字节数 + 文件名 + 本地化格式描述）
struct AssetBasics: Equatable {
    let byteSize: Int64
    let filename: String
    let formatText: String
}

protocol MetadataServiceProtocol: AnyObject {
    /// 字节数 + 文件名 + 格式（后台解析；无资源返回 nil）
    func basics(for assetID: String) async -> AssetBasics?
    /// EXIF 字段（禁网络取件 → ImageIO 属性 → MetadataParser；后台解析）
    func exifFields(for assetID: String) async -> MetadataFields?
}

final class PhotoMetadataService: MetadataServiceProtocol {

    func basics(for assetID: String) async -> AssetBasics? {
        await Task.detached(priority: .userInitiated) { () -> AssetBasics? in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = assets.firstObject else { return nil }
            let resources = PHAssetResource.assetResources(for: asset)
            let resource = resources.first { $0.type == .photo }
                ?? resources.first { $0.type == .fullSizePhoto }
                ?? resources.first { $0.type == .video }
                ?? resources.first
            guard let resource else { return nil }
            let byteSize = (try? resource.value(forKey: "fileSize") as? Int64) ?? 0
            let filename = resource.originalFilename
            let ext = (filename as NSString).pathExtension
            var formatText = ext.uppercased()
            if let type = UTType(resource.uniformTypeIdentifier) {
                let localized = type.localizedDescription ?? ""
                if !localized.isEmpty { formatText = localized }
            }
            return AssetBasics(byteSize: byteSize, filename: filename, formatText: formatText)
        }.value
    }

    func exifFields(for assetID: String) async -> MetadataFields? {
        await Task.detached(priority: .userInitiated) { () -> MetadataFields? in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = assets.firstObject else { return nil }
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = false
            let input: PHContentEditingInput? = await withCheckedContinuation { continuation in
                asset.requestContentEditingInput(with: options) { input, _ in
                    continuation.resume(returning: input)
                }
            }
            guard let url = input?.fullSizeImageURL,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
                return nil
            }
            return MetadataParser.parse(properties: properties)
        }.value
    }
}