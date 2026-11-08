// MARK: - 职责说明：全屏浏览 UIKit 分页器（docs/05 M2/M3；docs/09 Phase 4 重写）★——
// UICollectionView 横向 paging；首次 viewDidLayoutSubviews 按 assetID 定位（D01）；
// 删除/隐藏走会话暂存：同步入队 → 飞出 → performBatchUpdates 删 cell → ReplacementPlan 补位动画（D02/D16）；
// 滚动回调只在用户手势时更新 index（isProgrammaticScroll 屏蔽程序化滚动）；cell 级加载 token；
// 无 App 内删除/隐藏确认（D03/D04）；动作池：加相簿/分享/信息/旋转/长按菜单全部接入（D15）；
// 视频点击暂停/继续；双击缩放不触发 chrome 切换；顶部 SessionBadge 待处理入口。

import UIKit
import PhotoDeskCore
import SwiftUI

final class ViewerViewController: UIViewController {
    // MARK: - 依赖

    private let viewModel: ViewerViewModel
    private let pipeline: ImagePipelineProtocol
    private let settings: SettingsStore
    private let undoCenter: UndoCenter

    // MARK: - 手势与浮层

    private lazy var engine = SwipeGestureEngine(config: SwipeGestureEngine.config(for: settings.sensitivity))
    private let upOverlay = ActionOverlayView(frame: .zero)     // 上滑 → 屏幕上方 1/4
    private let downOverlay = ActionOverlayView(frame: .zero)   // 下滑 → 屏幕下方 1/4
    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - UI

    private var collectionView: UICollectionView!
    private let topBar = UIToolbar()
    private let filmStrip = FilmStripView(frame: .zero)
    private let toast = DSToast(frame: .zero)
    private var topBarItems: [UIBarButtonItem] = []
    /// ⋯ 菜单按钮（actionSheet popover 锚点）
    private var moreButtonItem: UIBarButtonItem?
    private var favoriteButton: UIBarButtonItem!
    private var chromeVisible = true
    private var chromeTimer: Timer?
    /// 程序化滚动标志（屏蔽 scrollViewDidScroll 的 index 写回，docs/09 D01）
    private var isProgrammaticScroll = false
    /// 首次布局定位（D01：viewDidLoad 时 bounds 未定，scrollToItem 无效——布局后按 assetID 定位）
    private var needsInitialPositioning = true
    /// 删除事务进行中（docs/13 S12：同一时间只允许一个 plan→commit→settle 事务）
    private var isRemovalInFlight = false
    /// commitRemoval 结果（batch block 内赋值，completion 消费）
    private var pendingRemovalResult: ViewerViewModel.RemovalResult?
    /// M13 P1：缩放事务活跃期收到的删除/隐藏动作——按 FIFO 排队，待几何事务 idle 后串行 drain。
    /// 绝不在 pinch 中 performBatchUpdates，也绝不把用户动作直接丢弃。
    private var pendingRemovalActions: [(SwipeAction, PhotoDeskCore.VerticalEdge?)] = []
    /// 在途大图加载数（DEBUG 横幅 load= 字段；S08 验收 ≤3）
    private var inflightLoadCount = 0
    /// 预取防抖任务（docs/13 S02：100ms 内多次翻页只预取最后一次）
    private var prefetchDebounceTask: Task<Void, Never>?

    var onClose: (() -> Void)?

    init(viewModel: ViewerViewModel, pipeline: ImagePipelineProtocol,
         settings: SettingsStore, undoCenter: UndoCenter) {
        self.viewModel = viewModel
        self.pipeline = pipeline
        self.settings = settings
        self.undoCenter = undoCenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DSColor.bgViewer
        view.accessibilityIdentifier = "ViewerRoot"
        setupCollectionView()
        setupOverlays()
        setupTopBar()
        setupFilmStrip()
        setupToast()
        setupPanGesture()
        scheduleChromeHide()
        logPendingDeleteCount("open items=\(viewModel.items.count) idx=\(viewModel.currentIndex)")
        ViewerTrace.log("open items=\(viewModel.items.count) idx=\(viewModel.currentIndex)")

        undoCenter.onExpire = { [weak self] _ in
            self?.toast.dismiss()
        }
        viewModel.onUndoApplied = { [weak self] in
            self?.refreshChrome()
        }
        viewModel.onItemRestored = { [weak self] in
            self?.reloadAfterRestore()
        }

        modalPresentationStyle = .fullScreen
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // M12 Phase 1：appear 面包屑（present 信息/编辑/分享或切 Tab 返回的取证锚点）
        ViewerTrace.log("appear idx=\(viewModel.currentIndex) count=\(viewModel.items.count)")
        // M12 A3：appear 时当前 cell 必有 image 或在途任务（present 信息/编辑/分享、切 Tab 返回的恢复路径）
        remountCurrentLoadIfNeeded()
        // M13 P1：appear 后若当前 cell 已 idle，排空之前因缩放事务暂存的删除/隐藏动作。
        schedulePendingRemovalDrain()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 浮层锚点：上滑 = 上方 1/4，下滑 = 下方 1/4（docs/04 §3.2）
        let width = view.bounds.width
        let height = view.bounds.height
        upOverlay.frame = CGRect(x: 0, y: height * 0.25 - 70, width: width, height: 140)
        upOverlay.setBaseCenter(y: height * 0.25)
        downOverlay.frame = CGRect(x: 0, y: height * 0.75 - 70, width: width, height: 140)
        downOverlay.setBaseCenter(y: height * 0.75)
        // 无障碍替代栏：手势关闭时常驻
        let showBar = !settings.gesturesEnabled
        accessibilityBar.isHidden = !showBar
        filmStrip.isHidden = showBar ? true : filmStrip.isHidden
        view.bringSubviewToFront(accessibilityBar)
        // M12 A4：itemSize 跟随真实 bounds——fullScreenCover 首布局 bounds 为 .zero/占位值，
        // 旧版只在 viewDidLoad 设一次 → 全部 cell 零尺寸 → 整页空白
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
           collectionView.bounds.width > 0, collectionView.bounds.height > 0,
           layout.itemSize != collectionView.bounds.size {
            layout.itemSize = collectionView.bounds.size
            layout.invalidateLayout()
            if !needsInitialPositioning {
                positionAtCurrentIndex()   // 布局变化后保持页码（内部 isProgrammaticScroll 包裹）
            }
        }
        // D01：首次拿到有效宽度后按当前 index 定位（contentOffset 直设，不触发 didScroll 写回）
        if needsInitialPositioning, width > 0, !collectionView.isHidden {
            needsInitialPositioning = false
            positionAtCurrentIndex()
        }
    }

    /// 离开查看器：取消全部在途请求与预取（docs/13 S02 验收项 7）。
    /// M12 A3：仅在真正离开（被关闭）时取消——present 信息/编辑/分享或切 Tab 返回后必须恢复显示
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        prefetchDebounceTask?.cancel()
        pipeline.cancelAll()
    }

    /// M12 A3：重挂当前页加载（无图且无有效在途任务时；A1 修复后 cell 无图 = 未加载或被取消）
    private func remountCurrentLoadIfNeeded() {
        guard isViewLoaded, collectionView.bounds.width > 0 else { return }
        let index = viewModel.currentIndex
        guard index < viewModel.items.count,
              let item = viewModel.items[safe: index],
              let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ZoomableImageCell,
              !cell.hasImage else { return }
        // loadTask 为 nil 或已取消都算「无在途」——present 信息页返回后正是被取消的旧任务
        let hasLiveTask = !(cell.loadTask?.isCancelled ?? true)
        guard !hasLiveTask else { return }
        ViewerTrace.log("remount idx=\(index) id=\(item.id.prefix(8))")
        loadImage(for: item, at: index, cell: cell)
    }

    /// 旋转 / 分屏（docs/09 Phase 7）：更新 itemSize，按当前 assetID 保持页码不跳回第 1 张
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self,
                  let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
            layout.itemSize = size
            layout.invalidateLayout()
            let index = max(0, min(self.viewModel.currentIndex, max(0, self.viewModel.items.count - 1)))
            self.isProgrammaticScroll = true
            self.collectionView.setContentOffset(CGPoint(x: CGFloat(index) * size.width, y: 0), animated: false)
            self.isProgrammaticScroll = false
        }, completion: nil)
    }

    // MARK: - 构建

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.itemSize = view.bounds.size
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.isPagingEnabled = true
        collectionView.backgroundColor = DSColor.bgViewer
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPrefetchingEnabled = true
        collectionView.prefetchDataSource = self
        collectionView.register(ZoomableImageCell.self, forCellWithReuseIdentifier: ZoomableImageCell.reuseID)
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseID)
        view.addSubview(collectionView)
    }

    /// 首次/恢复定位（contentOffset 直设 + 显式 updateIndex，绕过 scrollViewDidScroll）
    private func positionAtCurrentIndex() {
        let index = max(0, min(viewModel.currentIndex, max(0, viewModel.items.count - 1)))
        viewModel.updateIndex(index)
        isProgrammaticScroll = true
        collectionView.setContentOffset(CGPoint(x: CGFloat(index) * collectionView.bounds.width, y: 0),
                                        animated: false)
        isProgrammaticScroll = false
        filmStrip.highlight(index: index, centerIfNeeded: true)
        refreshChrome()
        prefetchAround(index: index)
        refreshDebugBanner()
    }

    private func setupOverlays() {
        view.addSubview(upOverlay)
        view.addSubview(downOverlay)
        upOverlay.hide()
        downOverlay.hide()
        #if DEBUG
        // CI 截图自诊断 + D01 断言锚点（Release 不编译）
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugLabel)
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            debugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        ])
        #endif
    }

    #if DEBUG
    private let debugLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .black
        label.backgroundColor = .systemYellow
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.text = "viewer:ready"
        // UI 测试（docs/09 D01 + docs/13 S01/S08）：横幅含 items/idx/id/zoom/load/img 字段
        label.accessibilityIdentifier = "Viewer-Debug"
        return label
    }()

    private func updateDebugLabel(_ text: String) {
        debugLabel.text = text
    }

    /// 带全部状态字段的横幅（items/idx/id/zoom/load/img，docs/13 §3.9 + docs/16 M12 R02）。
    /// zoom / frameW 只在翻页/定时器/用户操作时从 cell.diagnostics 读取；缩放 delegate 不刷新本横幅。
    private func refreshDebugBanner() {
        guard isViewLoaded else { return }
        let index = viewModel.currentIndex
        let idPart = viewModel.items[safe: index].map { "id=\($0.id)" } ?? "id=-"
        let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ZoomableImageCell
        let imgPart = cell.map { "img=\($0.hasImage ? "ok" : "nil")" } ?? "img=-"
        let zoom = Double(cell?.diagnostics.currentScale ?? ZoomableImageCell.minZoomScale)
        let frameWidth = Double(cell?.imageViewFrameWidth ?? -1)
        let trace = ViewerTrace.recentLines()
        let nonFinite = trace.contains {
            $0.localizedCaseInsensitiveContains("nan")
                || $0.localizedCaseInsensitiveContains("non-finite")
                || $0.localizedCaseInsensitiveContains("非有限")
        }
        let pending = AppContainer.shared.reviewSession.pendingDeleteCount
        updateDebugLabel("items=\(viewModel.items.count) idx=\(index) \(idPart) " +
                         "zoom=\(String(format: "%.2f", zoom)) load=\(inflightLoadCount) \(imgPart) " +
                         "frameW=\(String(format: "%.1f", frameWidth)) " +
                         "pendingDeleteCount=\(pending) traceNonFinite=\(nonFinite ? 1 : 0)")
    }

    /// 单元测试布局断言锚点（A4：itemSize 刷新；Release 不编译）
    var test_collectionView: UICollectionView { collectionView }
    #else
    private func refreshDebugBanner() {}
    #endif

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        topBar.setShadowImage(UIImage(), forToolbarPosition: .any)
        topBar.barTintColor = .clear
        view.addSubview(topBar)

        let close = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                    style: .plain, target: self, action: #selector(closeTapped))
        close.accessibilityLabel = "关闭"
        close.accessibilityIdentifier = "Viewer-Close"   // UI 测试锚点
        // SessionBadge（docs/09 D16）：查看器顶部待处理入口 → SessionReviewView
        let sessionBadge = UIBarButtonItem(title: "", style: .plain, target: self,
                                           action: #selector(sessionBadgeTapped))
        sessionBadge.accessibilityIdentifier = "SessionBadge"
        sessionBadge.isEnabled = true
        sessionBadge.width = DSTouch.minimum
        favoriteButton = UIBarButtonItem(image: UIImage(systemName: favoriteIconName),
                                         style: .plain, target: self,
                                         action: #selector(favoriteTapped))
        favoriteButton.accessibilityLabel = "收藏"
        let info = UIBarButtonItem(image: UIImage(systemName: "info.circle"),
                                   style: .plain, target: self, action: #selector(infoTapped))
        info.accessibilityLabel = "查看信息"
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"),
                                   style: .plain, target: self, action: #selector(moreTapped))
        more.accessibilityLabel = "更多"
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        topBarItems = [close, sessionBadge, flexibleSpace, favoriteButton, info, more]
        moreButtonItem = more
        topBar.setItems(topBarItems, animated: false)

        // 点击屏幕切换 chrome。M15 实锤：根视图上的占位双击手势（只为让单击等待双击失败）
        // 会与 cell 的双击互斥竞争且抢占成功 → cell 缩放从未触发。删除占位双击：
        // 双击缩放时 chrome 会切换两次（无净变化），cell 的双击从此唯一持有双击语义。
        let tap = UITapGestureRecognizer(target: self, action: #selector(viewTapped(_:)))
        view.addGestureRecognizer(tap)
        // 长按操作菜单（docs/09 D15）
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(viewLongPressed(_:)))
        view.addGestureRecognizer(longPress)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),
        ])
        refreshChrome()
    }

    private func setupFilmStrip() {
        filmStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filmStrip)
        NSLayoutConstraint.activate([
            filmStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filmStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filmStrip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            filmStrip.heightAnchor.constraint(equalToConstant: 56),
        ])
        filmStrip.reload(ids: viewModel.items.map(\.id),
                         currentIndex: viewModel.currentIndex,
                         pipeline: pipeline) { [weak self] index in
            self?.scrollTo(index: index)
        }
        setupAccessibilityBar()
    }

    /// 无障碍替代路径（docs/04 §6）：关闭手势时底部常驻三按钮；删除/隐藏走会话暂存（无确认）
    private func setupAccessibilityBar() {
        accessibilityBar.translatesAutoresizingMaskIntoConstraints = false
        accessibilityBar.axis = .horizontal
        accessibilityBar.distribution = .fillEqually
        accessibilityBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.addSubview(accessibilityBar)

        func barButton(_ symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 4
            config.title = label
            button.configuration = config
            button.tintColor = .white
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            button.accessibilityLabel = label
            return button
        }

        accessibilityBar.addArrangedSubview(barButton("heart", label: "收藏") { [weak self] in
            self?.executeAction(.toggleFavorite, direction: .up, exitEdge: .top)
        })
        accessibilityBar.addArrangedSubview(barButton("eye.slash", label: "隐藏") { [weak self] in
            self?.executeAction(.hide, direction: .down, exitEdge: .bottom)
        })
        accessibilityBar.addArrangedSubview(barButton("trash", label: "移到最近删除") { [weak self] in
            self?.executeAction(.moveToRecentlyDeleted, direction: .down, exitEdge: .bottom)
        })

        NSLayoutConstraint.activate([
            accessibilityBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accessibilityBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accessibilityBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            accessibilityBar.heightAnchor.constraint(equalToConstant: 52),
        ])
        // 胶片条上移让位
        filmStrip.bottomAnchor.constraint(equalTo: accessibilityBar.topAnchor, constant: -8).isActive = true
    }

    /// 手势开关实时生效
    private var accessibilityBar: UIStackView = {
        let stack = UIStackView()
        stack.isHidden = true
        return stack
    }()

    private func setupToast() {
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DSSpacing.screenPadding),
            toast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DSSpacing.screenPadding),
            toast.bottomAnchor.constraint(equalTo: filmStrip.topAnchor, constant: -DSSpacing.toastBottomOffset),
        ])
    }

    private func setupPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        collectionView.addGestureRecognizer(pan)
    }

    // MARK: - Pan 手势（docs/03 §5.1）

    @objc private func onPan(_ gesture: UIPanGestureRecognizer) {
        let rawTranslation = gesture.translation(in: view)
        let rawVelocity = gesture.velocity(in: view)
        let translation = CGSize(width: rawTranslation.x, height: rawTranslation.y)
        let velocity = CGSize(width: rawVelocity.x, height: rawVelocity.y)
        switch gesture.state {
        case .began:
            engine.begin()

        case .changed:
            // M12 B1：持续复查（不只 shouldBegin 起始判一次）——cell 进入缩放事务立即让位
            guard ViewerGesturePolicy.shouldPanBegin(
                gesturesEnabled: settings.gesturesEnabled,
                numberOfTouches: gesture.numberOfTouches,
                cell: currentCellZoomState()) else {
                engine.cancel()
                hideOverlays()
                if !collectionView.isScrollEnabled { collectionView.isScrollEnabled = true }
                return
            }
            let output = engine.update(translation: translation, velocity: velocity)
            if output.isHorizontal {
                hideOverlays()
                if !collectionView.isScrollEnabled { collectionView.isScrollEnabled = true }
            } else if let direction = output.direction {
                // 垂直方向锁：停用分页，松手恢复
                collectionView.isScrollEnabled = false
                let action = viewModel.action(for: direction)
                let overlay = direction == .up ? upOverlay : downOverlay
                let other = direction == .up ? downOverlay : upOverlay
                other.hide()
                overlay.update(direction: direction, action: action,
                               progress: output.progress, locked: output.locked,
                               translationY: translation.height)
                if output.lockEdge && settings.hapticsEnabled {
                    haptics.impactOccurred()
                }
            }

        case .ended:
            if let direction = engine.finish() {
                triggerAction(direction: direction, exitEdge: direction == .up ? .top : .bottom)
            } else {
                hideOverlays()
                collectionView.isScrollEnabled = true
            }

        case .cancelled, .failed:
            engine.cancel()
            hideOverlays()
            collectionView.isScrollEnabled = true

        default:
            break
        }
    }

    private func hideOverlays() {
        upOverlay.hide()
        downOverlay.hide()
    }

    // MARK: - 动作执行管线

    private func triggerAction(direction: SwipeDirection, exitEdge: PhotoDeskCore.VerticalEdge?) {
        let action = viewModel.action(for: direction)
        executeAction(action, direction: direction, exitEdge: exitEdge)
    }

    /// 统一执行入口（手势 / 无障碍按钮 / 菜单共用）。
    /// docs/09 D03/D04：删除/隐藏不弹 App 内确认——直接会话暂存 + 飞出 + 补位。
    private func executeAction(_ action: SwipeAction, direction: SwipeDirection, exitEdge: PhotoDeskCore.VerticalEdge?) {
        hideOverlays()
        collectionView.isScrollEnabled = true

        guard action != .none else { return }
        if action == .dismiss {
            closeTapped()
            return
        }

        switch action {
        case .moveToRecentlyDeleted, .hide:
            // M13 P1：缩放事务与删除事务互斥。活跃期入队（不是丢弃），idle 后由 cell 回调串行 drain。
            guard !ViewerGesturePolicy.shouldQueueRemoval(cell: currentCellZoomState()) else {
                pendingRemovalActions.append((action, exitEdge))
                logPendingDeleteCount("queue \(action) idx=\(viewModel.currentIndex)")
                ViewerTrace.log("action-queued-zooming \(action) idx=\(viewModel.currentIndex) pending=\(pendingRemovalActions.count)")
                return
            }
            performStaged(action: action, exitEdge: exitEdge)
        default:
            perform(action: action, direction: direction)
        }
    }

    /// cell 手势回 idle 后回调；只做 @MainActor 串行排空，不读任何几何（docs/25 §4.6）。
    private func wireZoomIdleIfNeeded(_ cell: ZoomableImageCell) {
        cell.setZoomTransactionIdleHandler { [weak self] in
            Task { @MainActor in
                self?.schedulePendingRemovalDrain()
            }
        }
        // 缩放交互期间禁用翻页滚动；交互结束且已回 1× 时恢复（放大静止态仍保持禁用）
        cell.syncInteraction = { [weak self] interacting in
            guard let self else { return }
            if interacting {
                if self.collectionView.isScrollEnabled { self.collectionView.isScrollEnabled = false }
            } else {
                let scale = self.currentCellZoomState()?.zoomScale ?? ZoomableImageCell.minZoomScale
                if scale <= 1.01 && !self.collectionView.isScrollEnabled {
                    self.collectionView.isScrollEnabled = true
                }
            }
        }
    }

    /// 把 drain 排到下一个 MainActor 执行片：与当帧 CATransaction 几何提交严格错开。
    @MainActor
    private func schedulePendingRemovalDrain() {
        guard !pendingRemovalActions.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.drainPendingRemovalActions()
        }
    }

    /// 当前页 cell 的缩放状态快照（B1 互斥判定信号源；无 cell = nil）
    private func currentCellZoomState() -> ViewerGesturePolicy.CellState? {
        (collectionView.cellForItem(at: IndexPath(item: viewModel.currentIndex, section: 0))
            as? ZoomableImageCell)?.zoomState
    }

    /// M13 P1：cell 几何事务回 idle 时串行 drain 删除/隐藏队列。
    /// drain 只在 geometryState==idle 且非 isZooming 时执行，绝不和 CATransaction 几何提交 /
    /// cell transform 写入 / performBatchUpdates 同帧；每个 batch completion 后再消费下一个动作。
    @MainActor
    private func drainPendingRemovalActions() {
        guard !isRemovalInFlight,
              ViewerGesturePolicy.allowsQueuedRemovalDrain(cell: currentCellZoomState()),
              let next = pendingRemovalActions.first else { return }
        // 事务真正启动后才出队：避免 performStaged 的二次门禁拒绝时把用户动作永久丢弃。
        guard performStaged(action: next.0, exitEdge: next.1, fromQueue: true) else { return }
        pendingRemovalActions.removeFirst()
        logPendingDeleteCount("drain \(next.0) idx=\(viewModel.currentIndex)")
    }

    /// Release 面包屑：pendingDeleteCount / pendingHideCount / 队列长度；只写本地，不含照片像素。
    private func logPendingDeleteCount(_ event: String) {
        let session = AppContainer.shared.reviewSession
        ViewerTrace.log("\(event) pendingDeleteCount=\(session.pendingDeleteCount) pendingHideCount=\(session.pendingHideCount) queue=\(pendingRemovalActions.count)")
    }

    /// 删除事务（docs/13 S12）：plan → snapshot 飞出（并行）→ 同一 runloop 内
    /// performBatchUpdates { commitRemoval + deleteItems } → completion 定位/关闭。
    /// isRemovalInFlight 串行化：事务期间忽略新动作（最多丢一次滑动，好过崩溃）。
    /// M13 P1：缩放事务活跃期的动作已由 executeAction 入队，本方法只在 idle 后按队列调用。
    @discardableResult
    private func performStaged(action: SwipeAction, exitEdge: PhotoDeskCore.VerticalEdge?, fromQueue: Bool = false) -> Bool {
        let removalAllowed = fromQueue
            ? ViewerGesturePolicy.allowsQueuedRemovalDrain(cell: currentCellZoomState())
            : ViewerGesturePolicy.allowsRemovalTransaction(cell: currentCellZoomState())
        guard !isRemovalInFlight,
              removalAllowed,
              let item = viewModel.current,
              let staged = viewModel.planRemoval(action: action, forItemID: item.id, exitEdge: exitEdge) else { return false }
        isRemovalInFlight = true
        ViewerTrace.log("stage \(action) idx=\(staged.removedIndex) count=\(viewModel.items.count)")

        // snapshot 飞出：真实 cell 不再参与动画（docs/13 S12 根因 1/2——cell 冻结与 batch 更新错位）
        let removedIndexPath = IndexPath(item: staged.removedIndex, section: 0)
        if usesMotion, let cell = collectionView.cellForItem(at: removedIndexPath),
           let snapshot = cell.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = collectionView.convert(cell.frame, to: view)
            view.addSubview(snapshot)
            let flyDistance = exitEdge == .top ? -view.bounds.height : view.bounds.height
            UIView.animate(withDuration: DSMotion.flyOutDuration,
                           delay: 0,
                           usingSpringWithDamping: DSMotion.springDamping,
                           initialSpringVelocity: DSMotion.springVelocity,
                           options: [.beginFromCurrentState],
                           animations: {
                snapshot.transform = CGAffineTransform(translationX: 0, y: flyDistance)
                snapshot.alpha = 0
            }, completion: { _ in
                snapshot.removeFromSuperview()
            })
        }

        showToast(text: staged.toastText,
                  icon: ActionOverlayView.symbol(for: action),
                  allowUndo: true)

        // 同一 runloop：数据源变更与 cell 删除在同一事务（不变量 I1：block 外 items.count == numberOfItems）
        collectionView.performBatchUpdates {
            let result = viewModel.commitRemoval(staged)
            collectionView.deleteItems(at: [removedIndexPath])
            pendingRemovalResult = result
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isRemovalInFlight = false
            guard let result = self.pendingRemovalResult else { return }
            self.pendingRemovalResult = nil
            ViewerTrace.log("settle next=\(result.nextIndex.map(String.init) ?? "nil") close=\(result.shouldClose)")
            if result.shouldClose {
                self.closeTapped()   // 列表删空：关闭查看器（docs/09 D02）
                return
            }
            guard let next = result.nextIndex, next < self.viewModel.items.count else { return }
            self.viewModel.updateIndex(next)
            self.collectionView.layoutIfNeeded()
            self.scrollTo(index: next, animated: false)
            self.applyEntryAnimation(edge: staged.plan.entryEdge, index: next)
            self.refreshFilmStrip(current: next)
            self.refreshChrome()   // 顶部待处理计数 +1（docs/09 D16）
            self.logPendingDeleteCount("settle idx=\(next)")
            self.prefetchAround(index: next)
            self.refreshDebugBanner()
            self.schedulePendingRemovalDrain()   // 队列仍有动作时，等下一个 batch completion 再消费
        }
        #if DEBUG
        updateDebugLabel("staged:\(action) idx=\(staged.removedIndex)")
        #endif
        return true
    }

    /// 补位进入动画：下一张从 entryEdge 以 0.96→1.0 缩放 / 16pt 位移进入（Reduce Motion 降级）
    private func applyEntryAnimation(edge: PhotoDeskCore.VerticalEdge?, index: Int) {
        guard usesMotion, let edge else { return }
        guard let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) else { return }
        let offset: CGFloat = edge == .top ? -16 : 16
        cell.transform = CGAffineTransform(translationX: 0, y: offset).scaledBy(x: 0.96, y: 0.96)
        cell.alpha = 0.4
        UIView.animate(withDuration: DSMotion.fadeDuration, delay: 0, options: [.curveEaseOut]) {
            cell.transform = .identity
            cell.alpha = 1
        }
    }

    /// staged 撤销（恢复 item）：全量重载集合视图并定位回恢复位置
    private func reloadAfterRestore() {
        collectionView.reloadData()
        let index = max(0, min(viewModel.currentIndex, max(0, viewModel.items.count - 1)))
        scrollTo(index: index, animated: false)
        refreshFilmStrip(current: index)
        refreshChrome()
        refreshDebugBanner()
    }

    private func perform(action: SwipeAction, direction: SwipeDirection) {
        guard let item = viewModel.current else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.viewModel.execute(action, for: item)
            #if DEBUG
            switch outcome {
            case .success: self.updateDebugLabel("exec:\(action) ✓")
            case .rejected(let message): self.updateDebugLabel("exec:\(action) ✗ \(message)")
            }
            #endif
            switch outcome {
            case .success(_, let toastText, let undoKind):
                // 收藏/取消收藏/取消隐藏：不前进（docs/09 §2.4），本地状态已更新
                self.refreshChrome()
                self.showToast(text: toastText,
                               icon: ActionOverlayView.symbol(for: action),
                               allowUndo: undoKind != nil)
                #if DEBUG
                self.updateDebugLabel("exec:\(action) ✓ \(self.toast.debugState)")
                #endif

            case .rejected(let message):
                guard !message.isEmpty else { return }
                self.showToast(text: message, icon: "info.circle", allowUndo: false)
            }
        }
    }

    /// 飞出动画已由 performStaged 的 snapshot 覆盖（docs/13 S12：真实 cell 不参与飞出）

    private var usesMotion: Bool {
        !(UIAccessibility.isReduceMotionEnabled && settings.respectReduceMotion)
    }

    // MARK: - Toast / 撤销

    private func showToast(text: String, icon: String, allowUndo: Bool) {
        // staged 撤销走 undoStaged（零 PhotoKit 写）；即时写撤销走 UndoCenter。
        // R04：到 0 由唯一时钟驱动统一触发——staged 路径撤销入口失效（expireStaged）
        let isStaged = viewModel.hasUndoableStaged
        toast.show(icon: icon,
                   text: text + (allowUndo ? " · 撤销" : ""),
                   duration: settings.undoWindow,
                   allowUndo: allowUndo,
                   onUndo: { [weak self] in
            guard let self else { return }
            if isStaged {
                self.viewModel.undoStaged()
            } else {
                Task { await self.viewModel.undoLast() }
            }
        },
                   onExpire: isStaged ? { [weak self] in
            self?.viewModel.expireStaged()
        } : nil,
                   onDismissFinished: nil)
        scheduleChromeHide()
    }

    // MARK: - Chrome（3 秒无操作淡出，docs/04 §3.2）

    @objc private func viewTapped(_ gesture: UITapGestureRecognizer) {
        // 视频点击暂停/继续（docs/09 D15）：点在视频 cell 上时切换播放，不切换 chrome
        let point = gesture.location(in: view)
        if let indexPath = collectionView.indexPathForItem(at: collectionView.convert(point, from: view)),
           let cell = collectionView.cellForItem(at: indexPath) as? VideoCell {
            cell.togglePlayback()
            return
        }
        setChrome(visible: !chromeVisible)
    }
    /// UILongPressGestureRecognizer 的 location
    private var longPressLocation: CGPoint?

    @objc private func viewLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        longPressLocation = gesture.location(in: view)
        presentActionMenu()
    }

    /// 长按操作菜单（docs/09 D15）：收藏/隐藏/移到最近删除/加相簿/分享/信息/编辑
    private func presentActionMenu() {
        guard viewModel.current != nil else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let addItem: (String, SwipeAction) -> Void = { [weak self] title, action in
            alert.addAction(UIAlertAction(title: title, style: action == .moveToRecentlyDeleted ? .destructive : .default) { _ in
                self?.executeAction(action, direction: .down, exitEdge: nil)
            })
        }
        addItem("收藏", .favorite)
        addItem("隐藏", .hide)
        addItem("移到最近删除", .moveToRecentlyDeleted)
        alert.addAction(UIAlertAction(title: "加入相簿…", style: .default) { [weak self] _ in
            self?.addToAlbumTapped()
        })
        alert.addAction(UIAlertAction(title: "分享…", style: .default) { [weak self] _ in
            self?.shareCurrent()
        })
        alert.addAction(UIAlertAction(title: "查看信息", style: .default) { [weak self] _ in
            self?.infoTapped()
        })
        alert.addAction(UIAlertAction(title: "旋转 / 编辑", style: .default) { [weak self] _ in
            self?.rotateTapped()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(origin: longPressLocation ?? view.center, size: .zero)
        }
        present(alert, animated: true)
    }

    private func setChrome(visible: Bool) {
        chromeVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        let animate = usesMotion
        if animate {
            UIView.animate(withDuration: DSMotion.fadeDuration, delay: 0, options: DSMotion.fadeOptions) {
                self.topBar.alpha = alpha
                self.filmStrip.alpha = alpha
            }
        } else {
            topBar.alpha = alpha
            filmStrip.alpha = alpha
        }
        if visible {
            scheduleChromeHide()
        } else {
            chromeTimer?.invalidate()
            chromeTimer = nil
        }
    }

    private func scheduleChromeHide() {
        // UI 测试钩子（docs/09 Phase 0）：禁用 chrome 自动淡出，保证顶栏徽标可点（仅 DEBUG + 启动参数）
        #if DEBUG
        if UITestHooks.enabled("-uiTestingKeepChrome") { return }
        #endif
        chromeTimer?.invalidate()
        chromeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.setChrome(visible: false)
            }
        }
    }

    private var favoriteIconName: String {
        viewModel.isFavoriteCurrent ? "heart.fill" : "heart"
    }

    private func refreshChrome() {
        favoriteButton.image = UIImage(systemName: favoriteIconName)
        refreshSessionBadge()
    }

    /// 顶部待处理徽标（docs/09 D16）：待删除 N / 待隐藏 M，点击打开整理回顾
    private func refreshSessionBadge() {
        let session = AppContainer.shared.reviewSession
        let deletes = session.pendingDeleteCount
        let hides = session.pendingHideCount
        let item = topBarItems.first { $0.accessibilityIdentifier == "SessionBadge" }
        guard let item else { return }
        item.width = DSTouch.minimum
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

    @objc private func sessionBadgeTapped() {
        let review = SessionReviewView(session: AppContainer.shared.reviewSession,
                                       pipeline: pipeline,
                                       settings: settings) { [weak self] in
            self?.dismiss(animated: true)
            self?.refreshChrome()
        }
        let host = UIHostingController(rootView: review)
        host.view.backgroundColor = DSColor.bgViewer
        present(host, animated: true)
    }

    // MARK: - 按钮

    @objc private func closeTapped() {
        ViewerTrace.log("close idx=\(viewModel.currentIndex) count=\(viewModel.items.count)")
        undoCenter.dismissActive()
        onClose?()
        dismiss(animated: usesMotion)
    }

    @objc private func favoriteTapped() {
        guard let item = viewModel.current else { return }
        let action: SwipeAction = item.isFavorite ? .unfavorite : .favorite
        perform(action: action, direction: item.isFavorite ? .down : .up)
    }

    @objc private func infoTapped() {
        guard let item = viewModel.current else { return }
        let host = UIHostingController(rootView: NavigationView {
            MetadataView(item: item)
        }.navigationViewStyle(.stack))
        present(host, animated: usesMotion)
    }

    /// 旋转/编辑（docs/09 D15：rotate 接入编辑器——旋转在编辑器内完成）
    private func rotateTapped() {
        guard let item = viewModel.current else { return }
        openEditor(for: item)
    }

    /// 加入相簿（docs/09 D15：addToAlbum 接入——输入相簿名创建并加入）
    private func addToAlbumTapped() {
        guard let item = viewModel.current else { return }
        let alert = UIAlertController(title: "加入相簿",
                                      message: "将这张照片加入新相簿",
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "相簿名称" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建并加入", style: .default) { [weak self] _ in
            guard let title = alert.textFields?.first?.text, !title.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let albumID = try await AppContainer.shared.photoWriter.createAlbum(title: title)
                    try await AppContainer.shared.photoWriter.add(ids: [item.id], toAlbum: albumID)
                    self.showToast(text: "已加入相簿", icon: "folder.badge.plus", allowUndo: false)
                } catch {
                    self.showToast(text: "操作失败：\(error.localizedDescription)",
                                   icon: "info.circle", allowUndo: false)
                }
            }
        })
        present(alert, animated: true)
    }

    @objc private func moreTapped() {
        guard let item = viewModel.current else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "编辑", style: .default) { [weak self] _ in
            self?.openEditor(for: item)
        })
        alert.addAction(UIAlertAction(title: "导出…", style: .default) { [weak self] _ in
            self?.openExport(for: item)
        })
        alert.addAction(UIAlertAction(title: "分享…", style: .default) { [weak self] _ in
            self?.shareCurrent()
        })
        alert.addAction(UIAlertAction(title: "加入相簿…", style: .default) { [weak self] _ in
            self?.addToAlbumTapped()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = moreButtonItem
        }
        present(alert, animated: true)
    }

    /// 编辑器（UIKit 全屏；关闭回调刷新预览与收藏状态）
    private func openEditor(for item: PhotoItem) {
        let editor = EditorViewController(viewModel: AppContainer.shared.makeEditorViewModel(item: item),
                                          item: item)
        editor.onClose = { [weak self] in
            self?.viewModel.updateIndex(self?.viewModel.currentIndex ?? 0)
        }
        editor.modalPresentationStyle = .fullScreen
        present(editor, animated: usesMotion)
    }

    /// 导出页（SwiftUI Form；viewModel 由组合根装配）
    private func openExport(for item: PhotoItem) {
        let host = UIHostingController(rootView: NavigationView {
            ExportView(viewModel: AppContainer.shared.makeExportViewModel(item: item))
        }.navigationViewStyle(.stack))
        present(host, animated: usesMotion)
    }

    /// 分享（iCloud 原件自动下载后弹出系统分享面板）
    private func shareCurrent() {
        guard let item = viewModel.current else { return }
        let more = moreButtonItem
        Task { @MainActor in
            do {
                let url = try await AppContainer.shared.photoWriter.requestInputURL(assetID: item.id)
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.barButtonItem = more
                present(share, animated: true)
            } catch {
                showToast(text: error.localizedDescription, icon: "info.circle", allowUndo: false)
            }
        }
    }

    // MARK: - 翻页与图片加载

    private func scrollTo(index: Int, animated: Bool = true) {
        guard index >= 0, index < viewModel.items.count else { return }
        // 翻页/跳转前重置旧页缩放（docs/25 §4.6：翻页后无残留缩放）
        if let oldCell = collectionView.cellForItem(at: IndexPath(item: viewModel.currentIndex, section: 0)) as? ZoomableImageCell {
            oldCell.resetZoom()
        }
        isProgrammaticScroll = true
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0),
                                    at: .centeredHorizontally,
                                    animated: animated && usesMotion)
        isProgrammaticScroll = false
        filmStrip.highlight(index: index, centerIfNeeded: true)
        refreshChrome()
        refreshDebugBanner()
    }

    /// 预取当前 index 后 3 张 + 前 1 张（docs/09 D02：补位不白屏；docs/13 S02：100ms 防抖 + 边界保护）
    private func prefetchAround(index: Int) {
        prefetchDebounceTask?.cancel()
        prefetchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.prefetchNow(index: index) }
        }
    }

    private func prefetchNow(index: Int) {
        let items = viewModel.items
        guard !items.isEmpty, items.indices.contains(index) else { return }
        let forward = items[(index + 1)..<min(index + 4, items.count)].map(\.id)
        let backward = index > 0 ? [items[index - 1].id] : []
        let ids = forward + backward
        guard !ids.isEmpty else { return }
        let size = collectionView.bounds.size
        let pixel = CGSize(width: size.width * UIScreen.main.scale,
                           height: size.height * UIScreen.main.scale)
        pipeline.prefetch(ids: Array(ids), size: pixel)
    }

    private func refreshFilmStrip(current index: Int) {
        filmStrip.reload(ids: viewModel.items.map(\.id),
                         currentIndex: index,
                         pipeline: pipeline) { [weak self] target in
            self?.scrollTo(index: target)
        }
    }

    /// 大图加载：Task 挂到 cell（离屏/复用即取消，docs/13 S08）；在途计数供 DEBUG 横幅。
    /// M12 A2：inCloud 回传 → 占位 + 下载按钮（不再纯黑无自救）。
    private func loadImage(for item: PhotoItem, at index: Int, cell: ZoomableImageCell) {
        // cell 级 token（docs/09 D02：回填前校验 cell.itemID 与 item.id 一致且 token 未过期）
        let token = cell.beginLoad()
        // iCloud-only 未下载：保持占位态，等用户点「下载」（docs/03 §5.8）
        guard !item.isCloudOnly else { return }
        ViewerTrace.log("loadStart idx=\(index) id=\(item.id.prefix(8))")
        inflightLoadCount += 1
        cell.loadTask = Task { [weak self, weak cell] in
            guard let self else { return }
            defer { self.inflightLoadCount = max(0, self.inflightLoadCount - 1) }
            let result = await self.pipeline.fullImageWithState(for: item.id, progress: { fraction in
                Task { @MainActor in
                    cell?.updateDownloadProgress(fraction)
                }
            }, allowNetwork: false)
            ViewerTrace.log("loadEnd idx=\(index) ok=\(result.image != nil) cloud=\(result.isInCloud)")
            guard !Task.isCancelled, let cell, cell.itemID == item.id, cell.matches(token: token) else { return }
            if let image = result.image {
                cell.applyDownloadedImage(image)
                self.refreshDebugBanner()
            } else if result.isInCloud {
                // 禁网 + iCloud-only：占位 + 下载入口（A2 自救路径）
                cell.showCloudPlaceholder()
                self.refreshDebugBanner()
            } else {
                // 坏图/资源已不可用：中文占位 + 重试（不再纯黑）
                cell.showFailurePlaceholder { [weak self, weak cell] in
                    guard let self, let cell else { return }
                    self.loadImage(for: item, at: index, cell: cell)
                }
                self.refreshDebugBanner()
                ViewerTrace.log("loadFail idx=\(index) id=\(item.id.prefix(8))")
            }
        }
    }
}

// MARK: - DataSource / Delegate

extension ViewerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    /// 越界分支的空态条目（已 configure 的占位 cell 用；不进入任何业务路径）
    static let emptyItem = PhotoItem(id: "",
                                     mediaType: .image,
                                     mediaSubtypes: [],
                                     creationDate: nil,
                                     modificationDate: nil,
                                     pixelWidth: 1,
                                     pixelHeight: 1,
                                     duration: 0,
                                     isFavorite: false,
                                     isHidden: false,
                                     location: nil,
                                     burstIdentifier: nil,
                                     isCloudOnly: false)

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        max(0, viewModel.items.count)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // 边界保护（docs/13 S08/S12：删除事务窗口内可能收到旧 index 的请求）。
        // M12 附带：越界分支返回已 configure 的空态 cell（旧版返回未配置 cell → 携带复用前的旧图/旧交互态）
        guard indexPath.item < viewModel.items.count else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZoomableImageCell.reuseID,
                                                          for: indexPath)
            if let imageCell = cell as? ZoomableImageCell {
                imageCell.configure(item: Self.emptyItem, image: nil)
                wireZoomIdleIfNeeded(imageCell)
            }
            return cell
        }
        let item = viewModel.items[indexPath.item]
        if item.mediaType == .video {
            // 视频资产在 willDisplay 拉取并起播（离屏停止）
            return collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseID,
                                                      for: indexPath)
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZoomableImageCell.reuseID,
                                                      for: indexPath)
        guard let imageCell = cell as? ZoomableImageCell else { return cell }
        imageCell.configure(item: item, image: nil)
        wireZoomIdleIfNeeded(imageCell)
        schedulePendingRemovalDrain()
        imageCell.setDownloadHandler { [weak self, weak imageCell] id in
            guard let self, let imageCell else { return }
            self.downloadFromCloud(id: id, cell: imageCell)
        }
        loadImage(for: item, at: indexPath.item, cell: imageCell)
        return imageCell
    }

    private func downloadFromCloud(id: String, cell: ZoomableImageCell) {
        let token = cell.beginLoad()
        inflightLoadCount += 1
        cell.loadTask = Task { [weak self, weak cell] in
            guard let self else { return }
            defer { self.inflightLoadCount = max(0, self.inflightLoadCount - 1) }
            let result = await self.pipeline.fullImageWithState(for: id, progress: { fraction in
                Task { @MainActor in cell?.updateDownloadProgress(fraction) }
            }, allowNetwork: true)
            ViewerTrace.log("downloadEnd id=\(id.prefix(8)) ok=\(result.image != nil)")
            guard !Task.isCancelled, let cell, cell.itemID == id, cell.matches(token: token) else { return }
            if let image = result.image {
                cell.applyDownloadedImage(image)
            } else {
                // 仍未拿到（下载失败/仍受限）：保持占位态，用户可重试
                cell.showCloudPlaceholder()
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        guard indexPath.item < viewModel.items.count,
              let videoCell = cell as? VideoCell,
              let item = viewModel.items[safe: indexPath.item],
              item.mediaType == .video else { return }
        videoCell.loadVideo(item: item) { [weak self] in
            guard let asset = await self?.pipeline.videoAsset(for: item.id) else { return nil }
            return asset.asset
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? VideoCell)?.stopPlayback()
        // 图片 cell 离屏取消在途加载（docs/13 S08：旧实现只处理 VideoCell）
        (cell as? ZoomableImageCell)?.cancelLoad()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // D01：只在用户手势（拖拽/减速）时更新 index；程序化滚动一律屏蔽
        guard !isProgrammaticScroll,
              scrollView.isTracking || scrollView.isDecelerating,
              viewModel.items.count > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
        let clamped = max(0, min(page, viewModel.items.count - 1))
        if clamped != viewModel.currentIndex {
            ViewerTrace.log("page idx=\(clamped) count=\(viewModel.items.count)")
            viewModel.updateIndex(clamped)
            filmStrip.highlight(index: clamped, centerIfNeeded: true)
            refreshChrome()
            prefetchAround(index: clamped)
            refreshDebugBanner()
        }
    }
}

// MARK: - 预取（docs/09 D02：后 3 张）

extension ViewerViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let ids = indexPaths.compactMap { viewModel.items[safe: $0.item]?.id }
        guard !ids.isEmpty else { return }
        let size = collectionView.bounds.size
        let pixel = CGSize(width: size.width * UIScreen.main.scale,
                           height: size.height * UIScreen.main.scale)
        pipeline.prefetch(ids: ids, size: pixel)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        indexPaths.compactMap { viewModel.items[safe: $0.item]?.id }.forEach { pipeline.cancel(id: $0) }
    }
}

// MARK: - 手势冲突（docs/03 §5.1）

extension ViewerViewController: UIGestureRecognizerDelegate {
    /// M12 B1：pan 开始判定收口到 ViewerGesturePolicy（放大 > 1.01 / 捏合中 / 回弹宽限 / 双指 /
    /// 无障碍关闭 → 一律拒绝；旧版 isZoomed 只在起始判一次且双指分支是死代码）
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        return ViewerGesturePolicy.shouldPanBegin(
            gesturesEnabled: settings.gesturesEnabled,
            numberOfTouches: pan.numberOfTouches,
            cell: currentCellZoomState())
    }

    /// M12 B1：与捏合互斥——旧版无条件 true → 捏合两指中的单指位移触发垂直锁 →
    /// 删除事务在 UIScrollView 缩放事务中执行 → CALayer position NaN 崩溃
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if other is UIPinchGestureRecognizer { return false }
        if let otherPan = other as? UIPanGestureRecognizer, otherPan.numberOfTouches >= 2 { return false }
        // 与分页手势同时识别，靠 SwipeGestureEngine 的方向锁裁决（docs/03 §5.1）
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
