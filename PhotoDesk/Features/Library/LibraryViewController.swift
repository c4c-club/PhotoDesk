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
    /// 单月 scope 的展示标题（计数「已选择 N 项 · 本月」用，docs/13 S10）
    private var selectionScopeTitle: String?
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
    /// 底部 Toast 约束（多选时上移到 selectionBar 之上，docs/13 S05）
    private var toastBottomConstraint: NSLayoutConstraint?
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
    /// 框选进行中（移动超过 4pt 后进入；此时滚动禁用）
    private var isBoxSelecting = false
    private var lastBoxPoint: CGPoint = .zero
    private var boxAutoScrollLink: CADisplayLink?
    /// 范围选择锚点（docs/13 S07）：.began 时记录 anchor id 与初始选中集
    private var boxAnchorID: String?
    private var boxBaseSelected: [String] = []
    private var boxDidMove = false

    // MARK: - 快照缓存

    private var currentSections: [MonthSection] = []
    private var currentItemsBySection: [[PhotoItem]] = []
    /// 快照协调器（docs/13 §3.4 S03）：同一时间只允许一个 dataSource.apply；
    /// 新快照到来时覆盖 pending，completion 后排空
    private var pendingSnapshot: LibrarySnapshot?
    private var isApplyingSnapshot = false
    /// 当前已提交快照对应的查询键（位置记忆 v2 保存用，docs/13 S04）
    private var currentSnapshotQueryKey: String?
    /// 上一次布局时配置 cell 所用的像素尺寸（变化时重配可视 cell）
    private var lastConfiguredPixelSize: CGSize = .zero
    /// 网格点击 → 打开全屏浏览器（ViewerContext：当前筛选结果 + 被点条目，docs/09 D01）
    var onOpenViewer: ((PhotoItem) -> Void)?
    /// 多选操作行「筛选」→ 打开筛选面板（docs/13 S06）
    var onOpenFilter: (() -> Void)?

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

        // 位置记忆：切后台/失活立即保存（docs/13 S04 修复 3——杀进程前最后一道保存）
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.savePositionNow(reason: "resignActive")
            }
        }

        // 月份跳转横幅（docs/13 S11）
        view.addSubview(jumpBanner)
        NSLayoutConstraint.activate([
            jumpBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            jumpBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DSSpacing.screenPadding),
            jumpBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DSSpacing.screenPadding),
            jumpBanner.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 切 Tab / 进设置 / 返回前强制保存位置（docs/09 D08；docs/13 S04 v2）
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
        savePositionNow(reason: "disappear")
    }

    deinit {
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        // docs/13 S05：首次捏合提示改顶部细横幅（不占底部、不拦截触摸）
        showTopBanner(text: "双指捏合可调整列数", duration: 2.5)
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
            header.configure(title: section.headerTitle, sectionID: section.id, count: section.count)
            // docs/13 S10：标题点击 = 跳到本月；⋯ 菜单 =「选择本月全部」/「跳到本月」
            header.onJumpToMonth = { [weak self] in
                self?.scrollToSection(indexPath.section)
            }
            header.onSelectAllMonth = { [weak self] in
                self?.enterSelectionMode(section: indexPath.section, selectAll: true)
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
        view.addSubview(batchToast)
        let bottomConstraint = batchToast.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -DSSpacing.toastBottomOffset)
        toastBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            batchToast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DSSpacing.screenPadding),
            batchToast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DSSpacing.screenPadding),
            bottomConstraint,
        ])
    }

    /// Toast 底部位置随多选工具栏上移（docs/13 S05：多选时 bottom = -(84+12)，退出恢复）
    private func updateToastPosition() {
        toastBottomConstraint?.constant = isSelecting ? -(84 + 12) : -DSSpacing.toastBottomOffset
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

        // 第二行：横向滚动操作按钮（docs/09 D12：避免 11 item 溢出；docs/13 S06：筛选在全选左侧）
        let filterButton = barButton(symbol: "line.3.horizontal.decrease.circle", label: "筛选",
                                     identifier: "Batch-Filter", action: nil)
        filterButton.addAction(UIAction { [weak self] _ in
            self?.onOpenFilter?()
        }, for: .touchUpInside)
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
        let actionStack = UIStackView(arrangedSubviews: [filterButton, selectAllButton, favoriteButton,
                                                         hideButton, deleteButton, albumButton, moreButton])
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

        // S07：单个长按手势驱动「进入多选 + 拖拽范围选择」。
        // 0.15s / 不限移动距离（旧版 0.28s + 10pt：自然拖动就失败 → 变滚动，用户感知「不能滑动选择」）
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onBoxLongPress(_:)))
        longPress.minimumPressDuration = 0.15
        longPress.allowableMovement = .greatestFiniteMagnitude
        longPress.delaysTouchesBegan = false
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
        updateToastPosition()   // docs/13 S05：Toast 上移到 selectionBar 之上
        showSlideSelectHintOnce()
    }

    /// S07 提示：首次进入多选提示「按住滑动可连续选择」（顶部横幅 2s）
    private func showSlideSelectHintOnce() {
        let key = "library.slideSelectHintShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showTopBanner(text: "按住照片滑动可连续选择", duration: 2)
    }

    /// 月份头/月份面板「选择本月全部」（docs/13 S10）：scope = 该月 items + scopeID = "month:<id>"；
    /// selectAll = true 时立即全选该月
    private func enterSelectionMode(section: Int, selectAll: Bool) {
        guard !isSelecting else { return }
        guard section < currentSections.count else { return }
        let monthItems = currentItemsBySection[safe: section] ?? []
        guard !monthItems.isEmpty else { return }
        isSelecting = true
        let scope = Set(monthItems.map(\.id))
        let sectionID = currentSections[section].id
        selectionState.begin(scope: scope, initial: nil, scopeID: "month:\(sectionID)")
        selectionScopeTitle = currentSections[section].title
        selectionBar.isHidden = false
        indexBar.isHidden = true
        if selectAll {
            selectionState.selectAll()
        }
        reloadSelectionBadges()
        updateSelectionCount()
        updateToastPosition()   // docs/13 S05：Toast 上移到 selectionBar 之上
    }

    /// 月份头「选择本月全部」对外入口（MonthJumpSheet 也走这里）
    func enterMonthSelection(sectionIndex: Int) {
        enterSelectionMode(section: sectionIndex, selectAll: true)
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectionState = SelectionState()
        selectionScopeTitle = nil
        selectionBar.isHidden = true
        indexBar.isHidden = false
        reloadSelectionBadges()
        updateSelectionCount()
        updateToastPosition()   // docs/13 S05：退出多选恢复 Toast 常规位置
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
        // S10：单月 scope 显示「· 本月」范围说明
        let suffix = selectionState.isMonthScope ? " · 本月" : ""
        selectionCountLabel.text = "已选择 \(selectionState.selected.count) 项\(suffix)"
        selectionCountLabel.accessibilityLabel = "已选择 \(selectionState.selected.count) 项\(suffix)"
    }

    private func reloadSelectionBadges() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell else { continue }
            cell.setSelectionVisible(isSelecting)
            // docs/13 §3.7：经 dataSource 取 item（不用数组下标——apply 窗口内两套数据可能错位）
            let item = dataSource.itemIdentifier(for: indexPath)
            cell.setSelected(item.map { selectionState.selectedSet.contains($0.id) } ?? false)
        }
    }

    /// 全选/取消全选切换（docs/09 D11 + docs/13 S10）
    @objc private func selectAllTapped() {
        // S10：单月 scope 只在月内全选/取消，不得扩到全库
        if selectionState.isMonthScope {
            if selectionState.allSelected {
                selectionState.deselectAll()
            } else {
                selectionState.selectAll()
            }
            reloadSelectionBadges()
            updateSelectionCount()
            return
        }
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

    // MARK: - 范围选择（docs/13 S07：长按 0.15s 进入，拖动连续选中 anchor→target，边缘自动滚动）

    @objc private func onBoxLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let point = gesture.location(in: collectionView)
            if !isSelecting {
                guard let indexPath = collectionView.indexPathForItem(at: point),
                      let item = dataSource.itemIdentifier(for: indexPath) else { return }
                enterSelectionMode(selecting: item.id)
            }
            boxStartPoint = point
            lastBoxPoint = point
            boxDidMove = false
            // 记录锚点与初始选中集：拖动过程中 replaceSelection(base ∪ range)
            boxAnchorID = collectionView.indexPathForItem(at: point)
                .flatMap { dataSource.itemIdentifier(for: $0)?.id }
            boxBaseSelected = selectionState.selected

        case .changed:
            guard let start = boxStartPoint else { return }
            let location = gesture.location(in: collectionView)
            lastBoxPoint = location
            boxDidMove = true
            if !isBoxSelecting {
                let distance = hypot(location.x - start.x, location.y - start.y)
                guard distance > 4 else { return }   // 4pt 抖动阈值（docs/13 S07）
                isBoxSelecting = true
                collectionView.isScrollEnabled = false   // 此刻才禁用滚动
                selectionOverlay.isHidden = false
                startBoxAutoScroll()
            }
            updateBoxSelection(from: start, to: location)

        case .ended, .cancelled, .failed:
            boxStartPoint = nil
            boxAnchorID = nil
            boxBaseSelected = []
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
        // 视觉反馈矩形
        let rect = CGRect(x: min(start.x, location.x),
                          y: min(start.y, location.y),
                          width: abs(start.x - location.x),
                          height: abs(start.y - location.y))
        selectionOverlay.frame = rect
        // S07：范围选择——anchor→target 的连续 id（SelectionRange 纯逻辑），replaceSelection(base ∪ range)
        guard let anchor = boxAnchorID else { return }
        let targetPath = collectionView.indexPathForItem(at: location) ?? nearestIndexPath(to: location)
        guard let target = targetPath.flatMap({ dataSource.itemIdentifier(for: $0)?.id }) else { return }
        let orderedIDs = currentItemsBySection.flatMap { $0.map(\.id) }
        let range = SelectionRange.ids(in: orderedIDs, from: anchor, to: target)
        guard !range.isEmpty else { return }
        selectionState.replaceSelection(boxBaseSelected + range)
        reloadSelectionBadges()
        updateSelectionCount()
    }

    /// 手指拖出网格边缘/未落在 cell 上时取最近 cell（docs/13 S07）
    private func nearestIndexPath(to point: CGPoint) -> IndexPath? {
        let clampedX = min(max(point.x, 0), max(0, collectionView.contentSize.width - 1))
        let clampedY = min(max(point.y, 0), max(0, collectionView.contentSize.height - 1))
        return collectionView.indexPathForItem(at: CGPoint(x: clampedX, y: clampedY))
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
        viewModel.attachSnapshotHandler { [weak self] snapshot in
            self?.applySnapshot(snapshot)
        }
    }

    // MARK: - 快照协调器（docs/13 §3.4：apply completion 是唯一更新派生状态的时机）

    private func applySnapshot(_ snapshot: LibrarySnapshot) {
        pendingSnapshot = snapshot
        guard !isApplyingSnapshot else { return }
        drainPendingSnapshot()
    }

    private func drainPendingSnapshot() {
        guard let pending = pendingSnapshot else { return }
        pendingSnapshot = nil
        isApplyingSnapshot = true
        indexBar.isUserInteractionEnabled = false   // S03：apply 期间禁用索引条（防越界 scrollToItem）

        var diffable = NSDiffableDataSourceSnapshot<MonthSection, PhotoItem>()
        diffable.appendSections(pending.sections)
        for (section, items) in zip(pending.sections, pending.itemsBySection) {
            diffable.appendItems(items, toSection: section)
        }
        // 筛选/年份切换一律无动画；增量且不在滚动/多选时才动画（docs/13 §3.4）
        let shouldAnimate = pending.animated && usesMotion && !isSelecting
            && !collectionView.isTracking && !collectionView.isDecelerating
        dataSource.apply(diffable, animatingDifferences: shouldAnimate) { [weak self] in
            guard let self else { return }
            self.currentSections = pending.sections
            self.currentItemsBySection = pending.itemsBySection
            self.currentSnapshotQueryKey = pending.queryKey
            self.isApplyingSnapshot = false
            self.indexBar.isUserInteractionEnabled = true
            self.syncIndexBar()
            // 位置记忆恢复（docs/09 D08；Phase 5 重写为 v2 策略）
            self.restorePositionIfNeeded()
            // 多选中：筛选/pending 变化 → 选中集合收敛到新 scope（docs/09 D11 §3）
            if self.isSelecting {
                let newScope = Set(self.currentItemsBySection.flatMap { $0.map(\.id) })
                self.selectionState.intersectScope(with: newScope)
                self.reloadSelectionBadges()
                self.updateSelectionCount()
            }
            self.drainPendingSnapshot()   // apply 期间又来了新快照 → 排空
        }
    }

    // MARK: - 位置记忆 v2（docs/13 §3.5 S04/S11）

    /// 恢复中的位置（assetID 找不到且索引未完成时保持 pending，等下一批）
    private var pendingRestorePosition: LibraryPosition?
    /// 上次已尝试恢复的查询键（query 变化时重置恢复状态）
    private var lastRestoredQueryKey: String?
    private var resignActiveObserver: NSObjectProtocol?

    /// 统一保存入口：所有触发点都走这里（滚动停止 / 拖拽结束 / 消失 / 后台 / 跳转完成）
    /// 保存用 currentSnapshotQueryKey（快照时的 key），不用 viewModel.query.key（S04 根因 3）
    func savePositionNow(reason: String) {
        guard positionStore.isEnabled, !isRestoringPosition,
              let queryKey = currentSnapshotQueryKey,
              !currentSections.isEmpty, !currentItemsBySection.isEmpty else { return }
        guard let indexPath = collectionView.indexPathsForVisibleItems.sorted().first,
              indexPath.section < currentSections.count,
              let section = currentSections[safe: indexPath.section],
              let item = currentItemsBySection[safe: indexPath.section]?[safe: indexPath.item] else { return }
        let scrollable = max(1, collectionView.contentSize.height - collectionView.bounds.height)
        let ratio = min(1, max(0, collectionView.contentOffset.y / scrollable))
        positionStore.save(LibraryPosition(assetID: item.id,
                                           sectionID: section.id,
                                           itemIndexInSection: indexPath.item,
                                           offsetRatio: ratio,
                                           savedAt: Date()),
                           queryKey: queryKey)
        ViewerTrace.log("position.save \(reason) section=\(section.id) idx=\(indexPath.item)")
    }

    /// 每次 apply completion 后尝试恢复；策略：assetID → sectionID + itemIndexInSection → offsetRatio。
    /// 索引未完成且 assetID 找不到 → 保持 pending 等下一批（不提前放弃，S04 根因 1）。
    private func restorePositionIfNeeded() {
        // query 变化 → 重新加载该查询键的位置
        if lastRestoredQueryKey != currentSnapshotQueryKey {
            lastRestoredQueryKey = currentSnapshotQueryKey
            pendingRestorePosition = nil
            didRestorePosition = false
        }
        if !didRestorePosition {
            guard !currentSections.isEmpty, !currentItemsBySection.isEmpty else { return }
            didRestorePosition = true   // load 已尝试；找不到 asset 时由 pending 续等
            pendingRestorePosition = positionStore.load(queryKey: currentSnapshotQueryKey ?? viewModel.query.key)
        }
        guard let position = pendingRestorePosition else { return }
        guard !currentSections.isEmpty, !currentItemsBySection.isEmpty else { return }

        // 策略 1：assetID 精确定位
        for (sectionIndex, items) in currentItemsBySection.enumerated() {
            if let itemIndex = items.firstIndex(where: { $0.id == position.assetID }) {
                applyRestore(sectionIndex: sectionIndex, itemIndex: itemIndex, position: position, by: "asset")
                return
            }
        }
        // 索引未完成 → 等下一批快照再试（不标记完成）
        guard viewModel.isIndexComplete else {
            viewModel.debugRestoreNote = "restore=pending"
            return
        }
        // 策略 2：sectionID + itemIndexInSection（钳制）
        if let sectionIndex = currentSections.firstIndex(where: { $0.id == position.sectionID }) {
            let itemCount = currentItemsBySection[safe: sectionIndex]?.count ?? 0
            if itemCount > 0 {
                let itemIndex = min(max(0, position.itemIndexInSection), itemCount - 1)
                applyRestore(sectionIndex: sectionIndex, itemIndex: itemIndex, position: position, by: "section")
                return
            }
        }
        // 策略 3：offsetRatio（此时 contentSize 已完整）
        applyRatioRestore(position)
    }

    private func applyRestore(sectionIndex: Int, itemIndex: Int, position: LibraryPosition, by strategy: String) {
        pendingRestorePosition = nil
        isRestoringPosition = true
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: IndexPath(item: itemIndex, section: sectionIndex),
                                    at: .centeredVertically, animated: false)
        isRestoringPosition = false
        viewModel.debugRestoreNote = "restore=ok section=\(position.sectionID) by=\(strategy)"
        ViewerTrace.log("position.restore ok section=\(position.sectionID) idx=\(itemIndex) by=\(strategy)")
    }

    private func applyRatioRestore(_ position: LibraryPosition) {
        pendingRestorePosition = nil
        isRestoringPosition = true
        collectionView.layoutIfNeeded()
        let scrollable = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        collectionView.setContentOffset(CGPoint(x: 0, y: position.offsetRatio * scrollable), animated: false)
        isRestoringPosition = false
        viewModel.debugRestoreNote = "restore=ratio section=\(position.sectionID)"
        ViewerTrace.log("position.restore ratio section=\(position.sectionID)")
    }

    /// 月份/索引条跳转（docs/13 S09/S11）：校验 → 滚动 → 抵消粘性 header → 同步保存 → 顶部细横幅
    /// - Returns: 是否实际执行了滚动（false = 校验未通过/快照未提交，调用方可重试）
    @discardableResult
    func scrollToSection(_ index: Int) -> Bool {
        // S03 修复：校验 collectionView 实际 section/item 数（apply 未提交时 currentSections 已是新值）
        guard index < currentSections.count,
              index < collectionView.numberOfSections,
              collectionView.numberOfItems(inSection: index) > 0 else { return false }
        isRestoringPosition = true
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: IndexPath(item: 0, section: index),
                                    at: .top,
                                    animated: false)
        // 抵消 48pt 粘性 header：scrollToItem(.top) 对齐的是第一个 cell，粘性头会盖住首行
        let targetY = max(0, collectionView.contentOffset.y - 48)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
        isRestoringPosition = false
        indexBar.setHighlighted(index: index, notify: false)
        // S11：跳转后立即同步保存（不依赖滚动回调/Timer——跳完立刻杀进程也要记住）
        if let section = currentSections[safe: index],
           let item = currentItemsBySection[safe: index]?.first, let queryKey = currentSnapshotQueryKey {
            positionStore.save(LibraryPosition(assetID: item.id,
                                               sectionID: section.id,
                                               itemIndexInSection: 0,
                                               offsetRatio: min(1, max(0, collectionView.contentOffset.y /
                                                                            max(1, collectionView.contentSize.height - collectionView.bounds.height))),
                                               savedAt: Date()),
                               queryKey: queryKey)
            ViewerTrace.log("position.save monthJump section=\(section.id)")
        }
        showJumpBanner(section: currentSections[index])
        return true
    }

    /// 月份面板「回到顶部」（docs/13 S09）
    func scrollToTop() {
        guard collectionView.numberOfSections > 0 else { return }
        isRestoringPosition = true
        collectionView.setContentOffset(.zero, animated: false)
        isRestoringPosition = false
        savePositionNow(reason: "scrollTop")
    }

    /// 跳转/提示共用顶部细横幅（不挡网格；generation 令牌防旧动画隐藏新横幅）
    private let jumpBanner: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.badge)
        label.textColor = DSColor.textPrimary
        label.backgroundColor = DSColor.bgSecondary
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.alpha = 0
        label.isHidden = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "Library-JumpBanner"
        return label
    }()
    private var jumpBannerGeneration = 0

    private func showTopBanner(text: String, duration: TimeInterval) {
        jumpBanner.text = text
        jumpBanner.isHidden = false
        jumpBannerGeneration += 1
        let generation = jumpBannerGeneration
        UIView.animate(withDuration: 0.15) {
            self.jumpBanner.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.jumpBannerGeneration else { return }
            UIView.animate(withDuration: 0.25, animations: {
                self.jumpBanner.alpha = 0
            }, completion: { _ in
                if generation == self.jumpBannerGeneration {
                    self.jumpBanner.isHidden = true
                }
            })
        }
    }

    /// 月份跳转横幅（docs/13 S11）
    private func showJumpBanner(section: MonthSection) {
        showTopBanner(text: "已跳到 \(section.title)", duration: 1.5)
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
                entries.append(MonthIndexBar.Entry(label: "?", detail: "未知日期"))
            } else if year != lastYear {
                entries.append(MonthIndexBar.Entry(label: year, detail: section.title))
                lastYear = year
            } else {
                entries.append(MonthIndexBar.Entry(label: nil, detail: section.title))
            }
        }
        indexBar.update(entries: entries, highlightedIndex: -1)
    }
}

// MARK: - Delegate（预取）

extension LibraryViewController: UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // docs/13 §3.7：一律经 dataSource 取 item（apply 窗口内数组下标不可信）
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        if isSelecting {
            // 多选模式：点选 = 勾选/取消
            toggleSelection(id: item.id)
            return
        }
        // ViewerContext：当前筛选结果 + 被点条目（assetID 定位，docs/09 D01）
        onOpenViewer?(item)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 位置记忆：滚动停止 0.3 秒兜底保存（docs/13 S04：0.5s → 0.3s）
        guard !isRestoringPosition else { return }
        positionSaveTimer?.invalidate()
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.savePositionNow(reason: "idle")
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        savePositionNow(reason: "decelerating")
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            savePositionNow(reason: "dragging")
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        // 经 dataSource 取 item（apply 窗口内 currentItemsBySection 可能尚未更新）
        let ids = indexPaths.compactMap { dataSource.itemIdentifier(for: $0)?.id }
        guard !ids.isEmpty else { return }
        let pixel = cellPixelSize
        pipeline.prefetch(ids: ids, size: CGSize(width: pixel.width, height: pixel.height))
    }

    func collectionView(_ collectionView: UICollectionView,
                        cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let ids = indexPaths.compactMap { dataSource.itemIdentifier(for: $0)?.id }
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

// MARK: - 月份粘性分组头（docs/13 S09/S10：标题点击跳转 + ⋯ 菜单「选择本月全部/跳到本月」）

final class MonthHeaderView: UICollectionReusableView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.sectionHeader)
        // 动态 UIColor 直接赋值即可随深浅色切换
        label.textColor = DSColor.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }()
    private let menuButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.tintColor = DSColor.tint
        button.accessibilityLabel = "本月操作"
        button.showsMenuAsPrimaryAction = true
        return button
    }()
    /// 标题点击 = 跳到本月
    var onJumpToMonth: (() -> Void)?
    /// 菜单「选择本月全部」
    var onSelectAllMonth: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DSColor.bgPrimary
        addSubview(titleLabel)
        addSubview(menuButton)
        // 标题点击 → 跳到本月（docs/13 S09）
        let titleTap = UITapGestureRecognizer(target: self, action: #selector(titleTapped))
        titleLabel.addGestureRecognizer(titleTap)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DSSpacing.screenPadding),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),

            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DSSpacing.screenPadding),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    @objc private func titleTapped() {
        onJumpToMonth?()
    }

    func configure(title: String, sectionID: String, count: Int) {
        titleLabel.text = title
        menuButton.menu = UIMenu(children: [
            UIAction(title: "选择本月全部", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.onSelectAllMonth?()
            },
            UIAction(title: "跳到本月", image: UIImage(systemName: "arrow.down.right")) { [weak self] _ in
                self?.onJumpToMonth?()
            },
        ])
        // docs/13 S10：菜单按钮带 sectionID（UI 测试锚点）；标题 AX 值带 id/count
        menuButton.accessibilityIdentifier = "MonthHeader-Menu-\(sectionID)"
        titleLabel.accessibilityValue = "id=\(sectionID) count=\(count)"
    }
}

// MARK: - 安全取值


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
