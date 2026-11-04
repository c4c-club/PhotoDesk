// MARK: - 职责说明：ViewerViewController 首布局 itemSize 单元测试（docs/16 M12 R01/A4）——
// 基线红：viewDidLoad 设 itemSize = view.bounds.size（fullScreenCover 首布局为 .zero），
// viewDidLayoutSubviews 从不刷新 → 所有 cell 零尺寸 → 整页空白。

import XCTest
import UIKit
@testable import PhotoDesk

@MainActor
final class ViewerViewControllerLayoutTests: XCTestCase {
    private func makeViewController() -> ViewerViewController {
        let container = AppContainer.shared
        let items = (0..<6).map { index in
            PhotoItem(id: "layout-\(index)-\(UUID().uuidString)",
                      mediaType: .image,
                      mediaSubtypes: [],
                      creationDate: Date(),
                      modificationDate: nil,
                      pixelWidth: 100,
                      pixelHeight: 100,
                      duration: 0,
                      isFavorite: false,
                      isHidden: false,
                      location: nil,
                      burstIdentifier: nil,
                      isCloudOnly: false)
        }
        let context = ViewerContext(items: items, startItemID: items[0].id)
        let viewModel = ViewerViewModel(context: context,
                                        settings: container.settings,
                                        writer: container.photoWriter,
                                        trashBin: container.trashBin,
                                        undoCenter: container.undoCenter,
                                        reviewSession: container.reviewSession)
        return ViewerViewController(viewModel: viewModel,
                                    pipeline: container.imagePipeline,
                                    settings: container.settings,
                                    undoCenter: container.undoCenter)
    }

    /// 正常 bounds 首布局：itemSize == bounds
    func testFirstLayoutItemSizeEqualsBounds() {
        let controller = makeViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        let layout = controller.test_collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        XCTAssertEqual(layout?.itemSize, CGSize(width: 390, height: 700),
                       "A4：itemSize 必须等于 view.bounds（旧版仅 viewDidLoad 设一次）")
    }

    /// 零 bounds 首布局（fullScreenCover 常见）→ 拿到真实 bounds 后必须自恢复
    func testZeroBoundsThenLayoutRecovers() {
        let controller = makeViewController()
        controller.view.frame = .zero
        controller.loadViewIfNeeded()   // viewDidLoad：itemSize = .zero（旧版此后永不刷新）
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let layout = controller.test_collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        XCTAssertEqual(layout?.itemSize, CGSize(width: 390, height: 700),
                       "A4：零 bounds 首布局后，viewDidLayoutSubviews 必须把 itemSize 刷新到真实 bounds")
        XCTAssertGreaterThan(controller.test_collectionView.numberOfItems(inSection: 0), 0)
    }
}
