// MARK: - 职责说明：ImagePipeline v2 单元测试（docs/13 Phase 2 / S02 验收）——
// ResumeOnce 单次恢复（双回调/百路并发）；FakeImageRequester 注入验证：
// 大图双回调只返回一次、取消后迟到回调不崩、预取差量 stop/start、窗口 ≤7、尺寸变化全停、目标尺寸 ≤2048。

import XCTest
import Photos
@testable import PhotoDesk

// MARK: - Fake 请求层（记录调用，onRequest 脚本化回调）

final class FakeImageRequester: ImageRequesting {
    struct CacheCall: Equatable {
        let ids: [String]
        let size: CGSize
    }

    private(set) var startCalls: [CacheCall] = []
    private(set) var stopCalls: [CacheCall] = []
    private(set) var cancelledIDs: [PHImageRequestID] = []
    private(set) var requestCount = 0
    private var nextID: PHImageRequestID = 100
    private let lock = NSLock()
    /// 请求脚本：requestImage 时同步执行（模拟 PhotoKit 回调时机，可触发两次）
    var onRequest: ((_ assetID: String,
                     _ targetSize: CGSize,
                     _ handler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> Void)?

    func requestImage(id: String,
                      targetSize: CGSize,
                      contentMode: PHImageContentMode,
                      options: PHImageRequestOptions,
                      resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID {
        lock.lock()
        nextID += 1
        let requestID = nextID
        requestCount += 1
        lock.unlock()
        onRequest?(id, targetSize, resultHandler)
        return requestID
    }

    func cancelImageRequest(_ id: PHImageRequestID) {
        lock.lock()
        cancelledIDs.append(id)
        lock.unlock()
    }

    func startCachingImages(ids: [String], targetSize: CGSize,
                            contentMode: PHImageContentMode, options: PHImageRequestOptions?) {
        lock.lock()
        startCalls.append(CacheCall(ids: ids, size: targetSize))
        lock.unlock()
    }

    func stopCachingImages(ids: [String], targetSize: CGSize,
                           contentMode: PHImageContentMode, options: PHImageRequestOptions?) {
        lock.lock()
        stopCalls.append(CacheCall(ids: ids, size: targetSize))
        lock.unlock()
    }

    var cancelledIDCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelledIDs.count
    }
}

@MainActor
final class ImagePipelineResumeTests: XCTestCase {
    private func makeImage(_ width: CGFloat = 100, _ height: CGFloat = 80) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makePipeline(_ fake: FakeImageRequester) -> ImagePipeline {
        ImagePipeline(requester: fake,
                      disk: DiskCache(),
                      allowsNetworkAccess: { false })
    }

    // MARK: - ResumeOnce（docs/13 §3.2）

    func testResumeOnceSecondResumeIgnored() async {
        let resumeOnce = ResumeOnce<Int>()
        let task = Task {
            await withCheckedContinuation { continuation in
                resumeOnce.resume(1, continuation)
                resumeOnce.resume(2, continuation)   // 第二次必须被忽略（否则 continuation misuse 崩溃）
            }
        }
        let value = await task.value
        XCTAssertEqual(value, 1, "只有第一次 resume 生效")
        XCTAssertTrue(resumeOnce.hasResumed)
    }

    func testResumeOnceConcurrentHundredOnlyFirstWins() async {
        let resumeOnce = ResumeOnce<Int>()
        let task = Task {
            await withCheckedContinuation { continuation in
                DispatchQueue.concurrentPerform(iterations: 100) { index in
                    resumeOnce.resume(index, continuation)
                }
            }
        }
        let value = await task.value
        XCTAssertTrue((0..<100).contains(value), "并发 100 次 resume 应恰有一次生效，实际值 \(value)")
        XCTAssertTrue(resumeOnce.hasResumed)
    }

    func testResumeOnceInitiallyNotResumed() {
        let resumeOnce = ResumeOnce<String>()
        XCTAssertFalse(resumeOnce.hasResumed)
    }

    // MARK: - 大图：Fake 双回调只返回一次（S02 现场）

    func testFullImageDoubleCallbackReturnsOnceWithoutCrash() async {
        let fake = FakeImageRequester()
        let testImage = makeImage()
        fake.onRequest = { _, _, handler in
            handler(testImage, [PHImageResultIsDegradedKey: false])
            handler(testImage, [PHImageResultIsDegradedKey: false])   // 双回调（S02 崩溃现场）
            handler(nil, nil)                                          // 迟到的第三次也必须被吞掉
        }
        let pipeline = makePipeline(fake)
        let image = await pipeline.fullImage(for: "asset-a", progress: { _ in }, allowNetwork: false)
        XCTAssertTrue(image === testImage, "双回调应只返回第一次的图")
    }

    // MARK: - 大图：取消后迟到回调不崩

    func testCancelThenLateCallbackDoesNotCrash() async {
        let fake = FakeImageRequester()
        var savedHandler: ((UIImage?, [AnyHashable: Any]?) -> Void)?
        fake.onRequest = { _, _, handler in
            savedHandler = handler   // 不回调，请求挂起
        }
        let pipeline = makePipeline(fake)
        let task = Task {
            await pipeline.fullImage(for: "asset-b", progress: { _ in }, allowNetwork: false)
        }
        // 等请求发出
        let deadline = Date().addingTimeInterval(5)
        while fake.requestCount == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(fake.requestCount, 1, "请求应已发出")
        task.cancel()
        // 迟到回调（真实 PhotoKit 取消后仍可能回调一次）
        savedHandler?(nil, [PHImageResultIsInCloudKey: false])
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(fake.cancelledIDCount, 1, "取消应调 cancelImageRequest")
    }

    // MARK: - 预取：差量 stop/start（S02 根因 1：旧实现只 start 从不 stop）

    func testPrefetchStopsIdsLeavingWindow() {
        let fake = FakeImageRequester()
        let pipeline = makePipeline(fake)
        let size = CGSize(width: 300, height: 300)
        let first = (0..<7).map { "id-\($0)" }
        let second = (1..<8).map { "id-\($0)" }

        pipeline.prefetch(ids: first, size: size)
        pipeline.prefetch(ids: second, size: size)

        let stopped = fake.stopCalls.flatMap(\.ids)
        XCTAssertTrue(stopped.contains("id-0"), "滑出窗口的 id 应收到 stop：\(fake.stopCalls)")
        let started = fake.startCalls.flatMap(\.ids)
        XCTAssertTrue(started.contains("id-7"), "新进入窗口的 id 应收到 start")
        XCTAssertFalse(started.contains("id-0"), "已在窗口内的 id 不应重复 start")
    }

    func testPrefetchWindowCappedAt7() {
        let fake = FakeImageRequester()
        let pipeline = makePipeline(fake)
        let ids = (0..<10).map { "cap-\($0)" }
        pipeline.prefetch(ids: ids, size: CGSize(width: 100, height: 100))
        let started = fake.startCalls.flatMap(\.ids)
        XCTAssertLessThanOrEqual(started.count, 7, "预取窗口应 ≤7，实际 \(started.count)")
        XCTAssertFalse(started.contains("cap-7"), "窗口外的 id 不应预取")
    }

    func testPrefetchSizeChangeStopsAllOldAndStartsNew() {
        let fake = FakeImageRequester()
        let pipeline = makePipeline(fake)
        let oldSize = CGSize(width: 100, height: 100)
        let newSize = CGSize(width: 200, height: 200)
        let ids = ["s-1", "s-2", "s-3"]

        pipeline.prefetch(ids: ids, size: oldSize)
        pipeline.prefetch(ids: ids, size: newSize)

        let stoppedAtOldSize = fake.stopCalls.filter { $0.size == oldSize }.flatMap(\.ids)
        XCTAssertEqual(Set(stoppedAtOldSize), Set(ids), "尺寸变化时旧 id 应按旧尺寸全停")
        let startedAtNewSize = fake.startCalls.filter { $0.size == newSize }.flatMap(\.ids)
        XCTAssertEqual(Set(startedAtNewSize), Set(ids), "尺寸变化时新 id 应按新尺寸全开")
    }

    func testCancelAllStopsEverything() {
        let fake = FakeImageRequester()
        let pipeline = makePipeline(fake)
        pipeline.prefetch(ids: ["c-1", "c-2"], size: CGSize(width: 100, height: 100))
        pipeline.cancelAll()
        let stopped = fake.stopCalls.flatMap(\.ids)
        XCTAssertEqual(Set(stopped), ["c-1", "c-2"], "cancelAll 应停掉全部预取")
    }

    // MARK: - 大图目标尺寸（S02：屏幕像素 ×1.25 封顶 2048）

    func testFullImageTargetSizeCappedAt2048() {
        let size = ImagePipeline.fullImageTargetSize(scale: 3, screenBounds: CGSize(width: 2000, height: 4000))
        XCTAssertLessThanOrEqual(size.width, 2048)
        XCTAssertLessThanOrEqual(size.height, 2048)
    }

    func testFullImageTargetSizeScalesScreenPixels() {
        let size = ImagePipeline.fullImageTargetSize(scale: 2, screenBounds: CGSize(width: 100, height: 200))
        XCTAssertEqual(size.width, 250, accuracy: 0.001)   // 100*2*1.25
        XCTAssertEqual(size.height, 500, accuracy: 0.001)  // 200*2*1.25
    }

    // MARK: - 内存警告清理

    func testMemoryWarningClearsCaches() async {
        let fake = FakeImageRequester()
        let testImage = makeImage()
        fake.onRequest = { _, _, handler in
            handler(testImage, [PHImageResultIsDegradedKey: false])
        }
        let pipeline = makePipeline(fake)
        let first = await pipeline.fullImage(for: "asset-mem", progress: { _ in }, allowNetwork: false)
        XCTAssertNotNil(first)
        // 回看应命中 fullImageCache
        let second = await pipeline.fullImage(for: "asset-mem", progress: { _ in }, allowNetwork: false)
        XCTAssertNotNil(second)
        XCTAssertEqual(fake.requestCount, 1, "第二次应命中缓存不再请求")
        // 模拟内存警告 → 缓存清空 → 重新请求
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let third = await pipeline.fullImage(for: "asset-mem", progress: { _ in }, allowNetwork: false)
        XCTAssertNotNil(third)
        XCTAssertEqual(fake.requestCount, 2, "内存警告后缓存应失效重新请求")
    }
}
