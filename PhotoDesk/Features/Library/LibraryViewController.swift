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
    /// 底部 Toast 约束（R04：约束引用切换——safeArea / selectionBar 顶部二选一）
    private var toastSafeAreaConstraint: NSLayoutConstraint?
    private var toastAboveSelectionConstraint: NSLayoutConstraint?
    /// M13 P3：单指滑选编排器（Core 纯策略 + UIKit 映射；长按二维框选整条移除）。
    private var slideSelectController: SlideSelectGestureController?
    private var slideSelectPan: UIPanGestureRecognizer?
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
    /// 月跳落地复核：待核对的目标月（viewDidLayoutSubviews 按真实钉住线核对，未钉住再校正）
    private var pendingJumpVerifySectionID: String?
    /// 月跳待存标记：落地点是估算布局，等 verifyJumpLanding 收敛后按真实几何保存
    private var pendingJumpSave = false
    private var jumpVerifyAttempts = 0

    /// v5 前插补偿（docs/25 §5.7）：只记录锚点 assetID + 视觉 y；apply completion 登记一次补偿，
    /// 布局 pass 按真实 minY 收敛（≤0.5pt），无 3 次上限；用户拖动/减速/恢复中立即让位。
    private struct HeadInsertAnchor {
        let assetID: String
        let visualY: CGFloat
    }
    private var pendingHeadInsertAnchor: HeadInsertAnchor?
    /// 减速静止补存（拖动结束且将减速时安排 +1.5s 重新抓快照保存）
    private var restSaveWorkItem: DispatchWorkItem?
    /// 网格点击 → 打开全屏浏览器（ViewerContext：当前筛选结果 + 被点条目，docs/09 D01）
    var onOpenViewer: ((PhotoItem) -> Void)?
    /// 多选操作行「筛选」→ 打开筛选面板（docs/13 S06）
    var onOpenFilter: (() -> Void)?
    /// M12 R05/R06/R07：唯一顶部栏回调（顶部按钮全部由 UIKit navigationItem 承载）
    var onOpenSearch: (() -> Void)?
    var onOpenMonthJump: (() -> Void)?
    var onOpenTools: (() -> Void)?
    var onShowVault: (() -> Void)?

    // MARK: - 下拉刷新（docs/09 D15）

    private let refreshControl = UIRefreshControl()

    // MARK: - 位置记忆（docs/09 D08）

    private var isRestoringPosition = false
    /// v4：唯一 save/restore 入口（docs/22 §4.4.3）
    private lazy var positionCoordinator = LibraryPositionCoordinator(store: positionStore)
    private var restoreMaskGeneration = 0
    /// v4：恢复遮罩（0.15s 后才淡入；done/failed/timeout 淡出，绝不永久遮挡）
    private let restoreMaskView: UIView = {
        let view = UIView()
        view.backgroundColor = DSColor.bgPrimary
        view.isUserInteractionEnabled = false
        view.alpha = 0
        view.isAccessibilityElement = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "Library-RestoreMask"
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }()

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
        setupNavigationItems()
        wireViewModel()
        // UI 测试钩子：-uiTestingSelectMode 启动即进入多选（绕开长按/工具栏按钮在 XCUITest 中的不可靠性）
        if ProcessInfo.processInfo.arguments.contains("-uiTestingSelectMode") {
            enterSelectionMode(selecting: nil)
        }
        #if DEBUG
        // UI 测试钩子：-uiTestingFilterYear（docs/13 M11）——viewDidLoad 先行设置 query.filter
        //（单一事实来源），首屏/补齐的所有 rebuildDerived 都会尊重它；与用户面板应用同一条 setFilter 路径。
        // 放 UIKit 侧（-uiTestingSelectMode 同款位置）：SwiftUI onChange 钩子在 CI 实测不可靠（轮 13–15）
        applyDebugFilterHookIfNeeded()
        applyDebugMonthJumpHookIfNeeded()
        #endif

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
                guard let self else { return }
                self.positionCoordinator.saveNow(reason: "resignActive",
                                                 snapshot: self.makePositionSnapshot())
            }
        }

        // v4：恢复阶段 → 遮罩/调试状态；几何写入仍由 attemptPositionRestore 负责。
        positionCoordinator.onPhaseChange = { [weak self] phase in
            self?.handlePositionPhase(phase)
        }

        // R03：恢复遮罩盖住网格（锚点定位完成才移除——用户看不到「先在别处、再滚过去」）
        view.addSubview(restoreMaskView)
        NSLayoutConstraint.activate([
            restoreMaskView.topAnchor.constraint(equalTo: view.topAnchor),
            restoreMaskView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            restoreMaskView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            restoreMaskView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

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
        // docs/25 §5.6：只在真正离开页面（被移除/被 dismiss）时保存；
        // 打开查看器 / 弹 sheet 不保存，避免临态覆盖已保存锚点。
        if isMovingFromParent || isBeingDismissed {
            positionCoordinator.saveNow(reason: "disappear", snapshot: makePositionSnapshot())
        }
    }

    deinit {
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 旋转 / 分屏（docs/09 Phase 7）：布局随尺寸更新，保持当前锚点不跳
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // 旋转前抓同一锚点，布局完成后按新几何复位（docs/22 Phase 4 网格验收）
        let preRotation = makePositionSnapshot()
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.collectionView.collectionViewLayout = self.makeLayout(columns: self.columns)
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }, completion: { [weak self] _ in
            guard let self, let preRotation else { return }
            self.pendingHeadInsertAnchor = HeadInsertAnchor(assetID: preRotation.anchorAssetID,
                                                            visualY: CGFloat(preRotation.anchorVisualY))
            self.collectionView.layoutIfNeeded()
            self.enforceHeadInsertAnchor()
        })
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
            // M13 绿5 实锤：首屏粘性头 AX 恒空的历史根因——本 provider 在 apply 期间被调，
            // 旧实现读 completion 才赋值的 currentSections → 首次配置时数组仍为空 → 标题空。
            // 改读 dataSource 已提交快照的 sectionIdentifier：任何时刻都拿到正确分组。
            guard let self,
                  let section = self.dataSource.sectionIdentifier(for: indexPath.section) else { return }
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
        // docs/16 M12 R04：约束引用切换（activate/deactivate），删除 -(84+12) 魔法数——
        // 常规贴 safeArea 底部；多选时贴 selectionBar 顶部（间距同 token）
        let safeAreaConstraint = batchToast.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -DSSpacing.toastBottomOffset)
        let aboveSelectionConstraint = batchToast.bottomAnchor.constraint(
            equalTo: selectionBar.topAnchor,
            constant: -DSSpacing.toastBottomOffset)
        toastSafeAreaConstraint = safeAreaConstraint
        toastAboveSelectionConstraint = aboveSelectionConstraint
        NSLayoutConstraint.activate([
            batchToast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DSSpacing.screenPadding),
            batchToast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DSSpacing.screenPadding),
            safeAreaConstraint,
        ])
    }

    /// R04：Toast 底部位置约束引用切换（多选 = selectionBar.topAnchor；常规 = safeArea 底部）
    private func updateToastPosition() {
        guard let safeAreaConstraint = toastSafeAreaConstraint,
              let aboveSelectionConstraint = toastAboveSelectionConstraint else { return }
        if isSelecting {
            safeAreaConstraint.isActive = false
            aboveSelectionConstraint.isActive = true
        } else {
            aboveSelectionConstraint.isActive = false
            safeAreaConstraint.isActive = true
        }
        view.layoutIfNeeded()
    }

    // MARK: - 唯一顶部栏（docs/16 M12 §3：R05 无标题 + R06 分类菜单 + R07 工具左上）
    // 为什么用 UIKit UINavigationItem：iOS 15.5 + Xcode 15.4 下 SwiftUI Toolbar/Menu 按钮的
    // XCUITest 合成点击与坐标点击均不可靠（docs/15 §3.2 六条 🟨 成因）；UIBarButtonItem /
    // showsMenuAsPrimaryAction UIButton 为 UIKit 宿主，点击可靠。

    private var sessionBadgeItem: UIBarButtonItem?
    private weak var categoryMenuButton: UIButton?
    /// 其他 scope 的异步计数缓存（R06：不切换 results，只读 count(scope:)）
    private var categoryCounts: [PhotoScope: Int] = [:]
    #if DEBUG
    /// UI 测试钩子一次性守卫
    private var debugChromeHookDone = false
    #endif

    private func setupNavigationItems() {
        navigationItem.title = nil                       // R05：顶部无 App 标题
        navigationItem.largeTitleDisplayMode = .never
        let iconConfig = UIImage.SymbolConfiguration(textStyle: .body)

        // 左上：工具（R07；点开 ToolsView sheet）
        let tools = UIBarButtonItem(image: UIImage(systemName: "wrench.and.screwdriver",
                                                   withConfiguration: iconConfig),
                                    style: .plain, target: self, action: #selector(toolsTapped))
        tools.accessibilityIdentifier = "Library-Tools"
        tools.accessibilityLabel = "工具"
        navigationItem.leftBarButtonItem = tools

        // 右上（UIKit 反序装配：数组首元素显示在最右）：
        // [SessionBadge] [多选] [搜索] [月份] [筛选] [分类]
        // 常驻图标：0 待处理时也可点开整理回顾（空标题 UIBarButtonItem 零宽，
        // XCUITest 坐标点击会落空——验证轮 9 实测）
        let session = UIBarButtonItem(image: UIImage(systemName: "tray"),
                                      style: .plain, target: self,
                                      action: #selector(sessionBadgeTapped))
        session.accessibilityIdentifier = "SessionBadge"
        session.accessibilityLabel = "整理回顾"
        let select = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle",
                                                    withConfiguration: iconConfig),
                                     style: .plain, target: self, action: #selector(selectTapped))
        select.accessibilityIdentifier = "Library-Select"
        select.accessibilityLabel = "多选"
        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass",
                                                    withConfiguration: iconConfig),
                                     style: .plain, target: self, action: #selector(searchTapped))
        search.accessibilityIdentifier = "Library-Search"
        search.accessibilityLabel = "搜索与筛选"
        let month = UIBarButtonItem(image: UIImage(systemName: "calendar",
                                                   withConfiguration: iconConfig),
                                    style: .plain, target: self, action: #selector(monthJumpTapped))
        month.accessibilityIdentifier = "Library-MonthJump"
        month.accessibilityLabel = "按月份跳转"
        let filter = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle",
                                                    withConfiguration: iconConfig),
                                     style: .plain, target: self, action: #selector(filterTapped))
        filter.accessibilityIdentifier = "Library-Filter"
        filter.accessibilityLabel = "筛选"

        // 分类菜单按钮（R06）：UIButton + showsMenuAsPrimaryAction（iOS 15 可用）
        let categoryButton = UIButton(type: .system)
        categoryButton.setTitle("分类", for: .normal)
        categoryButton.setTitleColor(DSColor.tint, for: .normal)
        categoryButton.titleLabel?.font = DSTypography.font(.body)
        categoryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        categoryButton.showsMenuAsPrimaryAction = true
        categoryButton.accessibilityIdentifier = "Library-Category"
        categoryButton.accessibilityLabel = "分类"
        categoryButton.menu = makeCategoryMenu()
        let category = UIBarButtonItem(customView: categoryButton)
        self.categoryMenuButton = categoryButton
        self.sessionBadgeItem = session

        navigationItem.rightBarButtonItems = [session, select, search, month, filter, category]
        refreshSessionBadge()
        refreshCategoryCountsAsync()
    }

    /// 分类菜单（R06）：5 项全保留 + .limited 管理入口；勾选由 query.scope 派生
    private func makeCategoryMenu() -> UIMenu {
        let items = LibraryCategoryMenuBuilder.items(currentScope: viewModel.query.scope,
                                                     isLimitedAccess: viewModel.isLimitedAccess,
                                                     counts: categoryCounts,
                                                     currentCount: viewModel.filteredItems.count)
        let actions = items.map { item in
            let action = UIAction(title: item.displayTitle,
                                  state: item.isSelected ? .on : .off) { [weak self] _ in
                self?.handleCategorySelection(item)
            }
            action.title = item.title
            action.discoverabilityTitle = item.displayTitle
            return action
        }
        return UIMenu(title: "", children: actions)
    }

    private func handleCategorySelection(_ item: CategoryMenuItem) {
        if item.isLimitedManagement {
            viewModel.requestManageLimitedPhotos()   // .limited：接上 DSEmptyState.limited 对应的系统选择器
            return
        }
        guard let scope = item.scope else {
            onShowVault?()   // 已隐藏：不 setScope，直接弹 Vault（Face ID / 受限提示全保留）
            return
        }
        Task { await viewModel.setScope(scope) }
    }

    /// 其他 scope 的异步计数（只读、不切换 results；快照变化后刷新缓存并重建菜单）。
    /// 在飞守卫：同一时刻只允许一轮（快照高频推送时防止后台 PhotoKit 查询堆积——验证轮 6/7
    /// 级联「网格无 cell」的可疑放大器之一）。
    private var isCountRefreshInFlight = false
    private func refreshCategoryCountsAsync() {
        guard !isCountRefreshInFlight else { return }
        isCountRefreshInFlight = true
        let scopes = LibraryCategoryMenuBuilder.scopeOrder
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCountRefreshInFlight = false }
            var counts: [PhotoScope: Int] = [:]
            for scope in scopes where scope != self.viewModel.query.scope {
                counts[scope] = await self.viewModel.count(scope: scope) ?? 0
            }
            self.categoryCounts = counts
            self.categoryMenuButton?.menu = self.makeCategoryMenu()
        }
    }

    /// 顶部待处理徽标（docs/09 D16 语义迁移到 UIBarButtonItem；计数入口不丢）
    private func refreshSessionBadge() {
        guard let item = sessionBadgeItem else { return }
        let session = AppContainer.shared.reviewSession
        let deletes = session.pendingDeleteCount
        let hides = session.pendingHideCount
        if deletes == 0 && hides == 0 {
            item.title = nil
            item.accessibilityLabel = "没有待处理内容"
        } else if hides == 0 {
            item.title = "待删除 \(deletes)"
            item.accessibilityLabel = "待删除 \(deletes) 张，点按查看整理回顾"
        } else if deletes == 0 {
            item.title = "待隐藏 \(hides)"
            item.accessibilityLabel = "待隐藏 \(hides) 张，点按查看整理回顾"
        } else {
            item.title = "待删除 \(deletes) · 待隐藏 \(hides)"
            item.accessibilityLabel = "待删除 \(deletes) 张，待隐藏 \(hides) 张，点按查看整理回顾"
        }
    }

    @objc private func toolsTapped() { onOpenTools?() }
    @objc private func searchTapped() { onOpenSearch?() }
    @objc private func monthJumpTapped() { onOpenMonthJump?() }
    @objc private func filterTapped() { onOpenFilter?() }
    @objc private func selectTapped() { toggleSelectionMode() }
    /// 整理回顾入口（徽标点按 / M13 DEBUG 钩子共用同一条路径，internal 供容器钩子调用）
    @objc func sessionBadgeTapped() {
        let review = SessionReviewView(session: AppContainer.shared.reviewSession,
                                       pipeline: pipeline,
                                       settings: settings) { [weak self] in
            self?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: review)
        host.view.backgroundColor = DSColor.bgPrimary
        present(host, animated: true)
    }

    #if DEBUG
    /// -uiTestingOpenSessionReview：查看器关闭回到网格后打开整理回顾（D16 语义不变，
    /// 只是绕开 XCUITest 对 UIToolbar 坐标点按的不可靠性；同一次会话只触发一次）。
    private var debugSessionReviewHookDone = false
    func attemptDebugOpenSessionReviewIfNeeded() {
        guard !debugSessionReviewHookDone,
              UITestHooks.enabled("-uiTestingOpenSessionReview"),
              AppContainer.shared.reviewSession.pendingDeleteCount > 0 else { return }
        debugSessionReviewHookDone = true
        ViewerTrace.log("hook openSessionReview pending=\(AppContainer.shared.reviewSession.pendingDeleteCount)")
        sessionBadgeTapped()
    }
    #endif

    #if DEBUG
    /// M12 UI 测试钩子接线（docs/16 §6.3）：网格就绪后触发（与 -uiTestingMonthJump 同位）。
    /// -uiTestingOpenTools：打开工具 sheet；-uiTestingSelectScope <all|favorites|videos|screenshots>：
    /// 走同一条 setScope 路径；-uiTestingOpenCategoryMenu：预取异步计数并重建菜单（UIKit 按钮点击可靠，
    /// 菜单断言直接 tap Library-Category）。
    private func attemptDebugChromeHooksIfNeeded() {
        guard !debugChromeHookDone, !currentSections.isEmpty else { return }
        debugChromeHookDone = true
        if UITestHooks.enabled("-uiTestingOpenTools") {
            ViewerTrace.log("hook openTools")
            onOpenTools?()
        }
        if let raw = UITestHooks.stringValue("-uiTestingSelectScope") {
            let scope: PhotoScope?
            switch raw {
            case "all":         scope = .all
            case "favorites":   scope = .favorites
            case "videos":      scope = .videos
            case "screenshots": scope = .screenshots
            default:            scope = nil
            }
            if let scope {
                ViewerTrace.log("hook selectScope \(raw)")
                Task { await self.viewModel.setScope(scope) }
            }
        }
        if UITestHooks.enabled("-uiTestingOpenCategoryMenu") {
            ViewerTrace.log("hook openCategoryMenu")
            refreshCategoryCountsAsync()
        }
    }
    #endif

    // MARK: - 多选模式（docs/09 D12：顶部取消/计数/完成；操作行可横滚；D13：长按拖拽框选）

    private func setupSelection() {
        selectionBar.translatesAutoresizingMaskIntoConstraints = false
        selectionBar.backgroundColor = DSColor.bgSecondary.withAlphaComponent(0.98)
        selectionBar.isHidden = true
        view.addSubview(selectionBar)

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

        // M13 P3 ①：单指滑选 pan；delegate 两方法在 UIGestureRecognizerDelegate 扩展内实现。
        let controller = SlideSelectGestureController(collectionView: collectionView)
        controller.attachDelegate(self)
        controller.isSelectionMode = { [weak self] in self?.isSelecting ?? false }
        controller.selectedIDsProvider = { [weak self] in self?.selectionState.selectedSet ?? [] }
        controller.itemIDProvider = { [weak self] indexPath in
            self?.dataSource.itemIdentifier(for: indexPath)?.id
        }
        controller.applyTargetIDs = { [weak self] ids in
            self?.applySlideSelection(ids: ids)
        }
        controller.scopeProvider = { [weak self] in self?.selectionState.scope }
        controller.geometryProvider = { [weak self] in
            self?.marqueeGeometry()
        }
        slideSelectController = controller
        slideSelectPan = controller.pan
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
        // 单指选择 / 双指滚动（docs/22 §5.5）：选择模式下 collectionView pan 至少两指。
        collectionView.panGestureRecognizer.minimumNumberOfTouches = 2
        reloadSelectionBadges()
        updateSelectionCount()
        updateToastPosition()   // docs/13 S05：Toast 上移到 selectionBar 之上
        refreshDebugScrollNote()
        showSlideSelectHintOnce()
    }

    /// S07 提示：首次进入多选提示「按住滑动可连续选择」（顶部横幅 2s）
    private func showSlideSelectHintOnce() {
        let key = "library.slideSelectHintShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showTopBanner(text: "在照片上拖动可框选；从已选照片起拖可取消；双指滚动", duration: 2)
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
        collectionView.panGestureRecognizer.minimumNumberOfTouches = 2
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
        slideSelectController?.finishSlideSelection()
        isSelecting = false
        selectionState = SelectionState()
        selectionScopeTitle = nil
        selectionBar.isHidden = true
        indexBar.isHidden = false
        collectionView.panGestureRecognizer.minimumNumberOfTouches = 1
        reloadSelectionBadges()
        updateSelectionCount()
        refreshDebugScrollNote()
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

    /// R08：差量刷新（拖选每帧只刷选中态变化的可见 cell——避免全量遍历掉帧）
    private func reloadSelectionBadges(previous: Set<String>) {
        let current = selectionState.selectedSet
        let added = current.subtracting(previous)
        let removed = previous.subtracting(current)
        guard !added.isEmpty || !removed.isEmpty else { return }
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell,
                  let item = dataSource.itemIdentifier(for: indexPath) else { continue }
            if added.contains(item.id) {
                cell.setSelectionVisible(true)
                cell.setSelected(true)
            } else if removed.contains(item.id) {
                cell.setSelected(false)
            }
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

    // MARK: - M13 P3 单指滑动连续多选（VC 只做映射，判定全在 SlideSelectPolicy）

    /// 把 Core 行带计算出的目标 id 集合整体落到 SelectionState；只 diff 可见 cell，计数仅变化时刷新。
    /// docs/25 §6.2：框选用网格几何（pt 单位）；sectionOriginY 取真实补充视图 minY，
    /// 远距离估算布局回退累计估算（header + rows × pitch）。
    private func marqueeGeometry() -> (metrics: GridMetrics, sectionOriginY: [Double])? {
        guard collectionView.bounds.width > 0, !currentItemsBySection.isEmpty else { return nil }
        let spacing = Double(DSSpacing.gridSpacing)
        let header = Double(DSSpacing.monthHeaderHeight)
        let width = Double(collectionView.bounds.width)
        let itemSide = (width - spacing * Double(max(1, columns - 1))) / Double(max(1, columns))
        guard itemSide.isFinite, itemSide > 0 else { return nil }
        let counts = (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        guard counts.count == currentItemsBySection.count, !counts.isEmpty else { return nil }
        let pitchY = itemSide + spacing
        var origins: [Double] = []
        var nextEstimate: Double = 0
        for section in 0..<counts.count {
            let rows = Int((Double(max(1, counts[section])) / Double(max(1, columns))).rounded(.up))
            if let attrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: section)) {
                origins.append(Double(attrs.frame.minY))
                nextEstimate = Double(attrs.frame.maxY) + Double(rows) * pitchY
            } else {
                origins.append(nextEstimate)
                nextEstimate += header + Double(rows) * pitchY
            }
        }
        let metrics = GridMetrics(columns: columns,
                                  itemWidth: itemSide,
                                  itemHeight: itemSide,
                                  interItemSpacing: spacing,
                                  sectionHeaderHeight: header,
                                  sectionItemCounts: counts)
        return (metrics, origins)
    }

    private func applySlideSelection(ids: Set<String>) {
        let previous = selectionState.selectedSet
        guard previous != ids else { return }
        selectionState.replaceSelection(Array(ids).sorted())
        let current = selectionState.selectedSet
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let item = dataSource.itemIdentifier(for: indexPath) else { continue }
            let wasSelected = previous.contains(item.id)
            let isSelectedNow = current.contains(item.id)
            guard wasSelected != isSelectedNow else { continue }
            guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell else { continue }
            cell.setSelectionVisible(isSelecting)
            cell.setSelected(isSelectedNow)
        }
        if previous.count != current.count {
            updateSelectionCount()
        }
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
        // M12（验证轮 15 实锤）：集合视图未完成初次布局（0 sections、零宽）时应用
        // 「空 → 多 section」快照，iOS 15 diffable 批更新以 NSInternalInconsistencyException
        //（「request for number of items in section 0 when there are only 0 sections」）崩溃。
        // 处置：保持 pending 不清空，推迟到 viewDidLayoutSubviews 布局生效后排空
        //（applySnapshot 语义不变：新快照仍覆盖 pending，最新者胜）。
        guard collectionView.window != nil, collectionView.bounds.width > 0 else { return }
        pendingSnapshot = nil
        isApplyingSnapshot = true
        indexBar.isUserInteractionEnabled = false   // S03：apply 期间禁用索引条（防越界 scrollToItem）

        // R03 前插补偿 v2（绿14 实锤：completion 期一次性补偿读到的 exactMinY 仍是过渡态布局，
        // 过冲 ~2700pt → 视口漂到 15 个月之外）。改为登记「锚点保持」任务：只记录首可见 asset
        // 及其视觉 y，viewDidLayoutSubviews 每个布局 pass 按该 asset 的真实 minY 重校
        // contentOffset，直到视觉 y 复位（≤0.5pt）或用户接管。仅同 query 的纯前插启用
        //（筛选变化是不同投影，不算漂移）。
        var headInsertAnchor: (assetID: String, visualY: CGFloat)?
        if pending.queryKey == currentSnapshotQueryKey,
           !collectionView.isTracking, !collectionView.isDecelerating,
           // M15 实锤：恢复进行中打的位置快照是恢复前落点，登记下去会在恢复 settle 后
           // 把已精确恢复的位置拖走（冷启动 −520pt 实锤）——恢复期间绝不登记补偿。
           !isRestoringPosition, !positionCoordinator.isRestoreInFlight,
           let snapshot = makePositionSnapshot() {
            headInsertAnchor = (snapshot.anchorAssetID, CGFloat(snapshot.anchorVisualY))
        }

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
            // v4 前插补偿：登记锚点保持任务（enforceHeadInsertAnchor 在布局 pass 里收敛）
            if let keep = headInsertAnchor {
                pendingHeadInsertAnchor = HeadInsertAnchor(assetID: keep.assetID,
                                                           visualY: keep.visualY)
            }
            // M12 R06/R07：快照变化后刷新分类菜单（scope 勾选 + 异步计数）与待处理徽标
            self.refreshSessionBadge()
            self.refreshCategoryCountsAsync()
            // 多选中：筛选/pending 变化 → 选中集合收敛到新 scope（docs/09 D11 §3）
            if self.isSelecting {
                let newScope = Set(self.currentItemsBySection.flatMap { $0.map(\.id) })
                self.selectionState.intersectScope(with: newScope)
                self.reloadSelectionBadges()
                self.updateSelectionCount()
            }
            #if DEBUG
            refreshDebugScrollNote()
            self.attemptDebugChromeHooksIfNeeded() // M12：工具/分类/选择 scope 钩子（走同一条路径）
            #endif
            // M12（验证轮 10 .ips 实锤）：apply completion 内不得嵌套再次 apply / 触发布局——
            // 恢复与排空全部推迟到下一轮主循环（杜绝 _existingNumberOfItemsInSection abort）
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isViewLoaded else { return }
                // 位置记忆恢复 v4（docs/22 §4.4.4）：beginRestore 只 load 一次；attempt 可重入
                self.positionCoordinator.beginRestore(queryKey: pending.queryKey)
                self.attemptPositionRestore()
                #if DEBUG
                // M13 绿5 实锤：月份跳转钩子必须晚于恢复——恢复会覆盖跳转落点（等价用户点卡片
                // 的语义优先于跨进程位置恢复）；retry 语义不变（每次 apply completion 都尝试）。
                self.attemptDebugMonthJumpIfNeeded()
                #endif
                self.drainPendingSnapshot()   // apply 期间又来了新快照 → 下一轮排空
            }
        }
    }

    #if DEBUG
    /// 单元测试断言锚点（R03 恢复遮罩 / R04 Toast 位置）
    var test_restoreMask: UIView { restoreMaskView }
    var test_batchToast: DSToast { batchToast }
    var test_selectionBar: UIView { selectionBar }
    /// collectionView 是 view 加载后才赋值的 IUO：宿主导航栈路径下 view 可能未加载，
    /// 访问前先 loadViewIfNeeded，避免单测进程 Implicitly unwrapped nil 崩溃。
    var test_collectionView: UICollectionView {
        loadViewIfNeeded()
        return collectionView
    }

    private func applyDebugFilterHookIfNeeded() {
        guard let year = UITestHooks.intValue("-uiTestingFilterYear") else { return }
        ViewerTrace.log("hook filterYear=\(year)")
        if year == 0 {
            viewModel.clearFilter()
        } else {
            var filter = viewModel.query.filter
            filter.year = year
            filter.month = nil
            filter.day = nil
            viewModel.setFilter(filter)
        }
    }

    private func applyDebugMonthJumpHookIfNeeded() {
        guard let sectionID = UITestHooks.stringValue("-uiTestingMonthJump"), !sectionID.isEmpty else { return }
        pendingDebugMonthJumpSectionID = sectionID
    }

    private var pendingDebugMonthJumpSectionID: String?

    /// docs/13 M11 / M13：每次 apply completion 尝试 -uiTestingMonthJump（等价月份面板点卡片，
    /// 同一条 scrollToSection 路径；成功即置位，快照未含目标月时随下一次 apply 重试）
    private func attemptDebugMonthJumpIfNeeded() {
        guard !debugMonthJumpDone,
              let sectionID = pendingDebugMonthJumpSectionID else { return }
        guard let index = currentSections.firstIndex(where: { $0.id == sectionID }) else {
            // 绿8 取证：目标月不在当前快照（如跨用例泄漏的筛选只剩 2026）——记一次等待痕迹
            ViewerTrace.log("jump.wait target=\(sectionID) sections=\(currentSections.count)")
            return
        }
        if scrollToSection(index) {
            debugMonthJumpDone = true
        } else {
            ViewerTrace.log("jump.skip target=\(sectionID) cvSections=\(collectionView.numberOfSections)")
        }
    }

    private var debugMonthJumpDone = false
    #endif

    /// M13 P2：把精确 contentOffset 写进 DEBUG 汇总（UI 像素锚点取证入口；Release 空实现）。
    private func refreshDebugScrollNote() {
        #if DEBUG
        let saved = currentSnapshotQueryKey.flatMap { positionStore.load(queryKey: $0) }
        let current = makePositionSnapshot()
        let anchor = current?.anchorAssetID ?? saved?.anchorAssetID ?? "-"
        let visualY = Int(current?.anchorVisualY ?? saved?.anchorVisualY ?? 0)
        let off = String(Int(Double(collectionView.contentOffset.y)))
        let maxOffset = String(Int(Double(max(0, collectionView.contentSize.height - collectionView.bounds.height))))
        let sectionCount = collectionView.numberOfSections
        let sections = String(sectionCount)
        let cells = sectionCount > 0 ? String(collectionView.numberOfItems(inSection: 0)) : "0"
        viewModel.debugScrollNote = "off=" + off + "/" + maxOffset +
            " anchor=" + anchor + " visualY=" + String(visualY) +
            " sec=" + sections + " cells=" + cells +
            " panMin=" + String(collectionView.panGestureRecognizer.minimumNumberOfTouches)
        #endif
    }

    // MARK: - 位置记忆 v4（docs/22 §4.4：单一协调器 + 恢复状态机；恢复期零回写）

    private var resignActiveObserver: NSObjectProtocol?

    /// 兼容入口：LibraryContainer / 旧单测只认这个方法名；内部只走 coordinator。
    func savePositionNow(reason: String) {
        positionCoordinator.saveNow(reason: reason, snapshot: makePositionSnapshot())
    }

    /// 主线程抓取几何快照：PositionAnchorSelector 选第一条完整可见、不被粘性头遮挡的 cell。
    private func makePositionSnapshot() -> LibraryPositionSnapshot? {
        guard !isRestoringPosition,
              positionStore.isEnabled,
              let queryKey = currentSnapshotQueryKey,
              !currentSections.isEmpty, !currentItemsBySection.isEmpty,
              collectionView.bounds.width > 0, collectionView.bounds.height > 0 else { return nil }
        let offsetY = Double(collectionView.contentOffset.y)
        let adjustedTop = Double(collectionView.adjustedContentInset.top)
        let effectiveTop = offsetY + adjustedTop + Double(DSSpacing.monthHeaderHeight)
        let viewportBottom = offsetY + Double(collectionView.bounds.height)
            - Double(collectionView.adjustedContentInset.bottom)
        let cells: [VisibleGridCell] = collectionView.indexPathsForVisibleItems.compactMap { ip in
            guard let attrs = collectionView.collectionViewLayout.layoutAttributesForItem(at: ip) else { return nil }
            return VisibleGridCell(section: ip.section,
                                   item: ip.item,
                                   minY: Double(attrs.frame.minY),
                                   maxY: Double(attrs.frame.maxY))
        }
        guard let anchor = PositionAnchorSelector.select(cells: cells,
                                                         effectiveTop: effectiveTop,
                                                         viewportBottom: viewportBottom),
              let item = dataSource.itemIdentifier(for: IndexPath(item: anchor.item, section: anchor.section)),
              let section = currentSections[safe: anchor.section] else { return nil }
        return LibraryPositionSnapshot(queryKey: queryKey,
                                       anchorAssetID: item.id,
                                       anchorVisualY: PositionAnchorPolicy.visualY(cellMinY: anchor.minY,
                                                                                  contentOffsetY: offsetY),
                                       anchorSectionID: section.id,
                                       anchorItemIndex: anchor.item,
                                       contentOffsetY: offsetY,
                                       contentHeight: Double(collectionView.contentSize.height),
                                       viewportHeight: Double(collectionView.bounds.height))
    }

    private func attemptPositionRestore() {
        guard positionCoordinator.isRestoreInFlight else { return }
        // 确保 anchorMinY / contentSize 取自本次真实布局，而不是上一次的估算值。
        collectionView.layoutIfNeeded()
        let context = LibraryPositionRestoreContext(
            bounds: collectionView.bounds.size,
            isIndexComplete: viewModel.isIndexComplete,
            contentHeight: Double(collectionView.contentSize.height),
            viewportHeight: Double(collectionView.bounds.height),
            adjustedTop: Double(collectionView.adjustedContentInset.top),
            bottomInset: Double(collectionView.adjustedContentInset.bottom),
            anchorInData: { [weak self] id in
                self?.indexPath(forAssetID: id) != nil
            },
            anchorMinY: { [weak self] id in
                guard let self else { return nil }
                return self.layoutMinY(forAssetID: id)
            },
            sectionMinY: { [weak self] sectionID, itemIndex in
                guard let self else { return nil }
                return self.layoutMinY(sectionID: sectionID, itemIndex: itemIndex)
            },
            scrollToAnchorTop: { [weak self] id in
                guard let self, let path = self.indexPath(forAssetID: id) else { return false }
                // §5.5：scrollToItem(.top) 让 UICollectionView 自己算目标 offset（知道全部 header 几何）
                self.isRestoringPosition = true
                self.collectionView.scrollToItem(at: path, at: .top, animated: false)
                self.collectionView.layoutIfNeeded()
                self.isRestoringPosition = false
                return true
            },
            applyOffset: { [weak self] y in
                guard let self else { return }
                self.isRestoringPosition = true
                self.collectionView.layoutIfNeeded()
                self.collectionView.setContentOffset(
                    CGPoint(x: self.collectionView.contentOffset.x, y: CGFloat(y)),
                    animated: false
                )
                self.collectionView.layoutIfNeeded()
                self.isRestoringPosition = false
                self.refreshDebugScrollNote()
            },
            actualOffsetY: { [weak self] in
                Double(self?.collectionView.contentOffset.y ?? 0)
            },
            layoutNow: { [weak self] in
                self?.collectionView.layoutIfNeeded()
            }
        )
        positionCoordinator.attemptRestore(context: context)
    }

    private func handlePositionPhase(_ phase: PositionRestorePhaseV5) {
        switch phase {
        case .restoring, .applying, .verifying, .fallback:
            showRestoreMaskIfNeeded()
        case .settled:
            hideRestoreMask()
            // 恢复是权威定位：恢复 settle 时丢弃恢复期间登记（或登记后未消费）的前插补偿，
            // 否则旧 visualY 会在恢复后把精确恢复的位置拖走（M15 冷启动 −520pt 实锤）。
            pendingHeadInsertAnchor = nil
            viewModel.debugRestoreNote = "restore=ok by=\(positionCoordinator.lastStrategy.rawValue)" +
                (positionCoordinator.lastRestoreDiagnostics.isEmpty ? "" : " | \(positionCoordinator.lastRestoreDiagnostics)")
            refreshDebugScrollNote()
        case .idle:
            break
        }
    }

    private func layoutMinY(forAssetID id: String) -> Double? {
        guard !id.isEmpty, let path = indexPath(forAssetID: id) else { return nil }
        return layoutMinY(at: path)
    }

    private func indexPath(forAssetID id: String) -> IndexPath? {
        for sectionIndex in 0..<currentItemsBySection.count {
            if let itemIndex = currentItemsBySection[sectionIndex].firstIndex(where: { $0.id == id }) {
                return IndexPath(item: itemIndex, section: sectionIndex)
            }
        }
        return nil
    }

    private func layoutMinY(sectionID: String, itemIndex: Int) -> Double? {
        guard let sectionIndex = currentSections.firstIndex(where: { $0.id == sectionID }) else { return nil }
        let count = currentItemsBySection[safe: sectionIndex]?.count ?? 0
        guard count > 0 else { return nil }
        let item = min(max(0, itemIndex), count - 1)
        return layoutMinY(at: IndexPath(item: item, section: sectionIndex))
    }

    private func layoutMinY(at indexPath: IndexPath) -> Double? {
        // 已物化 cell 的 frame 是当前布局的真实值；layoutAttributes 在远距离/估算高度下可能是旧估计。
        if let cell = collectionView.cellForItem(at: indexPath) {
            return Double(cell.frame.minY)
        }
        guard let frame = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        return Double(frame.minY)
    }

    /// 0.15s 后才淡入；done/failed/timeout 立即淡出，绝不永久遮挡。
    private func showRestoreMaskIfNeeded() {
        guard restoreMaskView.alpha == 0 else { return }
        restoreMaskGeneration += 1
        let generation = restoreMaskGeneration
        view.bringSubviewToFront(restoreMaskView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self,
                  generation == self.restoreMaskGeneration,
                  self.positionCoordinator.isRestoreInFlight else { return }
            UIView.animate(withDuration: 0.15) { self.restoreMaskView.alpha = 1 }
            // §5.4：遮罩最长显示 1.5s；消失不代表恢复失败，恢复可在后台继续
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, generation == self.restoreMaskGeneration else { return }
                if self.restoreMaskView.alpha > 0 {
                    UIView.animate(withDuration: 0.15) { self.restoreMaskView.alpha = 0 }
                }
            }
        }
    }

    private func hideRestoreMask() {
        restoreMaskGeneration += 1
        UIView.animate(withDuration: 0.15) { self.restoreMaskView.alpha = 0 }
    }

    /// 月份/索引条跳转（docs/13 S09/S11）：校验 → 滚动 → 抵消粘性 header → 同步保存 → 顶部细横幅
    /// - Returns: 是否实际执行了滚动（false = 校验未通过/快照未提交，调用方可重试）
    @discardableResult
    func scrollToSection(_ index: Int) -> Bool {
        // 用户主动月份跳转优先于跨进程恢复：取消恢复并收起遮罩，避免异步 restore 覆盖跳转落点。
        positionCoordinator.cancelRestore(reason: "monthJump")
        // S03 修复：校验 collectionView 实际 section/item 数（apply 未提交时 currentSections 已是新值）
        guard index < currentSections.count,
              index < collectionView.numberOfSections,
              collectionView.numberOfItems(inSection: index) > 0 else { return false }
        isRestoringPosition = true
        collectionView.layoutIfNeeded()
        // M13 绿12 实锤：远距离目标（2024-05 距顶部约 60 个月）的 header 布局属性是估算高度，
        // 一次性按估算 minY 跳转累计误差数千 pt（落到 2022-09）。改两段式：先 scrollToItem
        // 落到目标 cell（UIKit 内部对估算高度自校正），物化后按真实 header minY 二次校正，
        // 粘性头钉在月份边界（同时消除旧 -48pt 魔法数字）。
        let indexPath = IndexPath(item: 0, section: index)
        collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        collectionView.layoutIfNeeded()
        let headerAttrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: indexPath)
        let maxOffsetY = max(0, collectionView.contentSize.height
            - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
        if let headerMinY = headerAttrs?.frame.minY {
            let targetY = min(max(0, headerMinY - collectionView.adjustedContentInset.top), maxOffsetY)
            if abs(collectionView.contentOffset.y - targetY) > 0.5 {
                collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
                collectionView.layoutIfNeeded()
            }
        }
        isRestoringPosition = false
        indexBar.setHighlighted(index: index, notify: false)
        // v4：月份跳转后走同一协调器保存。M15 冷启动实锤：落地点的布局属性是估算值，
        // 立即保存会把校正前的位置写进文件（下一次恢复差 520pt）。改为登记待存标记，
        // 由 verifyJumpLanding 收敛（真实布局、钉住线复核通过）后保存。
        pendingJumpSave = true
        if let section = currentSections[safe: index] {
            // M13 绿12 实锤：跳转存档正确后视口仍会被 UIKit 内部调整（pinned header 重排 /
            // 快照 apply 期间的位置保持）推离目标月（AX 与 idle 存档均显示漂移到别的月份）。
            // 月跳语义必须落在目标月：登记复核目标，viewDidLayoutSubviews 里按真实钉住线核对，
            // 未钉住就再校正（事件驱动、最多 5 次防打转，与 restore pending 门禁同一严格语义）。
            pendingJumpVerifySectionID = section.id
            jumpVerifyAttempts = 0
        }
        showJumpBanner(section: currentSections[index])
        return true
    }

    /// 月跳待存的落盘出口：复核收敛（或放弃复核）后按当前真实几何保存一次。
    private func flushPendingJumpSave(reason: String) {
        guard pendingJumpSave else { return }
        pendingJumpSave = false
        positionCoordinator.saveNow(reason: reason, snapshot: makePositionSnapshot())
    }

    /// 月跳落地复核：钉住线上的 section 必须是目标月，否则按当前真实布局再校正
    private func verifyJumpLanding() {
        guard let targetID = pendingJumpVerifySectionID else { return }
        guard !isRestoringPosition, !isApplyingSnapshot,
              collectionView.window != nil, collectionView.bounds.width > 0 else { return }
        guard let targetIndex = currentSections.firstIndex(where: { $0.id == targetID }) else {
            pendingJumpVerifySectionID = nil
            return
        }
        if jumpVerifyAttempts >= 5 {
            pendingJumpVerifySectionID = nil
            flushPendingJumpSave(reason: "jump-verify-give-up")
            ViewerTrace.log("position.jump-verify give-up target=\(targetID) attempts=5")
            return
        }
        let pinY = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        var pinnedIndex: Int?
        for s in 0..<collectionView.numberOfSections {
            guard let attrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: s)),
                attrs.frame.minY <= pinY + 1 else { break }
            pinnedIndex = s
        }
        if pinnedIndex == targetIndex {
            pendingJumpVerifySectionID = nil
            jumpVerifyAttempts = 0
            ViewerTrace.log("position.jump-verified section=\(targetID)")
            flushPendingJumpSave(reason: "monthJump")
            #if DEBUG
            refreshDebugScrollNote()   // 校正后的真实位置要同步进取证摘要
            #endif
            return
        }
        jumpVerifyAttempts += 1
        ViewerTrace.log("position.jump-reassert pinned=\(pinnedIndex.map(String.init) ?? "nil") target=\(targetIndex) attempt=\(jumpVerifyAttempts)")
        scrollToSection(targetIndex)
    }

    /// v4 前插补偿：按同一锚点 assetID + 视觉 y 收敛 contentOffset，最多 3 个布局 pass。
    /// 用户接管（拖动/减速）或恢复进行中立即让位，绝不与用户/恢复抢滚动。
    private func enforceHeadInsertAnchor() {
        guard let keep = pendingHeadInsertAnchor else { return }
        guard !isRestoringPosition, !positionCoordinator.isRestoreInFlight, !isApplyingSnapshot,
              collectionView.window != nil, collectionView.bounds.width > 0,
              !collectionView.isTracking, !collectionView.isDecelerating else { return }
        guard let path = indexPath(forAssetID: keep.assetID),
              let attrs = collectionView.collectionViewLayout.layoutAttributesForItem(at: path) else {
            pendingHeadInsertAnchor = nil
            ViewerTrace.log("snapshot.head-insert dropped asset=\(keep.assetID.prefix(8)) 不在当前快照")
            return
        }
        let maxY = max(0, collectionView.contentSize.height
            - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
        let targetY = min(max(0, attrs.frame.minY - keep.visualY), maxY)
        if abs(collectionView.contentOffset.y - targetY) > 0.5 {
            // 无 3 次上限（docs/25 §5.7）：每 pass 用当前真实布局重算；锚点被删则上游已丢弃
            let dy = targetY - collectionView.contentOffset.y
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: targetY), animated: false)
            ViewerTrace.log("snapshot.head-insert dy=\(Int(dy)) asset=\(keep.assetID.prefix(8))")
        } else {
            pendingHeadInsertAnchor = nil
            ViewerTrace.log("snapshot.head-insert settled asset=\(keep.assetID.prefix(8)) visualY=\(Int(keep.visualY))")
        }
    }

    /// 月份面板「回到顶部」（docs/13 S09）
    func scrollToTop() {
        guard collectionView.numberOfSections > 0 else { return }
        isRestoringPosition = true
        collectionView.setContentOffset(.zero, animated: false)
        isRestoringPosition = false
        positionCoordinator.saveNow(reason: "scrollTop", snapshot: makePositionSnapshot())
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
            // 列宽变化 → cell 内取图尺寸变化 → 重载可视 cell（缓存键含尺寸）。
            // M12：apply 窗口内推迟（绕过 Diffable 的更新与 dataSource.apply 撞车 = abort）
            let applyReload = { [weak self] in
                guard let self else { return }
                self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
                if let anchor, anchor.section < self.currentSections.count {
                    self.collectionView.scrollToItem(at: anchor, at: .centeredVertically, animated: false)
                }
            }
            if self.isApplyingSnapshot {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isApplyingSnapshot else { return }
                    applyReload()
                }
            } else {
                applyReload()
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // v4：appear 是 restore 的第三个入口（applySnapshot / viewDidLayoutSubviews 之外）
        attemptPositionRestore()
        #if DEBUG
        refreshDebugScrollNote()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 首次布局前 dequeue 的 cell 拿到的是占位尺寸：布局稳定后重配可视 cell（缓存键含尺寸）。
        // M12（验证轮 12 .ips 实锤）：reloadItems 绕过 Diffable 数据源——与进行中的 dataSource.apply
        // 撞车即触发 _existingNumberOfItemsInSection abort；apply 窗口内推迟到下一轮主循环。
        let pixel = cellPixelSize
        if lastConfiguredPixelSize != .zero, pixel != lastConfiguredPixelSize {
            if isApplyingSnapshot {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isApplyingSnapshot,
                          let layout = self.collectionView.collectionViewLayout as? UICollectionViewCompositionalLayout
                    else { return }
                    self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
                }
            } else {
                collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
            }
        }
        lastConfiguredPixelSize = pixel
        // M13：月跳落地复核——布局稳定后按真实钉住线核对目标月，未钉住再校正
        verifyJumpLanding()
        // v4 前插补偿——按同一锚点 assetID + 视觉 y 收敛布局
        enforceHeadInsertAnchor()
        // v4：viewDidLayoutSubviews 是 bounds=0 竞态的唯一重试入口（不再只依赖 apply completion）
        attemptPositionRestore()
        // M12：集合视图完成初次布局后排空挂起的快照（见 drainPendingSnapshot 布局守卫）
        if collectionView.bounds.width > 0, pendingSnapshot != nil, !isApplyingSnapshot {
            drainPendingSnapshot()
        }
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
        indexBar.update(entries: entries, highlightedIndex: visibleSectionIndex)
    }

    /// 当前视口第一条可见 cell 所属 section（用于索引条常亮当前月份）。
    private var visibleSectionIndex: Int {
        let paths = collectionView.indexPathsForVisibleItems
        guard let first = paths.min(by: {
            $0.section == $1.section ? $0.item < $1.item : $0.section < $1.section
        }) else { return -1 }
        return first.section
    }

    private func updateIndexBarHighlight() {
        let index = visibleSectionIndex
        guard index >= 0 else { return }
        indexBar.setHighlighted(index: index, notify: false)
    }
}

// MARK: - Delegate（预取）

extension LibraryViewController: UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // docs/13 §3.7：一律经 dataSource 取 item（apply 窗口内数组下标不可信）
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        if isSelecting {
            // M13：拖选进行中的 touch-up 穿透不得再触发点选切换（allowsSelection 已关，双保险）
            if slideSelectController?.isDragSelecting == true { return }
            toggleSelection(id: item.id)
            return
        }
        // ViewerContext：当前筛选结果 + 被点条目（assetID 定位，docs/09 D01）
        onOpenViewer?(item)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateIndexBarHighlight()
        // 位置记忆 v5：0.5s 防抖且只在用户 tracking 时（程序化 offset 不保存），coordinator 门禁兜底。
        guard scrollView.isTracking,
              !isRestoringPosition, !positionCoordinator.isRestoreInFlight else { return }
        positionCoordinator.scheduleSave(reason: "scroll", snapshot: makePositionSnapshot())
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        positionCoordinator.saveNow(reason: "decelerating", snapshot: makePositionSnapshot())
        cancelRestSave()
        #if DEBUG
        refreshDebugScrollNote()   // 取证摘要跟随真实滚动位置（UI 测试读 off/anchor）
        #endif
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // docs/22 §4.4.3：无论是否继续减速都保存一次（旧实现只在 !decelerate 保存，是漏洞）。
        positionCoordinator.saveNow(reason: "dragging", snapshot: makePositionSnapshot())
        if decelerate {
            // 减速结束回调与进程死亡存在竞速（M15 冷启动实锤：文件里留下减速中途快照）。
            // 安排"静止补存"：触发时重新抓快照——长滑未静止时它是兜底，已静止时与
            // decelerating 保存同值幂等；didEndDecelerating 到达时取消。
            cancelRestSave()
            let work = DispatchWorkItem { [weak self] in
                self?.savePositionNow(reason: "rest")
            }
            restSaveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        } else {
            cancelRestSave()
        }
        #if DEBUG
        refreshDebugScrollNote()
        #endif
    }

    private func cancelRestSave() {
        restSaveWorkItem?.cancel()
        restSaveWorkItem = nil
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
    /// docs/22 §5.5：单指 pan 只在起点位于 cell 上时让滑选手势开始；双指交给 collectionView。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === slideSelectPan else { return true }
        guard isSelecting else { return false }
        guard gestureRecognizer.numberOfTouches <= 1,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let point = pan.location(in: collectionView)
        return collectionView.indexPathForItem(at: point) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // 滑选 pan 不与 collectionView 滚动/捏合同时识别（单指已由 minimumNumberOfTouches=2 分离）。
        if gestureRecognizer === slideSelectPan || other === slideSelectPan { return false }
        return true
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
        // M13 绿15 实锤（Auto Layout 冲突日志）：两个子视图都没关 autoresizing mask 约束，
        // AMAS 的 width/height == 0 与显式约束打架，UIKit 随机折衷——菜单按钮被压成 0×0，
        // AX 剔除零尺寸元素 →「月份头缺菜单按钮」（M12 历史 #12 条总根源）。
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false
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
