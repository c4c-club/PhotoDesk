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
        // D01：首次拿到有效宽度后按当前 index 定位（contentOffset 直设，不触发 didScroll 写回）
        if needsInitialPositioning, width > 0, !collectionView.isHidden {
            needsInitialPositioning = false
            positionAtCurrentIndex()
        }
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
        #if DEBUG
        updateDebugBanner(page: index)
        #endif
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
        // UI 测试（docs/09 D01）：横幅可查询，label 内含 "id=<assetID> idx=<n>"
        label.accessibilityIdentifier = "Viewer-Debug"
        return label
    }()

    private func updateDebugLabel(_ text: String) {
        debugLabel.text = text
    }

    /// 带定位信息的横幅文本（id / idx 供 UI 测试断言 assetID 一致性）
    private func updateDebugBanner(page index: Int) {
        guard let item = viewModel.items[safe: index] else { return }
        updateDebugLabel("id=\(item.id) idx=\(index)")
    }
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

        // 点击屏幕切换 chrome；双击缩放不触发 chrome（D15）：单击 require 双击失败
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapNoop))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(viewTapped(_:)))
        tap.require(toFail: doubleTap)
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

    @objc private func doubleTapNoop() {}   // 占位：只为让单击等待双击失败（缩放由 cell 处理）

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
            performStaged(action: action, exitEdge: exitEdge)
        default:
            perform(action: action, direction: direction)
        }
    }

    /// 会话暂存路径（docs/09 D16）：同步入队 → 飞出 → 批量更新删除 cell → 按补位计划进入
    private func performStaged(action: SwipeAction, exitEdge: PhotoDeskCore.VerticalEdge?) {
        guard let item = viewModel.current else { return }
        guard let staged = viewModel.stage(action, forItemID: item.id, exitEdge: exitEdge) else { return }
        ViewerTrace.log("stage \(action) idx=\(staged.removedIndex) count=\(viewModel.items.count)")

        flyOut(direction: exitEdge == .bottom ? .down : .up,
               index: staged.removedIndex) { [weak self] in
            guard let self else { return }
            self.applyRemoval(staged: staged)
        }
        showToast(text: staged.toastText,
                  icon: ActionOverlayView.symbol(for: action),
                  allowUndo: true)
        #if DEBUG
        updateDebugLabel("staged:\(action) n=\(staged.removedIndex)")
        #endif
    }

    /// performBatchUpdates 删除 cell → 按计划滚到 nextIndex → entry 动画 → 刷新胶片条
    private func applyRemoval(staged: ViewerViewModel.StagedOutcome) {
        ViewerTrace.log("commit idx=\(staged.removedIndex) next=\(staged.plan.nextIndex.map(String.init) ?? "nil") close=\(staged.plan.shouldClose)")
        let removedIndexPath = IndexPath(item: staged.removedIndex, section: 0)
        collectionView.performBatchUpdates {
            collectionView.deleteItems(at: [removedIndexPath])
        } completion: { [weak self] _ in
            guard let self else { return }
            if staged.plan.shouldClose {
                self.closeTapped()   // 列表删空：关闭查看器（docs/09 D02）
                return
            }
            guard let next = staged.plan.nextIndex else { return }
            self.viewModel.updateIndex(next)
            self.scrollTo(index: next, animated: false)
            self.applyEntryAnimation(edge: staged.plan.entryEdge, index: next)
            self.refreshFilmStrip(current: next)
            self.refreshChrome()   // 顶部待处理计数 +1（docs/09 D16）
            self.prefetchAround(index: next)
            #if DEBUG
            self.updateDebugBanner(page: next)
            #endif
        }
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
        #if DEBUG
        updateDebugBanner(page: index)
        #endif
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

    /// 飞出动画（目标 cell 在移除生效前冻结，docs/09 D02；index = 被移除条目原 index）
    private func flyOut(direction: SwipeDirection, index: Int, completion: @escaping () -> Void) {
        let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
        let flyDistance = direction == .up ? -view.bounds.height : view.bounds.height

        guard usesMotion, let cell else {
            completion()
            return
        }
        UIView.animate(withDuration: DSMotion.flyOutDuration,
                       delay: 0,
                       usingSpringWithDamping: DSMotion.springDamping,
                       initialSpringVelocity: DSMotion.springVelocity,
                       options: [.beginFromCurrentState],
                       animations: {
            cell.transform = CGAffineTransform(translationX: 0, y: flyDistance)
            cell.alpha = 0
        }, completion: { _ in
            cell.transform = .identity
            cell.alpha = 1
            completion()
        })
    }

    private var usesMotion: Bool {
        !(UIAccessibility.isReduceMotionEnabled && settings.respectReduceMotion)
    }

    // MARK: - Toast / 撤销

    private func showToast(text: String, icon: String, allowUndo: Bool) {
        // staged 撤销走 undoStaged（零 PhotoKit 写）；即时写撤销走 UndoCenter
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
        isProgrammaticScroll = true
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0),
                                    at: .centeredHorizontally,
                                    animated: animated && usesMotion)
        isProgrammaticScroll = false
        filmStrip.highlight(index: index, centerIfNeeded: true)
        refreshChrome()
        #if DEBUG
        updateDebugBanner(page: index)
        #endif
    }

    /// 预取当前 index 后 3 张 + 前 1 张（docs/09 D02：补位不白屏）
    private func prefetchAround(index: Int) {
        let ids = viewModel.items[index...].prefix(4).dropFirst().prefix(3).map(\.id)
            + viewModel.items[..<index].suffix(1).map(\.id)
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

    private func loadImage(for item: PhotoItem, at index: Int, cell: ZoomableImageCell) {
        // cell 级 token（docs/09 D02：回填前校验 cell.itemID 与 item.id 一致且 token 未过期）
        let token = cell.beginLoad()
        ViewerTrace.log("loadStart idx=\(index) id=\(item.id.prefix(8))")
        // iCloud-only 未下载：保持占位态，等用户点「下载」（docs/03 §5.8）
        guard !item.isCloudOnly else { return }
        Task { [weak self, weak cell] in
            guard let self else { return }
            let image = await self.pipeline.fullImage(for: item.id, progress: { fraction in
                Task { @MainActor in
                    cell?.updateDownloadProgress(fraction)
                }
            }, allowNetwork: false)
            ViewerTrace.log("loadEnd idx=\(index) ok=\(image != nil)")
            guard let cell, cell.itemID == item.id, cell.matches(token: token) else { return }
            if let image {
                cell.applyDownloadedImage(image)
            }
        }
    }
}

// MARK: - DataSource / Delegate

extension ViewerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
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
        imageCell.setDownloadHandler { [weak self, weak imageCell] id in
            guard let self, let imageCell else { return }
            self.downloadFromCloud(id: id, cell: imageCell)
        }
        loadImage(for: item, at: indexPath.item, cell: imageCell)
        return imageCell
    }

    private func downloadFromCloud(id: String, cell: ZoomableImageCell) {
        let token = cell.beginLoad()
        Task { [weak cell] in
            let image = await self.pipeline.fullImage(for: id, progress: { fraction in
                Task { @MainActor in cell?.updateDownloadProgress(fraction) }
            }, allowNetwork: true)
            guard let cell, cell.itemID == id, cell.matches(token: token) else { return }
            if let image {
                cell.applyDownloadedImage(image)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        guard let videoCell = cell as? VideoCell,
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
            #if DEBUG
            updateDebugBanner(page: clamped)
            #endif
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
    /// 放大状态（> 1.01）或双指操作时禁用上下滑（AGENTS.md §7 常见陷阱）
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard settings.gesturesEnabled else { return false }                 // 无障碍：手势总开关关闭
        if pan.numberOfTouches > 1 { return false }                       // 双指 → 捏合
        if let cell = collectionView.cellForItem(
            at: IndexPath(item: viewModel.currentIndex, section: 0)) as? ZoomableImageCell,
           cell.isZoomed {
            return false                                                  // 放大 → 拖动查看
        }
        return true
    }

    /// 与分页手势同时识别，靠 SwipeGestureEngine 的方向锁裁决（docs/03 §5.1）
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
