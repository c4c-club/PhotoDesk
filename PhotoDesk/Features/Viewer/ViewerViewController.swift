// MARK: - 职责说明：全屏浏览 UIKit 分页器（docs/05 M2 任务 2.1/2.4/2.6，docs/03 §5.1）★核心——
// UICollectionView 横向 paging（cell = 屏幕尺寸）；UIPanGestureRecognizer 经 SwipeGestureEngine 判定：
// 垂直 → 图片本体不动、只驱动 ActionOverlay（透明度/缩放/位移），方向锁期间停用分页；水平 → 交还分页器。
// 放大（zoomScale > 1.01）禁用上下滑；锁定触觉；松手 → 确认弹窗（破坏性）→ 飞出（Reduce Motion 降级淡出）
// → 执行 → 撤销栈 → autoAdvance → Toast。顶栏/胶片条 3 秒无操作淡出，点击切换。

import UIKit
import PhotoDeskCore

final class ViewerViewController: UIViewController {
    // MARK: - 依赖

    private let viewModel: ViewerViewModel
    private let pipeline: ImagePipelineProtocol
    private let settings: SettingsStore
    private let undoCenter: UndoCenter

    // MARK: - 手势与浮层

    private lazy var engine = SwipeGestureEngine(config: SwipeGestureEngine.config(
        for: settings.sensitivity, confirmDestructive: settings.confirmDestructive))
    private let upOverlay = ActionOverlayView(frame: .zero)     // 上滑 → 屏幕上方 1/4
    private let downOverlay = ActionOverlayView(frame: .zero)   // 下滑 → 屏幕下方 1/4
    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - UI

    private var collectionView: UICollectionView!
    private let topBar = UIToolbar()
    private let filmStrip = FilmStripView(frame: .zero)
    private let toast = DSToast(frame: .zero)
    private var topBarItems: [UIBarButtonItem] = []
    private var favoriteButton: UIBarButtonItem!
    private var chromeVisible = true
    private var chromeTimer: Timer?
    /// 图片加载 token（翻页竞态防护）
    private var loadTokens: [Int: Int] = [:]

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

        undoCenter.onExpire = { [weak self] _ in
            self?.toast.dismiss()
        }
        viewModel.onUndoApplied = { [weak self] in
            self?.refreshChrome()
            self?.reloadCurrentCell()
        }

        modalPresentationStyle = .fullScreen
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 浮层锚点：上滑 = 上方 1/4，下滑 = 下方 1/4（docs/04 §3.2）——frame 布局（浮层自带 transform，不走约束）
        let width = view.bounds.width
        let height = view.bounds.height
        upOverlay.frame = CGRect(x: 0, y: height * 0.25 - 70, width: width, height: 140)
        upOverlay.setBaseCenter(y: height * 0.25)
        downOverlay.frame = CGRect(x: 0, y: height * 0.75 - 70, width: width, height: 140)
        downOverlay.setBaseCenter(y: height * 0.75)
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
        collectionView.register(ZoomableImageCell.self, forCellWithReuseIdentifier: ZoomableImageCell.reuseID)
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseID)
        view.addSubview(collectionView)

        // 初始定位到起始页（无动画，避免白帧）
        if viewModel.currentIndex > 0 {
            collectionView.scrollToItem(at: IndexPath(item: viewModel.currentIndex, section: 0),
                                        at: .centeredHorizontally, animated: false)
        }
    }

    private func setupOverlays() {
        view.addSubview(upOverlay)
        view.addSubview(downOverlay)
        upOverlay.hide()
        downOverlay.hide()
    }

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.setBackgroundImage(UIImage(), forToolbarPosition: .any)
        topBar.setShadowImage(UIImage(), forToolbarPosition: .any)
        topBar.barTintColor = .clear
        view.addSubview(topBar)

        let close = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                    style: .plain, target: self, action: #selector(closeTapped))
        close.accessibilityLabel = "关闭"
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
        topBarItems = [close, flexibleSpace, favoriteButton, info, more]
        topBar.setItems(topBarItems, animated: false)

        // 点击屏幕切换 chrome 显隐（与双击缩放共存：双击会先触发一次切换，M6 一并优化）
        let tap = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        view.addGestureRecognizer(tap)

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
    }

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
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
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
                triggerAction(direction: direction, translationY: translation.height)
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

    // MARK: - 动作执行管线（docs/03 §5.1 执行流程）

    private func triggerAction(direction: SwipeDirection, translationY: CGFloat) {
        let action = viewModel.action(for: direction)
        hideOverlays()
        collectionView.isScrollEnabled = true

        guard action != .none else { return }
        if action == .dismiss {
            closeTapped()
            return
        }

        let proceed = { [weak self] in
            self?.perform(action: action, direction: direction, translationY: translationY)
        }

        // 破坏性动作二次确认（docs/04 §7 文案；系统对删除另有一次性确认弹窗，无法绕过）
        if action.isDestructive && settings.confirmDestructive {
            presentConfirmation(for: action, onConfirm: proceed)
        } else {
            proceed()
        }
    }

    private func presentConfirmation(for action: SwipeAction, onConfirm: @escaping () -> Void) {
        let title: String
        let message: String
        switch action {
        case .hide, .unhide:
            title = "隐藏这张照片？"
            message = "它不会再出现在照片库，可随时在「已隐藏」中查看。"
        case .moveToRecentlyDeleted:
            title = "移到「最近删除」？"
            message = "照片会在那里保留 30 天，期间随时可以在系统相册恢复，不是永久删除。"
        default:
            title = action.displayName + "？"
            message = ""
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: action.displayName, style: .destructive) { _ in
            onConfirm()
        })
        present(alert, animated: true)
    }

    private func perform(action: SwipeAction, direction: SwipeDirection, translationY: CGFloat) {
        guard let item = viewModel.current else { return }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.viewModel.execute(action, for: item)
            switch outcome {
            case .success(let updated, let toastText, _):
                self.flyOut(direction: direction, action: action) {
                    self.finishAfterAction(updated: updated)
                }
                self.showToast(for: action, allowUndo: true)

            case .rejected(let message):
                guard !message.isEmpty else { return }
                self.showToast(text: message, icon: "info.circle", allowUndo: false)
            }
        }
    }

    private func flyOut(direction: SwipeDirection, action: SwipeAction, completion: @escaping () -> Void) {
        let cell = collectionView.cellForItem(at: IndexPath(item: viewModel.currentIndex, section: 0))
        let flyDistance = direction == .up ? -view.bounds.height : view.bounds.height

        guard usesMotion, let cell else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: [.curveEaseIn, .beginFromCurrentState],
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

    /// 执行成功后：本地状态已在 VM 更新（收藏/隐藏不改图片内容，无需重载大图，缩放状态保留）
    private func finishAfterAction(updated: PhotoItem) {
        refreshChrome()
        if settings.autoAdvance {
            let next = viewModel.nextIndexAfterAction
            viewModel.updateIndex(next)
            scrollTo(index: next)
        }
    }

    // MARK: - Toast / 撤销

    private func showToast(for action: SwipeAction, allowUndo: Bool) {
        guard action != .none else { return }
        toast.show(icon: ActionOverlayView.symbol(for: action),
                   text: action.toastText + (allowUndo ? " · 撤销" : ""),
                   duration: settings.undoWindow,
                   allowUndo: allowUndo && undoCenter.hasActiveEntry,
                   onUndo: { [weak self] in
            Task { await self?.viewModel.undoLast() }
        },
                   onDismissFinished: nil)
        scheduleChromeHide()
    }

    private func showToast(text: String, icon: String, allowUndo: Bool) {
        toast.show(icon: icon, text: text, duration: 2.5, allowUndo: false, onUndo: nil, onDismissFinished: nil)
    }

    // MARK: - Chrome（3 秒无操作淡出，docs/04 §3.2）

    @objc private func viewTapped() {
        setChrome(visible: !chromeVisible)
    }

    private func setChrome(visible: Bool) {
        chromeVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        let animate = usesMotion
        if animate {
            UIView.animate(withDuration: 0.2) {
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
    }

    // MARK: - 按钮

    @objc private func closeTapped() {
        undoCenter.dismissActive()
        onClose?()
        dismiss(animated: usesMotion)
    }

    @objc private func favoriteTapped() {
        guard let item = viewModel.current else { return }
        let action: SwipeAction = item.isFavorite ? .unfavorite : .favorite
        perform(action: action, direction: item.isFavorite ? .down : .up, translationY: 0)
    }

    @objc private func infoTapped() {
        showToast(text: "元数据面板将在 M5 开放", icon: "info.circle", allowUndo: false)
    }

    @objc private func moreTapped() {
        showToast(text: "更多操作将在后续里程碑开放", icon: "ellipsis.circle", allowUndo: false)
    }

    // MARK: - 翻页与图片加载

    private func scrollTo(index: Int) {
        guard index >= 0, index < viewModel.items.count else { return }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0),
                                    at: .centeredHorizontally,
                                    animated: usesMotion)
        filmStrip.highlight(index: index, centerIfNeeded: true)
        refreshChrome()
    }

    private func loadImage(for item: PhotoItem, at index: Int, cell: ZoomableImageCell) {
        let token = (loadTokens[index] ?? 0) + 1
        loadTokens[index] = token
        // iCloud-only 未下载：保持占位态，等用户点「下载」（docs/03 §5.8）
        guard !item.isCloudOnly else { return }
        Task { [weak self] in
            guard let self else { return }
            let image = await self.pipeline.fullImage(for: item.id, progress: { fraction in
                Task { @MainActor in
                    cell.updateDownloadProgress(fraction)
                }
            }, allowNetwork: false)
            guard token == self.loadTokens[index] else { return }
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
        imageCell.setDownloadHandler { [weak self] id in
            self?.downloadFromCloud(id: id, cell: imageCell)
        }
        loadImage(for: item, at: indexPath.item, cell: imageCell)
        return imageCell
    }

    private func downloadFromCloud(id: String, cell: ZoomableImageCell) {
        Task { [weak self] in
            guard let self else { return }
            let image = await self.pipeline.fullImage(for: id, progress: { fraction in
                Task { @MainActor in cell.updateDownloadProgress(fraction) }
            }, allowNetwork: true)
            if let image {
                cell.applyDownloadedImage(image, token: self.loadTokens[self.viewModel.currentIndex] ?? 0)
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
        loadTokens[indexPath.item] = (loadTokens[indexPath.item] ?? 0) + 1   // 使在途回填失效
        (cell as? ZoomableImageCell)?.resetZoom()
        (cell as? VideoCell)?.stopPlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard viewModel.items.count > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
        let clamped = max(0, min(page, viewModel.items.count - 1))
        if clamped != viewModel.currentIndex {
            viewModel.updateIndex(clamped)
            filmStrip.highlight(index: clamped, centerIfNeeded: true)
            refreshChrome()
        }
    }
}

// MARK: - 手势冲突（docs/03 §5.1）

extension ViewerViewController: UIGestureRecognizerDelegate {
    /// 放大状态（> 1.01）或双指操作时禁用上下滑（AGENTS.md §7 常见陷阱）
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
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
