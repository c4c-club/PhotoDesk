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

    // MARK: - 多选与批量（docs/05 M3 任务 5）

    private(set) var isSelecting = false
    private var selectedIDs = Set<String>()
    private var isBatchRunning = false
    private let selectionBar = UIToolbar()
    private let batchToast = DSToast(frame: .zero)
    private var selectionPan: UIPanGestureRecognizer!
    private let selectionOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = DSColor.tint.withAlphaComponent(0.15)
        view.layer.borderColor = DSColor.tint.cgColor
        view.layer.borderWidth = 1
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()
    private var selectionStartPoint: CGPoint?
    private var selectAllItem: UIBarButtonItem!
    private var doneItem: UIBarButtonItem!

    // MARK: - 快照缓存

    private var currentSections: [MonthSection] = []
    private var currentItemsBySection: [[PhotoItem]] = []
    /// 上一次布局时配置 cell 所用的像素尺寸（变化时重配可视 cell）
    private var lastConfiguredPixelSize: CGSize = .zero
    /// 网格点击 → 打开全屏浏览器（扁平 index：Section=月份 → 全序换算）
    var onOpenViewer: ((Int) -> Void)?

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
        setupSelection()
        setupBatchToast()
        wireViewModel()
        // UI 测试钩子：-uiTestingSelectMode 启动即进入多选（绕开长按/工具栏按钮在 XCUITest 中的不可靠性）
        if ProcessInfo.processInfo.arguments.contains("-uiTestingSelectMode") {
            enterSelectionMode(selecting: nil)
        }

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
        collectionView.allowsSelection = true
        view.addSubview(collectionView)
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<PhotoGridCell, PhotoItem> { [weak self] cell, _, item in
            guard let self else { return }
            cell.configure(item: item, pipeline: self.pipeline, pixelSize: self.cellPixelSize)
            cell.setSelectionVisible(self.isSelecting)
            cell.setSelected(self.selectedIDs.contains(item.id))
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

    private func setupBatchToast() {
        batchToast.translatesAutoresizingMaskIntoConstraints = false
        batchToast.alpha = 0
        view.addSubview(batchToast)
        NSLayoutConstraint.activate([
            batchToast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DSSpacing.screenPadding),
            batchToast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DSSpacing.screenPadding),
            batchToast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DSSpacing.toastBottomOffset),
        ])
    }

    // MARK: - 多选模式（点选 / 框选 / 全选；长按进入）

    private func setupSelection() {
        selectionBar.translatesAutoresizingMaskIntoConstraints = false
        selectionBar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        selectionBar.barTintColor = DSColor.bgSecondary.withAlphaComponent(0.96)
        selectionBar.isHidden = true
        view.addSubview(selectionBar)

    func barItem(_ symbol: String, _ label: String, action: Selector) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol),
                                       style: .plain, target: self, action: action)
            item.accessibilityLabel = label
            return item
        }
        selectAllItem = barItem("checkmark.circle", "全选", action: #selector(selectAllTapped))
        selectAllItem.accessibilityIdentifier = "Batch-SelectAll"
        doneItem = barItem("xmark.circle.fill", "完成", action: #selector(doneSelectingTapped))
        doneItem.accessibilityIdentifier = "Batch-Done"
        let deleteItem = barItem("trash", "移到最近删除", action: #selector(batchDeleteTapped))
        deleteItem.accessibilityIdentifier = "Batch-Delete"
        selectionBar.setItems([
            doneItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            selectAllItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            barItem("heart", "收藏", action: #selector(batchFavoriteTapped)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            barItem("eye.slash", "隐藏", action: #selector(batchHideTapped)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            deleteItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            barItem("folder.badge.plus", "加相簿", action: #selector(batchAddToAlbumTapped)),
        ], animated: false)
        NSLayoutConstraint.activate([
            selectionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            selectionBar.heightAnchor.constraint(equalToConstant: 46),
        ])

        // 框选：多选模式下启用的第二把 Pan
        selectionPan = UIPanGestureRecognizer(target: self, action: #selector(onSelectionPan(_:)))
        selectionPan.isEnabled = false
        selectionPan.maximumNumberOfTouches = 1
        collectionView.addGestureRecognizer(selectionPan)
        view.addSubview(selectionOverlay)

        // 长按进入多选
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        collectionView.addGestureRecognizer(longPress)
    }

    /// 工具栏「多选」按钮（docs/04 §3.1）：切换多选模式（与长按进入等价）
    func toggleSelectionMode() {
        if isSelecting {
            exitSelectionMode()
        } else {
            enterSelectionMode(selecting: nil)
        }
    }

    private func enterSelectionMode(selecting id: String?) {
        guard !isSelecting else { return }
        isSelecting = true
        selectedIDs.removeAll()
        selectionPan.isEnabled = true
        selectionBar.isHidden = false
        indexBar.isHidden = true
        reloadSelectionBadges()
        if let id {
            selectedIDs.insert(id)
            reloadSelectionBadges()
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedIDs.removeAll()
        selectionPan.isEnabled = false
        selectionBar.isHidden = true
        indexBar.isHidden = false
        reloadSelectionBadges()
    }

    @objc private func doneSelectingTapped() {
        exitSelectionMode()
    }

    @objc private func onLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isSelecting else { return }
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        enterSelectionMode(selecting: currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item]?.id)
    }

    private func toggleSelection(id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        reloadSelectionBadges()
    }

    private func reloadSelectionBadges() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell else { continue }
            cell.setSelectionVisible(isSelecting)
            let id = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item]?.id
            cell.setSelected(id.map { selectedIDs.contains($0) } ?? false)
        }
    }

    @objc private func selectAllTapped() {
        selectedIDs = Set(currentItemsBySection.flatMap { $0.map(\.id) })
        reloadSelectionBadges()
    }

    // MARK: - 框选

    @objc private func onSelectionPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: collectionView)
        switch gesture.state {
        case .began:
            selectionStartPoint = location
        case .changed:
            guard let start = selectionStartPoint else { return }
            let rect = CGRect(x: min(start.x, location.x),
                              y: min(start.y, location.y),
                              width: abs(start.x - location.x),
                              height: abs(start.y - location.y))
            selectionOverlay.frame = rect
            selectionOverlay.isHidden = false
            // 公开 API 没有 indexPathsForElements(in:)：经 layout 查询矩形内的元素
            let attributes = collectionView.collectionViewLayout
                .layoutAttributesForElements(in: rect) ?? []
            for indexPath in attributes.map(\.indexPath) {
                guard let id = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item]?.id else { continue }
                if !selectedIDs.contains(id) {
                    selectedIDs.insert(id)
                    if let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell {
                        cell.setSelected(true)
                    }
                }
            }
        case .ended, .cancelled:
            selectionOverlay.isHidden = true
            selectionStartPoint = nil
        default:
            break
        }
    }

    // MARK: - 批量动作

    @objc private func batchFavoriteTapped() { runBatch(.setFavorite(true)) }
    @objc private func batchHideTapped() { runBatch(.setHidden(true)) }

    @objc private func batchDeleteTapped() {
        // docs/04 §7 清理确认口径：移到「最近删除」≠ 永久删除
        let alert = UIAlertController(
            title: "移到「最近删除」？",
            message: "将把 \(selectedIDs.count) 张照片移到「最近删除」。照片会在那里保留 30 天，期间随时可以在系统相册恢复，不是永久删除。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "移到最近删除", style: .destructive) { [weak self] _ in
            self?.runBatch(.moveToRecentlyDeleted)
        })
        present(alert, animated: true)
    }

    @objc private func batchAddToAlbumTapped() {
        let alert = UIAlertController(title: "加入相簿",
                                      message: "将 \(selectedIDs.count) 张照片加入新相簿",
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "相簿名称" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建并加入", style: .default) { [weak self] _ in
            guard let title = alert.textFields?.first?.text, !title.isEmpty else { return }
            Task { @MainActor in
                if let albumID = try? await AppContainer.shared.photoWriter.createAlbum(title: title) {
                    self?.runBatch(.addToAlbum(albumID: albumID))
                }
            }
        })
        present(alert, animated: true)
    }

    private func runBatch(_ action: LibraryViewModel.BatchAction) {
        guard !isBatchRunning, !selectedIDs.isEmpty else { return }
        isBatchRunning = true
        let ids = Array(selectedIDs)
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.viewModel.performBatch(action, ids: ids)
            self.isBatchRunning = false
            self.batchToast.show(icon: "checkmark.circle.fill",
                                 text: outcome.message,
                                 duration: 3.5,
                                 allowUndo: true,
                                 onUndo: { [weak self] in
                Task { await self?.viewModel.undoLatest() }
            },
                                 onDismissFinished: nil)
            if case .moveToRecentlyDeleted = action {
                self.exitSelectionMode()   // 已删除项随 observer 增量消失
            }
        }
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
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isSelecting {
            // 多选模式：点选 = 勾选/取消
            if let item = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item] {
                toggleSelection(id: item.id)
            }
            return
        }
        // 扁平 index：按 section 累加前缀 + 组内偏移（Viewer 以 items 全序定位起始页）
        var flatIndex = 0
        for section in 0..<indexPath.section {
            flatIndex += currentItemsBySection[safe: section]?.count ?? 0
        }
        flatIndex += indexPath.item
        onOpenViewer?(flatIndex)
    }

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
