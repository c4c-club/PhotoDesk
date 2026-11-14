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

    // MARK: - applySelection 四态（M17 T06，docs/32 §2.5 单一入口）

    private func makeCell() -> PhotoGridCell {
        let cell = PhotoGridCell(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        cell.configure(item: makeItem("sel-1"), pipeline: NoopPipeline(),
                       pixelSize: CGSize(width: 100, height: 100))
        return cell
    }

    private func dimView(of cell: PhotoGridCell) -> UIView? {
        cell.contentView.subviews.first { $0.backgroundColor == UIColor.black }
    }

    /// 态 1：多选中且已选——角标可见、dim 0.12、边框 2pt、AX 后缀 selected
    func testApplySelectionSelectedShowsBadgeDimBorderAndAX() {
        let cell = makeCell()
        cell.applySelection(isSelecting: true, isSelected: true, animated: false)
        XCTAssertFalse(cell.selectionBadge.isHidden, "选中态角标必须可见")
        let dim = dimView(of: cell)
        XCTAssertEqual(dim?.alpha ?? -1, 0.12, accuracy: 0.001,
                       "选中压暗必须 12%（验收 0.1–0.15）")
        XCTAssertEqual(cell.contentView.layer.borderWidth, 2, accuracy: 0.001,
                       "选中边框 2pt")
        XCTAssertTrue((cell.accessibilityValue ?? "").hasSuffix(" selected"),
                      "AX 与视觉同源（docs/32 §2.5）")
    }

    /// 态 2：多选中但未选——角标隐藏、无压暗、无边框、AX 后缀 none
    func testApplySelectionUnselectedHidesAllVisuals() {
        let cell = makeCell()
        cell.applySelection(isSelecting: true, isSelected: false, animated: false)
        XCTAssertTrue(cell.selectionBadge.isHidden, "未选中不得显示角标")
        XCTAssertEqual(dimView(of: cell)?.alpha ?? -1, 0, accuracy: 0.001,
                       "未选中不得压暗")
        XCTAssertEqual(cell.contentView.layer.borderWidth, 0, accuracy: 0.001,
                       "未选中无边框")
        XCTAssertTrue((cell.accessibilityValue ?? "").hasSuffix(" none"),
                      "AX 后缀必须同步 none")
    }

    /// 态 3：退出多选——视觉全部复位（先选中再退出）
    func testApplySelectionExitMultiSelectResetsVisuals() {
        let cell = makeCell()
        cell.applySelection(isSelecting: true, isSelected: true, animated: false)
        cell.applySelection(isSelecting: false, isSelected: false, animated: false)
        XCTAssertTrue(cell.selectionBadge.isHidden, "退出多选角标必须隐藏")
        XCTAssertEqual(dimView(of: cell)?.alpha ?? -1, 0, accuracy: 0.001,
                       "退出多选必须清除压暗")
        XCTAssertEqual(cell.contentView.layer.borderWidth, 0, accuracy: 0.001,
                       "退出多选必须清除边框")
        XCTAssertTrue((cell.accessibilityValue ?? "").hasSuffix(" none"),
                      "退出多选 AX 后缀必须 none")
    }

    /// 态 4：复用——角标/dim/边框/动画全部复位（docs/25 §6.4 契约扩展到 dim 与动画）
    func testPrepareForReuseResetsSelectionVisuals() {
        let cell = makeCell()
        cell.applySelection(isSelecting: true, isSelected: true, animated: true)
        cell.prepareForReuse()
        XCTAssertTrue(cell.selectionBadge.isHidden, "复用后角标必须隐藏")
        XCTAssertEqual(cell.selectionBadge.transform, .identity,
                       "复用必须清除角标 spring 动画残留")
        XCTAssertEqual(dimView(of: cell)?.alpha ?? -1, 0, accuracy: 0.001,
                       "复用后不得残留压暗")
        XCTAssertEqual(cell.contentView.layer.borderWidth, 0, accuracy: 0.001,
                       "复用后不得残留边框")
    }

    /// 非 animated 路径不得遗留 spring transform（滚动态直接落位）
    func testApplySelectionNonAnimatedLeavesNoTransform() {
        let cell = makeCell()
        cell.applySelection(isSelecting: true, isSelected: true, animated: false)
        XCTAssertEqual(cell.selectionBadge.transform, .identity,
                       "非动画路径角标 transform 必须为 identity")
    }
}
