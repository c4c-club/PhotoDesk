// MARK: - 职责说明：图片加载管线 v2（docs/03 §5.2 + docs/13 §3.2）——唯一合法取图入口。
// v2 修复 S02/S08：全部 continuation 经 ResumeOnce 单次恢复；大图 .highQualityFormat 单回调 +
// 目标尺寸 ≤2048 + requestID 可取消；预取经 PrefetchWindowTracker 差量 stop/start（窗口 ≤7）；
// fullImageCache（6 张 / 60MB）滑动回看命中；cancelAll + 内存警告清理。
// 三级：内存 NSCache 60MB → 磁盘 LRU 200MB → PHCachingImageManager；解码并发 4、大图并发 2。

import AVFoundation
import Photos
import UIKit

protocol ImagePipelineProtocol: AnyObject {
    /// 缩略图（网格/胶片条）：三级缓存 + 在途合并
    func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage?
    /// 预取（可视区 ± N）：差量 start/stopCachingImages，窗口 ≤7
    func prefetch(ids: [String], size: CGSize)
    /// 取消某 id 的在途请求与预取（cell 离屏）
    func cancel(id: String)
    /// 取消全部在途请求与预取（查看器关闭 / 内存警告，docs/13 S02）
    func cancelAll()
    /// 大图（浏览页）：.highQualityFormat 单回调 + 目标尺寸 ≤2048，progress 上报下载进度。
    /// allowNetwork：iCloud 手动下载时由「下载」按钮置 true，否则跟随设置（docs/03 §5.8）。
    /// M12 R01/A2：回传 inCloud 状态（image=nil 且在云 → VC 显示占位 + 下载按钮，不再纯黑）。
    func fullImageWithState(for id: String, progress: @escaping (Double) -> Void, allowNetwork: Bool) async -> FullImageResult
    /// 视频播放资产（浏览页视频 cell；用 iOS 8+ 的 requestAVAsset，兼容 iOS 15）
    func videoAsset(for id: String) async -> (asset: AVAsset, audioMix: AVAudioMix?)?
    /// 磁盘缓存占用（设置页显示）
    var diskCacheBytes: Int64 { get }
    /// 清空内存 + 磁盘缓存（设置页「清理缓存」）
    func clearCaches()
}

extension ImagePipelineProtocol {
    /// 旧签名兼容（只关心 image 的调用方；PhotoDeskTests 既有用例沿用）
    func fullImage(for id: String, progress: @escaping (Double) -> Void, allowNetwork: Bool) async -> UIImage? {
        await fullImageWithState(for: id, progress: progress, allowNetwork: allowNetwork).image
    }
}

/// 大图回传（M12 R01/A2，App 层类型——PhotoDeskCore 不参与）
struct FullImageResult {
    let image: UIImage?
    /// image 为 nil 且 true = 原件在 iCloud 且未下载（禁网或未允许联网）
    let isInCloud: Bool
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
    /// 大图并发上限（docs/13 §3.2：48MP 全尺寸解码限 2 路）
    static let maxConcurrentFullImages = 2
    /// 大图目标尺寸硬上限（docs/13 S02：屏幕像素×1.25，封顶 2048）
    static let maxFullImagePixel: CGFloat = 2048
    /// 预取窗口上限（docs/13 S02）
    static let maxPrefetchWindow = 7
    static let thumbnailJPEGQuality: CGFloat = 0.85

    private let requester: ImageRequesting
    private let memory = MemoryCache()
    private let disk: DiskCache
    private let gate = AsyncSemaphore(limit: ImagePipeline.maxConcurrentDecodes)
    private let fullImageGate = AsyncSemaphore(limit: ImagePipeline.maxConcurrentFullImages)
    private var inflight: [String: TaskBox] = [:]
    private let inflightLock = NSLock()
    /// 大图在途请求 id 盒（M12：requestImage 调用前预注册——旧版在返回后注册，缺失资产同步回调时
    /// 出现「unregister 先跑 / 陈旧 id 残留 / cancelAll 取消错对象」竞态）
    private var fullImageRequestBoxes: [String: RequestIDBox] = [:]
    private let requestIDLock = NSLock()

    /// 可变的请求 ID 盒（回调闭包内赋值；取消路径随时可读）
    final class RequestIDBox: @unchecked Sendable {
        var id: PHImageRequestID = PHInvalidImageRequestID
    }
    /// 大图回看缓存（countLimit 6 / costLimit 60MB，docs/13 S02）
    private let fullImageCache = NSCache<NSString, UIImage>()
    /// 预取窗口差量
    private let prefetchTracker = PrefetchWindowTracker(windowLimit: ImagePipeline.maxPrefetchWindow)
    private let allowsNetworkAccess: () -> Bool
    private var memoryWarningObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - requester: PhotoKit 请求层（生产默认 PHCachingImageManager；测试注入 Fake）
    ///   - allowsNetworkAccess: iCloud 原件是否允许联网下载（设置 icloud.autoDownloadOriginal，docs/03 §4.3）
    init(requester: ImageRequesting = PhotoKitImageRequester(),
         disk: DiskCache = DiskCache(),
         allowsNetworkAccess: @escaping () -> Bool = { false }) {
        self.requester = requester
        self.disk = disk
        self.allowsNetworkAccess = allowsNetworkAccess
        fullImageCache.countLimit = 6
        fullImageCache.totalCostLimit = 60 * 1024 * 1024
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        if let box = self.inflightBox(forKey: key) {
            return await box.task.value
        }

        let box = TaskBox(Task { [weak self] in
            guard let self else { return nil }
            await self.gate.acquire()
            defer { Task { await self.gate.release() } }
            if Task.isCancelled { return nil }
            return await self.requestThumbnail(request)
        })
        self.setInflightBox(box, forKey: key)
        let result = await box.task.value
        self.removeInflightBox(forKey: key, expected: box)
        return result
    }

    /// 预取：差量 stop/start（docs/13 S02——旧实现只 start 从不 stop，快滑必涨内存）
    /// - Parameter size: **像素尺寸**（与 thumbnail 的缓存键格式一致：同 id 同尺寸共用三级缓存）
    func prefetch(ids: [String], size: CGSize) {
        let delta = prefetchTracker.update(ids: ids, size: size)
        execute(delta)
    }

    func cancel(id: String) {
        // 1. 在途缩略图任务
        let prefix = id + "|"
        inflightLock.lock()
        let matching = inflight.filter { $0.key.hasPrefix(prefix) }
        matching.forEach { inflight.removeValue(forKey: $0.key) }
        inflightLock.unlock()
        matching.values.forEach { $0.task.cancel() }
        // 2. 在途大图请求
        cancelFullImageRequest(id)
        // 3. 该 id 的 PhotoKit 预取
        executeStopOnly(prefetchTracker.remove(id))
    }

    func cancelAll() {
        inflightLock.lock()
        let boxes = Array(inflight.values)
        inflight.removeAll()
        inflightLock.unlock()
        boxes.forEach { $0.task.cancel() }

        requestIDLock.lock()
        let requestBoxes = fullImageRequestBoxes
        fullImageRequestBoxes.removeAll()
        requestIDLock.unlock()
        requestBoxes.values.forEach { box in
            let id = box.id
            if id != PHInvalidImageRequestID {
                requester.cancelImageRequest(id)
            }
        }

        let delta = prefetchTracker.reset()
        executeStopOnly(delta)
    }

    func fullImageWithState(for id: String, progress: @escaping (Double) -> Void, allowNetwork: Bool) async -> FullImageResult {
        // 回看命中（docs/13 S02：滑动回看不再重新解码）
        if let cached = fullImageCache.object(forKey: id as NSString) {
            progress(1)
            return FullImageResult(image: cached, isInCloud: false)
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // 单次回调（docs/13 S02：.opportunistic 双回调是 resume 隐患）
        options.isNetworkAccessAllowed = allowsNetworkAccess() || allowNetwork
        options.resizeMode = .fast                  // 快速重采样：直接给目标尺寸
        options.isSynchronous = false
        options.progressHandler = { fraction, _, _, _ in
            progress(fraction)
        }

        await fullImageGate.acquire()
        defer { Task { await fullImageGate.release() } }
        if Task.isCancelled { return FullImageResult(image: nil, isInCloud: false) }

        // M12：ContinuationBox——取消路径强制 finish(nil)，PhotoKit 取消后不再回调也不悬挂；
        // 回调与取消竞态时只生效一次
        let box = ContinuationBox<FullImageResult>()
        let requester = self.requester
        let targetSize = Self.fullImageTargetSize()
        // 请求 ID 盒在 requestImage 之前注册（旧版返回后注册：缺失资产同步回调 → 注册竞态）
        let requestBox = RequestIDBox()
        registerFullImageRequestBox(requestBox, for: id)

        let result: FullImageResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.attach(continuation)
                requestBox.id = requester.requestImage(
                    id: id,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !isDegraded else { return }   // .highQualityFormat 不会再有 degraded，防御保留
                    // M12 R01/A2：iCloud-only 且未允许联网 → image=nil + PHImageResultIsInCloudKey
                    //（「下载」按钮信号；旧版丢弃该信息 → 无占位无自救 → 纯黑）
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    if let image {
                        box.finish(FullImageResult(image: image, isInCloud: false))
                    } else {
                        box.finish(FullImageResult(image: nil, isInCloud: isInCloud))
                    }
                }
            }
        } onCancel: {
            // 立即取消 PhotoKit 解码（requestBox 已预注册，无窗口期）；
            // 并强制收口——PhotoKit 取消后可能不再回调，不 resume 会悬挂 continuation
            let requestID = requestBox.id
            if requestID != PHInvalidImageRequestID {
                requester.cancelImageRequest(requestID)
            }
            box.finish(FullImageResult(image: nil, isInCloud: false))
        }
        unregisterFullImageRequestBox(id)
        if let image = result.image {
            let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
            fullImageCache.setObject(image, forKey: id as NSString, cost: max(1, cost))
        }
        return result
    }

    func videoAsset(for id: String) async -> (asset: AVAsset, audioMix: AVAudioMix?)? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              asset.mediaType == .video else { return nil }
        let resumeOnce = ResumeOnce<(asset: AVAsset, audioMix: AVAudioMix?)?>()
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, audioMix, _ in
                guard let avAsset else {
                    resumeOnce.resume(nil, continuation)
                    return
                }
                resumeOnce.resume((avAsset, audioMix), continuation)
            }
        }
    }

    var diskCacheBytes: Int64 {
        disk.totalBytes()
    }

    func clearCaches() {
        memory.clear()
        disk.clear()
        fullImageCache.removeAllObjects()
    }

    // MARK: - 大图目标尺寸（docs/13 S02：屏幕像素 ×1.25，封顶 2048）

    static func fullImageTargetSize(scale: CGFloat = UIScreen.main.scale,
                                    screenBounds: CGSize = UIScreen.main.bounds.size) -> CGSize {
        let width = min(screenBounds.width * scale * 1.25, maxFullImagePixel)
        let height = min(screenBounds.height * scale * 1.25, maxFullImagePixel)
        return CGSize(width: max(1, width), height: max(1, height))
    }

    // MARK: - PhotoKit 请求（缩略图）

    private func requestThumbnail(_ request: ThumbnailRequest) async -> UIImage? {
        let options = Self.thumbnailOptions(allowsNetwork: allowsNetworkAccess())
        let requester = self.requester
        // M12：ContinuationBox——取消路径强制 finish(nil)，PhotoKit 不再回调也不悬挂
        let box = ContinuationBox<UIImage?>()
        let requestBox = RequestIDBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.attach(continuation)
                requestBox.id = requester.requestImage(
                    id: request.id,
                    targetSize: request.pixelSize,
                    contentMode: .aspectFill,
                    options: options
                ) { [weak self] image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !isDegraded else { return }
                    guard let image else {
                        box.finish(nil)
                        return
                    }
                    self?.cacheAside(image, request: request)
                    box.finish(image)
                }
            }
        } onCancel: {
            let id = requestBox.id
            if id != PHInvalidImageRequestID {
                requester.cancelImageRequest(id)
            }
            box.finish(nil)   // 取消强制收口（旧版悬挂根因）
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

    // MARK: - 预取执行

    private func execute(_ delta: PrefetchDelta) {
        executeStopOnly(delta)
        guard !delta.startIDs.isEmpty, let startSize = delta.startSize else { return }
        requester.startCachingImages(ids: delta.startIDs,
                                     targetSize: startSize,
                                     contentMode: .aspectFill,
                                     options: Self.thumbnailOptions(allowsNetwork: allowsNetworkAccess()))
    }

    private func executeStopOnly(_ delta: PrefetchDelta) {
        guard !delta.stopIDs.isEmpty, let stopSize = delta.stopSize else { return }
        requester.stopCachingImages(ids: delta.stopIDs,
                                    targetSize: stopSize,
                                    contentMode: .aspectFill,
                                    options: nil)
    }

    // MARK: - 在途表（锁保护：回调线程 ≠ 调用线程）

    private func inflightBox(forKey key: String) -> TaskBox? {
        inflightLock.lock()
        defer { inflightLock.unlock() }
        return inflight[key]
    }

    private func setInflightBox(_ box: TaskBox, forKey key: String) {
        inflightLock.lock()
        inflight[key] = box
        inflightLock.unlock()
    }

    private func removeInflightBox(forKey key: String, expected: TaskBox) {
        inflightLock.lock()
        if inflight[key] === expected {
            inflight.removeValue(forKey: key)
        }
        inflightLock.unlock()
    }

    private func registerFullImageRequestBox(_ box: RequestIDBox, for assetID: String) {
        requestIDLock.lock()
        fullImageRequestBoxes[assetID] = box
        requestIDLock.unlock()
    }

    private func unregisterFullImageRequestBox(_ assetID: String) {
        requestIDLock.lock()
        fullImageRequestBoxes.removeValue(forKey: assetID)
        requestIDLock.unlock()
    }

    private func cancelFullImageRequest(_ assetID: String) {
        requestIDLock.lock()
        let box = fullImageRequestBoxes.removeValue(forKey: assetID)
        requestIDLock.unlock()
        if let id = box?.id, id != PHInvalidImageRequestID {
            requester.cancelImageRequest(id)
        }
    }

    // MARK: - 内存警告（docs/13 §3.2）

    private func handleMemoryWarning() {
        memory.clear()
        fullImageCache.removeAllObjects()
        let delta = prefetchTracker.reset()
        executeStopOnly(delta)
    }
}
