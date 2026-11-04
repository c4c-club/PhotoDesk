// MARK: - 职责说明：ImagePipeline inCloud 回传与取消收口单元测试（docs/16 M12 R01/A2 + 附带）——
// 基线红：fullImage 不查 PHImageResultIsInCloudKey（iCloud-only 拿不到占位信号）；
// 取消路径不强制 resume（PhotoKit 取消后不回调 → continuation 悬挂）。

import XCTest
import Photos
import UIKit
@testable import PhotoDesk

@MainActor
final class ImagePipelineInCloudTests: XCTestCase {
    private func makeImage(_ width: CGFloat = 100, _ height: CGFloat = 80) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makePipeline(_ fake: FakeImageRequester) -> ImagePipeline {
        ImagePipeline(requester: fake,
                      disk: DiskCache(),
                      allowsNetworkAccess: { false })
    }

    /// iCloud-only（禁网）：image=nil + PHImageResultIsInCloudKey=true → 必须回传 isInCloud=true
    func testFullImageReportsInCloud() async {
        let fake = FakeImageRequester()
        fake.onRequest = { _, _, handler in
            handler(nil, [PHImageResultIsInCloudKey: true])
        }
        let pipeline = makePipeline(fake)
        let result = await pipeline.fullImageWithState(for: "cloud-asset", progress: { _ in }, allowNetwork: false)
        XCTAssertNil(result.image, "禁网时 iCloud-only 不应有图")
        XCTAssertTrue(result.isInCloud,
                      "A2：必须回传 inCloud 状态（旧版丢弃该信息 → 无占位无下载按钮 → 纯黑）")
    }

    /// 正常本地图：image 非 nil → isInCloud=false
    func testFullImageReportsImageWithCloudFalse() async {
        let fake = FakeImageRequester()
        let image = makeImage()
        fake.onRequest = { _, _, handler in
            handler(image, [PHImageResultIsInCloudKey: false])
        }
        let pipeline = makePipeline(fake)
        let result = await pipeline.fullImageWithState(for: "local-asset", progress: { _ in }, allowNetwork: false)
        XCTAssertNotNil(result.image)
        XCTAssertFalse(result.isInCloud)
    }

    /// 资产缺失（生产 requester 同步回调 nil + isInCloud=false）：不悬挂、不误报云
    func testMissingAssetReturnsNilNotInCloud() async {
        let fake = FakeImageRequester()
        fake.onRequest = { _, _, handler in
            handler(nil, [PHImageResultIsInCloudKey: false])
        }
        let pipeline = makePipeline(fake)
        let result = await pipeline.fullImageWithState(for: "missing-asset", progress: { _ in }, allowNetwork: false)
        XCTAssertNil(result.image)
        XCTAssertFalse(result.isInCloud)
    }

    /// 取消必须强制收口：挂起的请求被取消后 3s 内必须返回（旧版 PhotoKit 取消后不再回调 → continuation 悬挂）
    func testCancelForcesResumeWithin3Seconds() async {
        let fake = FakeImageRequester()
        var savedHandler: ((UIImage?, [AnyHashable: Any]?) -> Void)?
        fake.onRequest = { _, _, handler in
            savedHandler = handler   // 不回调：请求挂起
        }
        let pipeline = makePipeline(fake)
        let task = Task {
            await pipeline.fullImageWithState(for: "cancel-asset", progress: { _ in }, allowNetwork: false)
        }
        let deadline = Date().addingTimeInterval(5)
        while fake.requestCount == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(fake.requestCount, 1, "请求应已发出")
        task.cancel()
        // 看门狗：3s 内必须恢复（悬挂 = 失败）。task 在 group 外独立存在，group.cancelAll 不影响它。
        let observed: FullImageResult? = await withTaskGroup(of: FullImageResult?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        XCTAssertNotNil(observed, "取消后 3s 内必须 resume（旧版 continuation 悬挂 → SWIFT TASK CONTINUATION MISUSE）")
        if let observed {
            XCTAssertNil(observed.image, "取消路径应返回 nil")
            XCTAssertFalse(observed.isInCloud)
        }
        // 迟到回调也必须被安全吞掉（不崩、不双 resume）
        savedHandler?(nil, [PHImageResultIsInCloudKey: false])
    }
}
