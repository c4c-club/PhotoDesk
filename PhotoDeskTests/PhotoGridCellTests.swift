// MARK: - 职责说明：R08 徽标/AX 同步 + R06 分类菜单装配单测（docs/16 M12 Phase 5/6）——
// 基线红：testSelectionBadgesStayInSyncAfterConfigure（configure 重置 AX value 不补选中后缀）。
// LibraryCategoryMenuBuilderTests 为回归守卫（builder 随实现落地；语义锁 5 项顺序/勾选/计数/hidden 不泄露）。

import XCTest
import UIKit
import Photos
import AVFoundation
@testable import PhotoDesk

@MainActor
private final class NoopPipeline: ImagePipelineProtocol {
    func thumbnail(for id: String, size: CGSize, scale: CGFloat) async -> UIImage? { nil }
    func prefetch(ids: [String], size: CGSize) {}
    func cancel(id: String) {}
    func cancelAll() {}
    func fullImageWithState(for id: String, progress: @escaping (Double) -> Void,
                            allowNetwork: Bool) async -> FullImageResult {
        FullImageResult(image: nil, isInCloud: false)
    }
    func videoAsset(for id: String) async -> (asset: AVAsset, audioMix: AVAudioMix?)? { nil }
    var diskCacheBytes: Int64 { 0 }
    func clearCaches() {}
}

@MainActor
final class PhotoGridCellTests: XCTestCase {
    private func makeItem(_ id: String) -> PhotoItem {
        PhotoItem(id: id,
                  mediaType: .image,
                  mediaSubtypes: [],
                  creationDate: nil,
                  modificationDate: nil,
                  pixelWidth: 10, pixelHeight: 10, duration: 0,
                  isFavorite: false, isHidden: false,
                  location: nil, burstIdentifier: nil,
                  isCloudOnly: false)
    }

    /// R08：cell 复用重配后 AX value 必须带当前选中态后缀（docs/09 D11 契约「<assetID> selected/none」）
    func testSelectionBadgesStayInSyncAfterConfigure() {
        let cell = PhotoGridCell(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        cell.setSelected(true)
        cell.configure(item: makeItem("ax-1"), pipeline: NoopPipeline(),
                       pixelSize: CGSize(width: 100, height: 100))
        XCTAssertTrue((cell.accessibilityValue ?? "").hasSuffix("selected"),
                      "R08：configure 重置 AX value 后必须按当前选中态补后缀（旧版复用后丢 selected → 断言红）")

        cell.setSelected(false)
        XCTAssertTrue((cell.accessibilityValue ?? "").hasSuffix("none"),
                      "取消选中后 AX 后缀必须为 none")

        // 复用场景：重配另一 item（未选中态）
        cell.setSelected(true)
        cell.configure(item: makeItem("ax-2"), pipeline: NoopPipeline(),
                       pixelSize: CGSize(width: 100, height: 100))
        XCTAssertTrue((cell.accessibilityValue ?? "").hasPrefix("ax-2"),
                      "configure 必须写入新 item id")
    }
}
