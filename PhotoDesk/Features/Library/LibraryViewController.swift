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
    private let positionStore: LibraryPositionStore

    // MARK: - UI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<MonthSection, PhotoItem>!
    private let indexBar = MonthIndexBar()
    private var columns: Int

    // MARK: - 多选与批量（docs/09 D11/D12/D13 重做：SelectionState + 长按框选）

    private(set) var isSelecting = false
    /// 选择状态（PhotoDeskCore.SelectionPolicy：scope = 当前筛选结果全集）
    private var selectionState = SelectionState()
    private var isBatchRunning = false
    /// 底部多选工具栏（两行：取消/计数/完成 + 横向滚动操作行）
    private let selectionBar = UIView()
    private let selectionCountLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.body)
        label.textColor = DSColor.textPrimary
        label.textAlignment = .center
        label.accessibilityIdentifier = "Selection-Count"
        label.accessibilityLabel = "已选择 0 项"
        return label
    }()
    private let batchToast = DSToast(frame: .zero)
    private let selectionOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = DSColor.tint.withAlphaComponent(0.15)
        view.layer.borderColor = DSColor.tint.cgColor
        view.layer.borderWidth = 1
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()
    /// 框选状态：长按起点（nil = 无长按进行中）
    private var boxStartPoint: CGPoint?
    /// 框选进行中（移动超过 10pt 后进入；此时滚动禁用）
    private var isBoxSelecting = false
    private var lastBoxPoint: CGPoint = .zero
    private var boxAutoScrollLink: CADisplayLink?

    // MARK: - 快照缓存

    private var currentSections: [MonthSection] = []
    private var currentItemsBySection: [[PhotoItem]] = []
    /// 上一次布局时配置 cell 所用的像素尺寸（变化时重配可视 cell）
    private var lastConfiguredPixelSize: CGSize = .zero
    /// 网格点击 → 打开全屏浏览器（ViewerContext：当前筛选结果 + 被点条目，docs/09 D01）
    var onOpenViewer: ((PhotoItem) -> Void)?

    // MARK: - 下拉刷新（docs/09 D15）

    private let refreshControl = UIRefreshControl()

    // MARK: - 位置记忆（docs/09 D08）

    private var isRestoringPosition = false
    private var didRestorePosition = false
    private var positionSaveTimer: Timer?

    init(viewModel: LibraryViewModel,
         pipeline: ImagePipelineProtocol,
         settings: SettingsStore,
         positionStore: LibraryPositionStore) {
        self.viewModel = viewModel
        self.pipeline = pipeline
        self.settings = settings
        self.positionStore = positionStore
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 切 Tab / 进设置 / 返回前强制保存位置（docs/09 D08）
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
        savePositionIfNeeded()
    }

    /// 旋转 / 分屏（docs/09 Phase 7）：布局随尺寸更新，保持当前锚点不跳
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.collectionView.collectionViewLayout = self.makeLayout(columns: self.columns)
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }, completion: nil)
    }

    // MARK: - 构建

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout(columns: columns))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.allowsSelection = true
        // 下拉刷新（docs/09 D15）：保留当前筛选与位置
        refreshControl.addTarget(self, action: #selector(didPullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        // 双指捏合调列数（docs/09 D14）：允许与单指滚动同时识别
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        collectionView.addGestureRecognizer(pinch)
        view.addSubview(collectionView)
    }

    // MARK: - 捏合列数（docs/09 D14：2–5 列吸附、锚点保持、触觉、持久化、首次提示）

    private var pinchStartColumns = 3
    private var pinchTargetColumns = 3
    private var pinchAnchorIndexPath: IndexPath?

    @objc private func onPinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartColumns = columns
            pinchTargetColumns = columns
            pinchAnchorIndexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView))

        case .changed:
            guard gesture.scale > 0 else { return }
            let target = max(2, min(5, Int((CGFloat(pinchStartColumns) / gesture.scale).rounded())))
            guard target != pinchTargetColumns else { return }
            pinchTargetColumns = target
            setColumns(target, animated: true, anchor: pinchAnchorIndexPath)
            if settings.hapticsEnabled {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            showPinchHintOnce()

        case .ended, .cancelled:
            // 松手：scale 接近 1 回弹到起始列数；否则持久化（docs/09 D14）
            if abs(gesture.scale - 1) < 0.08, pinchStartColumns != columns {
                setColumns(pinchStartColumns, animated: true, anchor: pinchAnchorIndexPath)
            }
            settings.gridColumns = columns
            pinchAnchorIndexPath = nil

        default:
            break
        }
    }

    private func showPinchHintOnce() {
        let key = "grid.pinchHintShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        batchToast.show(icon: "hand.draw",
                        text: "双指捏合可调整列数",
                        duration: 2.5,
                        allowUndo: false,
                        onUndo: nil,
                        onDismissFinished: nil)
    }

    @objc private func didPullToRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.reload()
            self.refreshControl.endRefreshing()
        }
    }

    private var usesMotion: Bool {
        !(UIAccessibility.isReduceMotionEnabled && settings.respectReduceMotion)
    }

    private func setupDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<PhotoGridCell, PhotoItem> { [weak self] cell, _, item in
            guard let self else { return }
            cell.configure(item: item, pipeline: self.pipeline, pixelSize: self.cellPixelSize)
            cell.setSelectionVisible(self.isSelecting)
            cell.setSelected(self.selectionState.selectedSet.contains(item.id))
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<MonthHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let section = self?.currentSections[safe: indexPath.section] else { return }
            header.configure(title: section.headerTitle)
            // 月份头「选择」（docs/09 D15）：进入该月多选（scope = 该月 items）
            header.onSelect = { [weak self] in
                self?.enterSelectionMode(section: indexPath.section)
            }
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

    // MARK: - 多选模式（docs/09 D12：顶部取消/计数/完成；操作行可横滚；D13：长按拖拽框选）

    private func setupSelection() {
        selectionBar.translatesAutoresizingMaskIntoConstraints = false
        selectionBar.backgroundColor = DSColor.bgSecondary.withAlphaComponent(0.98)
        selectionBar.isHidden = true
        view.addSubview(selectionBar)
        view.addSubview(selectionOverlay)

        // 第一行：取消 | 已选择 N 项 | 完成
        let cancelButton = barButton(symbol: "xmark", label: "取消", identifier: "Batch-Cancel",
                                     action: #selector(doneSelectingTapped))
        let doneButton = barButton(symbol: "checkmark", label: "完成", identifier: "Batch-Done",
                                   action: #selector(doneSelectingTapped))
        let topRow = UIStackView(arrangedSubviews: [cancelButton,
                                                    selectionCountLabel,
                                                    doneButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.distribution = .equalSpacing
        topRow.translatesAutoresizingMaskIntoConstraints = false

        // 第二行：横向滚动操作按钮（docs/09 D12：避免 11 item 溢出）
        let selectAllButton = barButton(symbol: "checkmark.circle", label: "全选", identifier: "Batch-SelectAll",
                                        action: #selector(selectAllTapped))
        let favoriteButton = barButton(symbol: "heart", label: "收藏", identifier: "Batch-Favorite",
                                       action: #selector(batchFavoriteTapped))
        let hideButton = barButton(symbol: "eye.slash", label: "隐藏", identifier: "Batch-Hide",
                                   action: #selector(batchHideTapped))
        let deleteButton = barButton(symbol: "trash", label: "移到最近删除", identifier: "Batch-Delete",
                                     action: #selector(batchDeleteTapped))
        let albumButton = barButton(symbol: "folder.badge.plus", label: "加相簿", identifier: "Batch-Album",
                                    action: #selector(batchAddToAlbumTapped))

        // 更多菜单：反选 / 取消全选 / 取消收藏 / 分享（docs/09 D11/D12）
        let moreButton = barButton(symbol: "ellipsis.circle", label: "更多", identifier: "Batch-More",
                                   action: nil)
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [
            UIAction(title: "反选") { [weak self] _ in self?.invertSelection() },
            UIAction(title: "取消全选") { [weak self] _ in self?.deselectAll() },
            UIAction(title: "取消收藏") { [weak self] _ in self?.runBatch(.setFavorite(false)) },
            UIAction(title: "分享…") { [weak self] _ in self?.batchShareTapped() },
        ])

        let actionRow = UIScrollView()
        actionRow.showsHorizontalScrollIndicator = false
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        let actionStack = UIStackView(arrangedSubviews: [selectAllButton, favoriteButton, hideButton,
                                                         deleteButton, albumButton, moreButton])
        actionStack.axis = .horizontal
        actionStack.spacing = 26
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionRow.addSubview(actionStack)

        let rowStack = UIStackView(arrangedSubviews: [topRow, actionRow])
        rowStack.axis = .vertical
        rowStack.spacing = 2
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        selectionBar.addSubview(rowStack)

        NSLayoutConstraint.activate([
            selectionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            selectionBar.heightAnchor.constraint(equalToConstant: 84),

            rowStack.topAnchor.constraint(equalTo: selectionBar.topAnchor, constant: 4),
            rowStack.leadingAnchor.constraint(equalTo: selectionBar.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: selectionBar.trailingAnchor, constant: -16),
            rowStack.bottomAnchor.constraint(equalTo: selectionBar.bottomAnchor, constant: -2),

            actionRow.heightAnchor.constraint(equalToConstant: 40),
            actionStack.leadingAnchor.constraint(equalTo: actionRow.contentLayoutGuide.leadingAnchor, constant: 4),
            actionStack.trailingAnchor.constraint(equalTo: actionRow.contentLayoutGuide.trailingAnchor, constant: -4),
            actionStack.topAnchor.constraint(equalTo: actionRow.contentLayoutGuide.topAnchor),
            actionStack.bottomAnchor.constraint(equalTo: actionRow.contentLayoutGuide.bottomAnchor),
            actionStack.heightAnchor.constraint(equalTo: actionRow.frameLayoutGuide.heightAnchor),
        ])

        // D13：删除常驻 selectionPan；单个长按手势驱动「进入多选 + 拖拽框选」
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onBoxLongPress(_:)))
        longPress.minimumPressDuration = 0.28
        longPress.allowableMovement = 10
        collectionView.addGestureRecognizer(longPress)
    }

    private func barButton(symbol: String, label: String, identifier: String,
                           action: Selector?) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = DSColor.tint
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        return button
    }

    /// 工具栏「多选」按钮（docs/04 §3.1）：切换多选模式（与长按进入等价）
    func toggleSelectionMode() {
        if isSelecting {
            exitSelectionMode()
        } else {
            enterSelectionMode(selecting: nil)
        }
    }

    private func enterSelectionMode(selecting id: String?, scopeOverride: Set<String>? = nil) {
        guard !isSelecting else { return }
        isSelecting = true
        let scope = scopeOverride ?? Set(currentItemsBySection.flatMap { $0.map(\.id) })
        selectionState.begin(scope: scope, initial: id)
        selectionBar.isHidden = false
        indexBar.isHidden = true
        reloadSelectionBadges()
        updateSelectionCount()
    }

    /// 月份头「选择」（docs/09 D15）：scope = 该月的 items
    private func enterSelectionMode(section: Int) {
        guard !isSelecting else { return }
        let monthItems = currentItemsBySection[safe: section] ?? []
        guard !monthItems.isEmpty else { return }
        enterSelectionMode(selecting: nil, scopeOverride: Set(monthItems.map(\.id)))
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectionState = SelectionState()
        selectionBar.isHidden = true
        indexBar.isHidden = false
        reloadSelectionBadges()
        updateSelectionCount()
    }

    @objc private func doneSelectingTapped() {
        exitSelectionMode()
    }

    private func toggleSelection(id: String) {
        selectionState.toggle(id)
        reloadSelectionBadges()
        updateSelectionCount()
    }

    private func invertSelection() {
        selectionState.invert()
        reloadSelectionBadges()
        updateSelectionCount()
    }

    private func deselectAll() {
        selectionState.deselectAll()
        reloadSelectionBadges()
        updateSelectionCount()
    }

    private func updateSelectionCount() {
        selectionCountLabel.text = "已选择 \(selectionState.selected.count) 项"
        selectionCountLabel.accessibilityLabel = "已选择 \(selectionState.selected.count) 项"
    }

    private func reloadSelectionBadges() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell else { continue }
            cell.setSelectionVisible(isSelecting)
            let id = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item]?.id
            cell.setSelected(id.map { selectionState.selectedSet.contains($0) } ?? false)
        }
    }

    /// 全选/取消全选切换（docs/09 D11：scope = 当前筛选结果全集，非全库）
    @objc private func selectAllTapped() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.viewModel.isIndexing {
                // 索引未完成：等待完整索引（docs/09 D11 §5）
                self.batchToast.show(icon: "hourglass",
                                     text: "正在读取照片库…",
                                     duration: 2,
                                     allowUndo: false,
                                     onUndo: nil, onDismissFinished: nil)
                await self.viewModel.ensureIndexComplete()
                let scope = Set(self.currentItemsBySection.flatMap { $0.map(\.id) })
                self.selectionState.intersectScope(with: scope)
            }
            if self.selectionState.allSelected {
                self.selectionState.deselectAll()
            } else {
                self.selectionState.selectAll()
            }
            self.reloadSelectionBadges()
            self.updateSelectionCount()
        }
    }

    // MARK: - 框选（docs/09 D13：长按 0.28s 进入，移动 >10pt 进入框选，边缘自动滚动，只加不取消）

    @objc private func onBoxLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let point = gesture.location(in: collectionView)
            if !isSelecting {
                guard let indexPath = collectionView.indexPathForItem(at: point),
                      let item = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item] else { return }
                enterSelectionMode(selecting: item.id)
            }
            boxStartPoint = point
            lastBoxPoint = point

        case .changed:
            guard let start = boxStartPoint else { return }
            let location = gesture.location(in: collectionView)
            lastBoxPoint = location
            if !isBoxSelecting {
                let distance = hypot(location.x - start.x, location.y - start.y)
                guard distance > 10 else { return }   // 静止长按不触发框选（普通快速滑动更不会触发）
                isBoxSelecting = true
                collectionView.isScrollEnabled = false   // 此刻才禁用滚动（docs/09 D13）
                selectionOverlay.isHidden = false
                startBoxAutoScroll()
            }
            updateBoxSelection(from: start, to: location)

        case .ended, .cancelled, .failed:
            boxStartPoint = nil
            if isBoxSelecting {
                isBoxSelecting = false
                selectionOverlay.isHidden = true
                collectionView.isScrollEnabled = true   // 松手恢复滚动
                boxAutoScrollLink?.invalidate()
                boxAutoScrollLink = nil
            }

        default:
            break
        }
    }

    private func updateBoxSelection(from start: CGPoint, to location: CGPoint) {
        let rect = CGRect(x: min(start.x, location.x),
                          y: min(start.y, location.y),
                          width: abs(start.x - location.x),
                          height: abs(start.y - location.y))
        selectionOverlay.frame = rect
        // 公开 API 没有 indexPathsForElements(in:)：经 layout 查询矩形内的元素（只加选不取消）
        let attributes = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: rect) ?? []
        for indexPath in attributes.map(\.indexPath) {
            guard let id = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item]?.id else { continue }
            if !selectionState.selectedSet.contains(id) {
                selectionState.select(id)
                if let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell {
                    cell.setSelected(true)
                }
                updateSelectionCount()
            }
        }
    }

    /// 边缘自动滚动（CADisplayLink：手指距顶/底 < 60pt 时 10pt/帧，docs/09 D13）
    private func startBoxAutoScroll() {
        boxAutoScrollLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(boxAutoScrollTick))
        link.add(to: .main, forMode: .common)
        boxAutoScrollLink = link
    }

    @objc private func boxAutoScrollTick() {
        guard isBoxSelecting, let start = boxStartPoint else { return }
        let edge: CGFloat = 60
        let step: CGFloat = 10
        let topDistance = lastBoxPoint.y - collectionView.contentOffset.y
        let bottomDistance = (collectionView.contentOffset.y + collectionView.bounds.height) - lastBoxPoint.y
        var delta: CGFloat = 0
        if topDistance < edge {
            delta = -step
        } else if bottomDistance < edge {
            delta = step
        }
        guard delta != 0 else { return }
        let maxY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(max(0, collectionView.contentOffset.y + delta), maxY)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: targetY), animated: false)
        updateBoxSelection(from: start, to: lastBoxPoint)
    }

    // MARK: - 批量动作（docs/09 D12/D16：收藏即时写；隐藏/删除入队；无 App 内删除确认）

    private var selectedIDs: [String] { selectionState.selected }

    @objc private func batchFavoriteTapped() { runBatch(.setFavorite(true)) }

    /// 隐藏：入队（零 PhotoKit 写）+ 清空选择（留在多选）+ Toast「已加入待隐藏 · 撤销」
    @objc private func batchHideTapped() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        let session = AppContainer.shared.reviewSession
        session.enqueueHides(ids: ids)
        selectionState.deselectAll()
        reloadSelectionBadges()
        updateSelectionCount()
        batchToast.show(icon: "eye.slash.fill",
                        text: "已加入待隐藏 · 撤销",
                        duration: settings.undoWindow,
                        allowUndo: true,
                        onUndo: {
            for id in ids { session.undoPending(id: id, kind: .hide) }
        },
                        onDismissFinished: nil)
    }

    /// 删除：入队 → SessionReviewView（「全部移到最近删除」= 一次批量提交 + 一次系统确认）
    @objc private func batchDeleteTapped() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        let session = AppContainer.shared.reviewSession
        session.enqueueDeletes(ids: ids)
        selectionState.deselectAll()
        reloadSelectionBadges()
        updateSelectionCount()
        let review = SessionReviewView(session: session,
                                       pipeline: pipeline,
                                       settings: settings) { [weak self] in
            self?.dismiss(animated: true)
            self?.exitSelectionMode()
        }
        let host = UIHostingController(rootView: review)
        host.view.backgroundColor = DSColor.bgPrimary
        present(host, animated: true)
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

    /// 批量分享（≤10 张原件；docs/09 D15：批量导出到文件为 P2，登记于已知问题）
    @objc private func batchShareTapped() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        guard ids.count <= 10 else {
            batchToast.show(icon: "info.circle",
                            text: "分享最多支持 10 张，当前已选 \(ids.count) 张",
                            duration: 2.5,
                            allowUndo: false,
                            onUndo: nil, onDismissFinished: nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var urls: [URL] = []
            for id in ids {
                if let url = try? await AppContainer.shared.photoWriter.requestInputURL(assetID: id) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else {
                self.batchToast.show(icon: "info.circle",
                                     text: "无法读取原件（iCloud 原件可能未下载）",
                                     duration: 2.5,
                                     allowUndo: false, onUndo: nil, onDismissFinished: nil)
                return
            }
            let share = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            self.present(share, animated: true)
        }
    }

    private func runBatch(_ action: LibraryViewModel.BatchAction) {
        guard !isBatchRunning, !selectedIDs.isEmpty else { return }
        isBatchRunning = true
        let ids = selectedIDs
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.viewModel.performBatch(action, ids: ids)
            self.isBatchRunning = false
            // docs/09 D12：批量操作后保留多选但清空选择；Toast 显示结果
            self.selectionState.deselectAll()
            self.reloadSelectionBadges()
            self.updateSelectionCount()
            self.batchToast.show(icon: "checkmark.circle.fill",
                                 text: outcome.message,
                                 duration: 3.5,
                                 allowUndo: true,
                                 onUndo: { [weak self] in
                Task { await self?.viewModel.undoLatest() }
            },
                                 onDismissFinished: nil)
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
        // 位置记忆恢复（docs/09 D08）：首次非空快照后按 assetID 恢复（找不到用 offsetRatio 回退）
        restorePositionIfNeeded()
        // 多选中：筛选/pending 变化 → 选中集合收敛到新 scope（docs/09 D11 §3）
        if isSelecting {
            let newScope = Set(currentItemsBySection.flatMap { $0.map(\.id) })
            selectionState.intersectScope(with: newScope)
            reloadSelectionBadges()
            updateSelectionCount()
        }
    }

    // MARK: - 位置记忆（docs/09 D08）

    /// 首个可见 item + 偏移比例 → 按查询键保存（滚动停止 0.5s / viewWillDisappear）
    private func savePositionIfNeeded() {
        guard positionStore.isEnabled, !isRestoringPosition,
              !currentSections.isEmpty, !currentItemsBySection.isEmpty else { return }
        guard let indexPath = collectionView.indexPathsForVisibleItems.min(),
              let section = currentSections[safe: indexPath.section],
              let item = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item] else { return }
        let scrollable = max(1, collectionView.contentSize.height - collectionView.bounds.height)
        let ratio = min(1, max(0, collectionView.contentOffset.y / scrollable))
        positionStore.save(LibraryPosition(assetID: item.id,
                                           sectionID: section.id,
                                           offsetRatio: ratio,
                                           savedAt: Date()),
                           queryKey: viewModel.query.key)
    }

    /// 快照首次非空后恢复（恢复过程 isRestoringPosition 防写回；docs/09 D08）
    private func restorePositionIfNeeded() {
        guard !didRestorePosition, !currentSections.isEmpty, !currentItemsBySection.isEmpty else { return }
        didRestorePosition = true
        guard let position = positionStore.load(queryKey: viewModel.query.key) else { return }

        func finishRestore() {
            isRestoringPosition = false
            batchToast.show(icon: "arrow.uturn.backward.circle.fill",
                            text: "已回到上次整理的位置",
                            duration: 3,
                            allowUndo: false,
                            onUndo: nil,
                            onDismissFinished: nil)
        }

        // 首选：按 assetID 精确定位
        for (sectionIndex, items) in currentItemsBySection.enumerated() {
            if let itemIndex = items.firstIndex(where: { $0.id == position.assetID }) {
                isRestoringPosition = true
                collectionView.layoutIfNeeded()
                collectionView.scrollToItem(at: IndexPath(item: itemIndex, section: sectionIndex),
                                            at: .centeredVertically, animated: false)
                finishRestore()
                return
            }
        }
        // 回退：按偏移比例
        isRestoringPosition = true
        collectionView.layoutIfNeeded()
        let scrollable = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        collectionView.setContentOffset(CGPoint(x: 0, y: position.offsetRatio * scrollable), animated: false)
        finishRestore()
    }

    private func scrollToSection(_ index: Int) {
        guard index < currentSections.count else { return }
        collectionView.scrollToItem(at: IndexPath(item: 0, section: index),
                                    at: .top,
                                    animated: false)
    }

    // MARK: - 列数切换（docs/09 D14：设置 Stepper 与捏合手势统一入口；锚点保持）

    func setColumns(_ newColumns: Int, animated: Bool = false, anchor: IndexPath? = nil) {
        let clamped = max(2, min(5, newColumns))
        guard clamped != columns else { return }
        columns = clamped
        let finish = { [weak self] in
            guard let self else { return }
            // 列宽变化 → cell 内取图尺寸变化 → 重载可视 cell（缓存键含尺寸）
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
            if let anchor, anchor.section < self.currentSections.count {
                self.collectionView.scrollToItem(at: anchor, at: .centeredVertically, animated: false)
            }
        }
        if animated && usesMotion {
            collectionView.setCollectionViewLayout(makeLayout(columns: clamped), animated: true) { _ in
                finish()
            }
        } else {
            collectionView.collectionViewLayout = makeLayout(columns: clamped)
            finish()
        }
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

// MARK: - Delegate（预取）

extension LibraryViewController: UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isSelecting {
            // 多选模式：点选 = 勾选/取消
            if let item = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item] {
                toggleSelection(id: item.id)
            }
            return
        }
        // ViewerContext：当前筛选结果 + 被点条目（assetID 定位，docs/09 D01）
        guard let item = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item] else { return }
        onOpenViewer?(item)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 位置记忆：滚动停止 0.5 秒后保存首个可见 assetID（docs/09 D08）
        guard !isRestoringPosition else { return }
        positionSaveTimer?.invalidate()
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.savePositionIfNeeded()
            }
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
        // docs/09 Phase 1：索引自后台补齐，此处无需兜底分页
    }

    func collectionView(_ collectionView: UICollectionView,
                        didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? PhotoGridCell)?.cancelLoad()
    }
}

// MARK: - 手势代理（捏合与滚动同时识别，docs/09 D14）

extension LibraryViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // 双指捏合（2 touches）与单指滚动 pan 互不阻塞
        true
    }
}

// MARK: - 月份粘性分组头（docs/09 D15：标题 + 「选择」按钮 → 该月批量选择）

final class MonthHeaderView: UICollectionReusableView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.sectionHeader)
        // 动态 UIColor 直接赋值即可随深浅色切换
        label.textColor = DSColor.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("选择", for: .normal)
        button.titleLabel?.font = DSTypography.font(.body)
        button.tintColor = DSColor.tint
        button.accessibilityLabel = "选择本月"
        return button
    }()
    /// 月份头「选择」回调（VC 在 configure 时注入）
    var onSelect: (() -> Void)? {
        get { selectAction }
        set { selectAction = newValue }
    }
    private var selectAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DSColor.bgPrimary
        addSubview(titleLabel)
        addSubview(selectButton)
        selectButton.addAction(UIAction { [weak self] _ in
            self?.selectAction?()
        }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DSSpacing.screenPadding),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            selectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DSSpacing.screenPadding),
            selectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
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
