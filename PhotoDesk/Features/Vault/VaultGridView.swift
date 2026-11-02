// MARK: - 职责说明：已隐藏相册网格（docs/09 D05）——UIKit UICollectionView + Compositional Layout，
// 复用 PhotoGridCell（AGENTS §3.3：隐藏库量级小也不豁免 UIKit 管线）；cell 可点开查看器；
// 上下文菜单（取消隐藏/移到最近删除/收藏）经 UIContextMenuInteraction 由 VC 提供。

import UIKit
import SwiftUI

/// 隐藏库网格控制器（轻量；无多选/框选）
final class VaultGridViewController: UIViewController {
    var items: [PhotoItem] = [] {
        didSet {
            guard isViewLoaded else { return }
            collectionView.reloadData()
        }
    }
    var pipeline: ImagePipelineProtocol?
    var onTap: ((PhotoItem) -> Void)?
    /// 上下文菜单（nil = 该项不显示菜单）
    var menuProvider: ((PhotoItem) -> UIMenu?)?
    var onItemsChanged: (() -> Void)?
    /// 待隐藏角标（未提交项）
    var pendingHideIDs: Set<String> = []

    private var collectionView: UICollectionView!
    private let pixelSize: CGSize = {
        let width = (UIScreen.main.bounds.width - 2 * DSSpacing.gridSpacing) / 3
        let scale = UIScreen.main.scale
        return CGSize(width: width * scale, height: width * scale)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
    }

    private func setupCollectionView() {
        let layout = Self.makeLayout()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: "VaultGridCell")
        view.addSubview(collectionView)
    }

    static func makeLayout() -> UICollectionViewCompositionalLayout {
        let columns = 3
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .fractionalWidth(1.0 / CGFloat(columns)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
        group.interItemSpacing = .fixed(DSSpacing.gridSpacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = DSSpacing.gridSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: DSSpacing.gridSpacing,
                                                        leading: DSSpacing.gridSpacing,
                                                        bottom: DSSpacing.gridSpacing,
                                                        trailing: DSSpacing.gridSpacing)
        return UICollectionViewCompositionalLayout(section: section)
    }

    func reload(items: [PhotoItem], pendingHideIDs: Set<String>) {
        self.items = items
        self.pendingHideIDs = pendingHideIDs
        guard isViewLoaded else { return }
        collectionView.reloadData()
    }
}

extension VaultGridViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VaultGridCell", for: indexPath)
        guard let gridCell = cell as? PhotoGridCell else { return cell }
        let item = items[indexPath.item]
        if let pipeline {
            gridCell.configure(item: item, pipeline: pipeline, pixelSize: pixelSize)
        }
        gridCell.setSelectionVisible(false)
        gridCell.setSelected(false)
        gridCell.isAccessibilityElement = true
        gridCell.accessibilityLabel = PhotoGridCell.accessibilityLabel(for: item)
        gridCell.accessibilityHint = "点按查看大图，长按更多操作"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = items[safe: indexPath.item] else { return }
        onTap?(item)
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = items[safe: indexPath.item],
              let menu = menuProvider?(item) else { return nil }
        return UIContextMenuConfiguration(identifier: nil) { nil } actionProvider: { _ in menu }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {}
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// SwiftUI 桥
struct VaultGridView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: VaultViewModel
    let pipeline: ImagePipelineProtocol
    var onTap: (PhotoItem) -> Void

    func makeUIViewController(context: Context) -> VaultGridViewController {
        let controller = VaultGridViewController()
        controller.pipeline = pipeline
        controller.onTap = onTap
        controller.menuProvider = { [weak viewModel] item in
            viewModel?.contextMenu(for: item)
        }
        viewModel.onItemsChanged = { [weak controller, weak viewModel] in
            guard let controller, let viewModel else { return }
            controller.reload(items: viewModel.items, pendingHideIDs: viewModel.pendingHideIDs)
        }
        controller.items = viewModel.items
        controller.pendingHideIDs = viewModel.pendingHideIDs
        return controller
    }

    func updateUIViewController(_ controller: VaultGridViewController, context: Context) {
        controller.onTap = onTap
        controller.reload(items: viewModel.items, pendingHideIDs: viewModel.pendingHideIDs)
    }
}
