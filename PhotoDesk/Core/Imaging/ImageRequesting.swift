// MARK: - 职责说明：PhotoKit 取图请求抽象（docs/13 §3.2 S02）——
// ImagePipeline 只依赖本协议：生产用 PhotoKitImageRequester（包 PHCachingImageManager），
// 测试注入 FakeImageRequester（记录调用、可手动触发两次回调/取消后回调，验证单次 resume 与取消）。
// 全部按 asset id 交互：id→PHAsset 的解析只发生在生产实现内（测试无需真实照片库）。

import Photos
import UIKit

protocol ImageRequesting: AnyObject {
    /// 单次取图请求；返回 requestID 供取消
    @discardableResult
    func requestImage(id: String,
                      targetSize: CGSize,
                      contentMode: PHImageContentMode,
                      options: PHImageRequestOptions,
                      resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID

    func cancelImageRequest(_ id: PHImageRequestID)

    /// 预取缓存（PHCachingImageManager.startCachingImages）
    func startCachingImages(ids: [String],
                            targetSize: CGSize,
                            contentMode: PHImageContentMode,
                            options: PHImageRequestOptions?)

    /// 停止预取缓存（PHCachingImageManager.stopCachingImages，docs/13 S02 差量 stop）
    func stopCachingImages(ids: [String],
                           targetSize: CGSize,
                           contentMode: PHImageContentMode,
                           options: PHImageRequestOptions?)
}

/// 生产实现：包 PHCachingImageManager（allowsCachingHighQualityImages = false，docs/03 §5.2）
final class PhotoKitImageRequester: ImageRequesting {
    private let manager: PHCachingImageManager

    init(manager: PHCachingImageManager = PHCachingImageManager()) {
        self.manager = manager
        manager.allowsCachingHighQualityImages = false
    }

    func requestImage(id: String,
                      targetSize: CGSize,
                      contentMode: PHImageContentMode,
                      options: PHImageRequestOptions,
                      resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            // 资源已不存在（删除/limited 收窄）：同步回调 nil + isInCloud=false，走正常失败路径
            resultHandler(nil, [PHImageResultIsInCloudKey: false])
            return PHInvalidImageRequestID
        }
        return manager.requestImage(for: asset,
                                    targetSize: targetSize,
                                    contentMode: contentMode,
                                    options: options) { image, info in
            resultHandler(image, info)
        }
    }

    func cancelImageRequest(_ id: PHImageRequestID) {
        guard id != PHInvalidImageRequestID else { return }
        manager.cancelImageRequest(id)
    }

    func startCachingImages(ids: [String],
                            targetSize: CGSize,
                            contentMode: PHImageContentMode,
                            options: PHImageRequestOptions?) {
        guard !ids.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard result.count > 0 else { return }
        let assets = result.objects(at: IndexSet(integersIn: 0..<result.count))
        manager.startCachingImages(for: assets,
                                   targetSize: targetSize,
                                   contentMode: contentMode,
                                   options: options)
    }

    func stopCachingImages(ids: [String],
                           targetSize: CGSize,
                           contentMode: PHImageContentMode,
                           options: PHImageRequestOptions?) {
        guard !ids.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard result.count > 0 else { return }
        let assets = result.objects(at: IndexSet(integersIn: 0..<result.count))
        manager.stopCachingImages(for: assets,
                                  targetSize: targetSize,
                                  contentMode: contentMode,
                                  options: options)
    }
}
