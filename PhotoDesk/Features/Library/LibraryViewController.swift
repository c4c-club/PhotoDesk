// MARK: - 职责说明：照片库网格控制器（docs/05 M1 任务 1.4 / docs/04 §3.1）——
// UICollectionView + Compositional Layout（列数 2-5 可切换）+ Diffable DataSource（Section = 月份）+
// 粘性分组头（boundarySupplementaryItem.pinToVisibleBounds）+ Prefetching + 分页（接近底部续页 500/批）+
// 右侧月份索引条。数据经 LibraryViewModel 推送（onSnapshotUpdate），本类不直接触碰 PhotoKit。

import UIKit
import SwiftUI
import PhotoDeskCore

final class LibraryViewController: UIViewController {
    // MARK: - 依赖

    private let viewModel: LibraryViewModel
    private let pipeline: ImagePipelineProtocol
    private let settings: SettingsStore

    // MARK: - UI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<MonthSection, PhotoItem>!
    private let indexBar = MonthIndexBar()
    private var columns: Int

    // MARK: - 快照缓存

    private var currentSections: [MonthSection] = []
    private var currentItemsBySection: [[PhotoItem]] = []
    /// 上一次布局时配置 cell 所用的像素尺寸（变化时重配可视 cell）
    private var lastConfiguredPixelSize: CGSize = .zero

    init(viewModel: LibraryViewModel, pipeline: ImagePipelineProtocol, settings: SettingsStore) {
        self.viewModel = viewModel
        self.pipeline = pipeline
        self.settings = settings
        self.columns = max(2, min(5, settings.gridColumns))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用（纯代码构建）")
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        // 动态 UIColor 自适应深浅色
        view.backgroundColor = DSColor.bgPrimary
        setupCollectionView()
        setupDataSource()
        setupIndexBar()
        wireViewModel()

        viewModel.onManageLimitedPhotos = { [weak self] in
            guard let self else { return }
            // .limited：调起系统「管理选中照片」选择器（docs/03 §5.6）
            AppContainer.shared.libraryService.presentLimitedLibraryPicker(from: self)
        }
    }

    // MARK: - 构建

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout(columns: columns))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<PhotoGridCell, PhotoItem> { [weak self] cell, _, item in
            guard let self else { return }
            cell.configure(item: item, pipeline: self.pipeline, pixelSize: self.cellPixelSize)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<MonthHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let section = self?.currentSections[safe: indexPath.section] else { return }
            header.configure(title: section.headerTitle)
        }

        dataSource = UICollectionViewDiffableDataSource<MonthSection, PhotoItem>(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func setupIndexBar() {
        indexBar.translatesAutoresizingMaskIntoConstraints = false
        indexBar.backgroundColor = .clear
        indexBar.onIndexChange = { [weak self] sectionIndex in
            self?.scrollToSection(sectionIndex)
        }
        view.addSubview(indexBar)
        NSLayoutConstraint.activate([
            indexBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -2),
            indexBar.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            indexBar.widthAnchor.constraint(equalToConstant: 44),
            indexBar.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),
        ])
    }

    private func wireViewModel() {
        // attachSnapshotHandler：接入即重放当前快照（VM 可能先于本 VC 完成加载）
        viewModel.attachSnapshotHandler { [weak self] sections, itemsBySection, animated in
            self?.applySnapshot(sections: sections, itemsBySection: itemsBySection, animated: animated)
        }
    }

    // MARK: - 快照

    private func applySnapshot(sections: [MonthSection], itemsBySection: [[PhotoItem]], animated: Bool) {
        currentSections = sections
        currentItemsBySection = itemsBySection

        var snapshot = NSDiffableDataSourceSnapshot<MonthSection, PhotoItem>()
        snapshot.appendSections(sections)
        for (section, items) in zip(sections, itemsBySection) {
            snapshot.appendItems(items, toSection: section)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
        syncIndexBar()
    }

    private func scrollToSection(_ index: Int) {
        guard index < currentSections.count else { return }
        collectionView.scrollToItem(at: IndexPath(item: 0, section: index),
                                    at: .top,
                                    animated: false)
    }

    // MARK: - 列数切换（设置 grid.columns 2/3/4/5，记忆由 @AppStorage 保证）

    func setColumns(_ newColumns: Int) {
        let clamped = max(2, min(5, newColumns))
        guard clamped != columns else { return }
        columns = clamped
        collectionView.collectionViewLayout = makeLayout(columns: clamped)
        // 列宽变化 → cell 内取图尺寸变化 → 重载可视 cell（缓存键含尺寸，自动落新缓存）
        let visible = collectionView.indexPathsForVisibleItems
        collectionView.reloadItems(at: visible)
    }

    // MARK: - 布局

    private func makeLayout(columns: Int) -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .fractionalWidth(1.0 / CGFloat(columns)))
        // subitem:count: 把单个 item 复制为 columns 列
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
        group.interItemSpacing = .fixed(DSSpacing.gridSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = DSSpacing.gridSpacing
        section.contentInsets = .zero

        // 粘性月份分组头（docs/04 §3.1：2026年10月 · 128 张）
        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                heightDimension: .absolute(48))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                 elementKind: UICollectionView.elementKindSectionHeader,
                                                                 alignment: .top)
        header.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [header]
        return UICollectionViewCompositionalLayout(section: section)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 首次布局前 dequeue 的 cell 拿到的是占位尺寸：布局稳定后重配可视 cell（缓存键含尺寸）
        let pixel = cellPixelSize
        if lastConfiguredPixelSize != .zero, pixel != lastConfiguredPixelSize {
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        }
        lastConfiguredPixelSize = pixel
    }

    /// 单个 cell 的像素尺寸（正方形；缓存键与预取共用，列数切换时随之变化）
    private var cellPixelSize: CGSize {
        let width = (view.bounds.width - CGFloat(columns - 1) * DSSpacing.gridSpacing) / CGFloat(columns)
        let scale = UIScreen.main.scale
        return CGSize(width: width * scale, height: width * scale)
    }

    // MARK: - 索引条同步

    private func syncIndexBar() {
        var entries: [MonthIndexBar.Entry] = []
        var lastYear: String?
        for section in currentSections {
            let year = String(section.id.prefix(4))
            if section.id == DateSectionizer.unknownIdentifier {
                entries.append(MonthIndexBar.Entry(label: "?"))
            } else if year != lastYear {
                entries.append(MonthIndexBar.Entry(label: year))
                lastYear = year
            } else {
                entries.append(MonthIndexBar.Entry(label: nil))
            }
        }
        indexBar.update(entries: entries, highlightedIndex: -1)
    }
}

// MARK: - Delegate（分页 + 预取）

extension LibraryViewController: UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 接近底部 → 续页（每批 500）
        let threshold = scrollView.contentSize.height - scrollView.bounds.height * 2
        if scrollView.contentOffset.y > max(0, threshold) {
            Task { await viewModel.loadNextPage() }
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        let ids = indexPaths.compactMap { currentItemsBySection[safe: $0.section]?[safe: $0.item]?.id }
        guard !ids.isEmpty else { return }
        let pixel = cellPixelSize
        pipeline.prefetch(ids: ids, size: CGSize(width: pixel.width, height: pixel.height))
    }

    func collectionView(_ collectionView: UICollectionView,
                        cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let ids = indexPaths.compactMap { currentItemsBySection[safe: $0.section]?[safe: $0.item]?.id }
        ids.forEach { pipeline.cancel(id: $0) }
    }

    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        // 兜底分页（某些快速滚动场景 scrollViewDidScroll 阈值不可靠）
        if indexPath.section >= currentSections.count - 1 {
            let itemsInSection = currentItemsBySection[safe: indexPath.section]?.count ?? 0
            if indexPath.item >= itemsInSection - 12 {
                Task { await viewModel.loadNextPage() }
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? PhotoGridCell)?.cancelLoad()
    }
}

// MARK: - 月份粘性分组头

final class MonthHeaderView: UICollectionReusableView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.sectionHeader)
        // 动态 UIColor 直接赋值即可随深浅色切换
        label.textColor = DSColor.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DSColor.bgPrimary
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DSSpacing.screenPadding),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}

// MARK: - 安全取值

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
