// MARK: - 职责说明：图片加载管线（docs/03 §5.2）——唯一合法取图入口（AGENTS.md §3.6 禁止 View 直接 requestImage）。
// 三级：内存 NSCache 60MB → 磁盘 LRU 200MB → PHCachingImageManager（allowsCachingHighQualityImages = false）。
// 同 id+size 在途请求合并（TaskBox）；解码并发上限 4（AGENTS.md §3.5，AsyncSemaphore）；
// iCloud-only 未下载时返回 nil（isNetworkAccessAllowed 由设置控制，docs/03 §5.8）。

import Photos
import UIKit

protocol ImagePipelineProtocol: AnyObject {
    /// 缩略图（网格/胶片条）：三级缓存 + 在途合并
    func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage?
    /// 预取（可视区 ± N）：经 PHCachingImageManager.startCachingImages
    func prefetch(ids: [String], size: CGSize)
    /// 取消某 id 的在途请求与预取（cell 离屏）
    func cancel(id: String)
    /// 大图（浏览页，M2）：opportunistic 先低清后高清，progress 上报下载进度
    func fullImage(for id: String, progress: @escaping (Double) -> Void) async -> UIImage?
}

/// 在途任务包装（Task 是结构体，用类做身份比较以便合并/清理）
private final class TaskBox {
    let task: Task<UIImage?, Never>
    init(_ task: Task<UIImage?, Never>) { self.task = task }
}

/// 异步信号量：限制并发解码数量（docs/03 §6 线程模型）
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        permits = max(1, limit)
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            permits += 1
        }
    }
}

final class ImagePipeline: ImagePipelineProtocol {
    /// 解码/请求并发上限（AGENTS.md §3.5）
    static let maxConcurrentDecodes = 4
    static let thumbnailJPEGQuality: CGFloat = 0.85

    private let memory = MemoryCache()
    private let disk: DiskCache
    private let cachingManager = PHCachingImageManager()
    private let gate = AsyncSemaphore(limit: ImagePipeline.maxConcurrentDecodes)
    private var inflight: [String: TaskBox] = [:]
    /// 最近一次预取的像素尺寸（网格缩略图统一尺寸；cancel 用它匹配 stopCachingImages）
    private var prefetchPixelSize: CGSize?
    private let allowsNetworkAccess: () -> Bool

    /// - Parameter allowsNetworkAccess: iCloud 原件是否允许联网下载（设置 icloud.autoDownloadOriginal，docs/03 §4.3）
    init(disk: DiskCache = DiskCache(), allowsNetworkAccess: @escaping () -> Bool = { false }) {
        self.disk = disk
        self.allowsNetworkAccess = allowsNetworkAccess
        cachingManager.allowsCachingHighQualityImages = false
    }

    // MARK: - ImagePipelineProtocol

    func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage? {
        let request = ThumbnailRequest(id: id, size: size, scale: scale)
        let key = request.cacheKey

        // 1. 内存
        if let hit = memory.image(forKey: key) { return hit }

        // 2. 磁盘
        if let data = disk.data(forKey: key),
           let image = await Self.decode(data) {
            memory.store(image, forKey: key)
            return image
        }

        // 3. 在途合并
        if let box = inflight[key] {
            return await box.task.value
        }

        let box = TaskBox(Task { [weak self] in
            guard let self else { return nil }
            await self.gate.acquire()
            defer { Task { await self.gate.release() } }
            if Task.isCancelled { return nil }
            return await self.requestThumbnail(request)
        })
        inflight[key] = box
        let result = await box.task.value
        if inflight[key] === box {
            inflight.removeValue(forKey: key)
        }
        return result
    }

    /// 预取（可视区 ± N）：经 PHCachingImageManager.startCachingImages。
    /// - Parameter size: **像素尺寸**（与 thumbnail 的缓存键格式一致：同 id 同尺寸共用三级缓存）
    func prefetch(ids: [String], size: CGSize) {
        guard !ids.isEmpty else { return }
        let pixelSize = size
        let options = Self.thumbnailOptions(allowsNetwork: allowsNetworkAccess())
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let targets = assets.objects(at: IndexSet(integersIn: 0..<assets.count))
        guard !targets.isEmpty else { return }
        prefetchPixelSize = pixelSize
        cachingManager.startCachingImages(for: targets,
                                          targetSize: pixelSize,
                                          contentMode: .aspectFill,
                                          options: options)
    }

    func cancel(id: String) {
        let prefix = id + "|"
        for (key, box) in inflight where key.hasPrefix(prefix) {
            box.task.cancel()
            inflight.removeValue(forKey: key)
        }
        // 停掉该资源对应尺寸的 PhotoKit 预取（网格缩略图尺寸统一，记录于 prefetchPixelSize）
        guard let pixelSize = prefetchPixelSize else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        if let asset = assets.firstObject {
            cachingManager.stopCachingImages(for: [asset],
                                             targetSize: pixelSize,
                                             contentMode: .aspectFill,
                                             options: nil)
        }
    }

    func fullImage(for id: String, progress: @escaping (Double) -> Void) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic           // 先低清后高清（docs/02 §3.2）
        options.isNetworkAccessAllowed = allowsNetworkAccess()
        options.resizeMode = .none
        options.progressHandler = { fraction, _, _, _ in
            progress(fraction)
        }
        return await withCheckedContinuation { continuation in
            let requestID = cachingManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }        // 只在最终结果恢复 continuation
                // iCloud-only 且未允许联网：image 为 nil + PHImageResultIsInCloudKey（M2 上「下载」按钮与环形进度）
                continuation.resume(returning: image)
            }
            _ = requestID   // M2：浏览页持有 requestID 以便切页取消
        }
    }

    // MARK: - PhotoKit 请求

    private func requestThumbnail(_ request: ThumbnailRequest) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [request.id], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = Self.thumbnailOptions(allowsNetwork: allowsNetworkAccess())

        // requestID 在回调闭包内才产生：用 box 递给 onCancel 取消 PhotoKit 解码
        final class RequestIDBox: @unchecked Sendable {
            var id: PHImageRequestID = PHInvalidImageRequestID
        }
        let box = RequestIDBox()
        let cachingManager = self.cachingManager

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.id = cachingManager.requestImage(
                    for: asset,
                    targetSize: request.pixelSize,
                    contentMode: .aspectFill,
                    options: options
                ) { [weak self] image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !isDegraded else { return }
                    guard let image else {
                        continuation.resume(returning: nil)
                        return
                    }
                    self?.cacheAside(image, request: request)
                    continuation.resume(returning: image)
                }
                if box.id == PHInvalidImageRequestID {
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            let id = box.id
            if id != PHInvalidImageRequestID {
                cachingManager.cancelImageRequest(id)
            }
        }
    }

    /// 回填内存 + 磁盘（磁盘写走 utility）
    private func cacheAside(_ image: UIImage, request: ThumbnailRequest) {
        memory.store(image, forKey: request.cacheKey)
        let key = request.cacheKey
        Task.detached(priority: .utility) { [disk] in
            if let data = image.jpegData(compressionQuality: ImagePipeline.thumbnailJPEGQuality) {
                disk.store(data, forKey: key)
            }
        }
    }

    private static func thumbnailOptions(allowsNetwork: Bool) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // 单次回调，避免网格双回调闪烁
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetwork
        options.isSynchronous = false
        return options
    }

    private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
    }
}
