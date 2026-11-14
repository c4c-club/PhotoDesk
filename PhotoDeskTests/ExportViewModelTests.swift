// MARK: - 职责说明：导出 ViewModel 测试（M17 T08 X05，docs/31 §3）——
// 取件失败路径 downloadProgress 必须复位（进度条卡死缺陷的回归锁）。

import XCTest
import AVFoundation
import UIKit
@testable import PhotoDesk

@MainActor
final class ExportViewModelTests: XCTestCase {

    /// iCloud 下载失败管道：推进度 0.5 后返回 nil（复现「失败路径不复位」现场）
    private final class FailingCloudPipeline: ImagePipelineProtocol {
        func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage? { nil }
        func prefetch(ids: [String], size: CGSize) {}
        func cancel(id: String) {}
        func cancelAll() {}
        func fullImageWithState(for id: String, progress: @escaping (Double) -> Void,
                                allowNetwork: Bool) async -> FullImageResult {
            progress(0.5)
            return FullImageResult(image: nil, isInCloud: false)
        }
        func videoAsset(for id: String) async -> (asset: AVAsset, audioMix: AVAudioMix?)? { nil }
        var diskCacheBytes: Int64 { 0 }
        func clearCaches() {}
    }

    private func cloudItem() -> PhotoItem {
        PhotoItem(id: "cloud-0",
                  mediaType: .image, mediaSubtypes: [],
                  creationDate: nil, modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: false, isHidden: false,
                  location: nil, burstIdentifier: nil, isCloudOnly: true)
    }

    func testDownloadProgressResetsOnSourceFailure() async {
        let vm = ExportViewModel(item: cloudItem(),
                                 pipeline: FailingCloudPipeline(),
                                 writer: MockPhotoWriter(),
                                 settings: SettingsStore())
        do {
            _ = try await vm.requestSourceURL()
            XCTFail("iCloud 取件失败必须抛错")
        } catch {
            // 期待路径：cannotLoadImage
        }
        XCTAssertNil(vm.downloadProgress,
                     "失败路径 downloadProgress 必须复位（X05：进度条卡死缺陷），got \(String(describing: vm.downloadProgress))")
    }
}