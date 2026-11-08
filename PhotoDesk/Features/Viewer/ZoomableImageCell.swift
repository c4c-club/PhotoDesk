// MARK: - 职责说明：可缩放大图 cell v6（docs/25 §4.5 / M15 P0-1 自管变换重写）——
// 视图层级：contentView → viewportScrollView（纯容器：isScrollEnabled=false、delegate=nil、
// min=max zoom=1，永不调用任何 UIScrollView zoom API）→ imageView。
// 几何模型：imageView.bounds = aspectFit 尺寸；imageView.transform = scale；
// imageView.center = viewport 中心 + translation。全部数值来自 PhotoDeskCore.ZoomTransformPolicy，
// 手势状态机在 ZoomInteractionController。复用/翻页/旋转一律 reset/relayout，无 UIScrollView 重入窗口。

import UIKit
import PhotoDeskCore

/// 纯值诊断快照：VC 只在翻页/定时器/用户操作时读取，手势回调内不回调 VC。
struct ZoomDiagnostics: Equatable {
    var currentScale: CGFloat = ZoomableImageCell.minZoomScale
    var zoomEndCount: Int = 0
    var lastActivity: TimeInterval = 0
}

final class ZoomableImageCell: UICollectionViewCell {
    static let reuseID = "ZoomableImageCell"
    static let minZoomScale: CGFloat = 1
    static let maxZoomScale: CGFloat = 5

    /// 纯容器（UI 测试锚点保留）：不承担缩放，delegate 永远为 nil。
    private let viewportScrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.isScrollEnabled = false
        view.bounces = false
        view.minimumZoomScale = 1
        view.maximumZoomScale = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "Viewer-ZoomScrollView"
        return view
    }()
    /// 显示载体：bounds = aspectFit 尺寸，center/transform 由变换回调写
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        return view
    }()
    /// iCloud 占位（docs/04 §4.13：云图标 + 文案 + 下载按钮 + 环形进度）
    private let cloudBox = UIView()
    private let cloudIcon = UIImageView(image: UIImage(systemName: "icloud"))
    private let cloudLabel: UILabel = {
        let label = UILabel()
        label.text = "这张照片存储在 iCloud，需要下载后才能操作"
        label.font = DSTypography.font(.body)
        label.textColor = DSColor.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    private let downloadButton = UIButton(type: .system)
    private let progressLayer = CAShapeLayer()

    /// 手势状态机（pinch/pan/double-tap 全部挂 viewportScrollView）
    private let zoomController: ZoomInteractionController
    /// 复用/离屏竞态防护
    private var configureToken = 0
    private var onDownloadRequested: ((String) -> Void)?
    private var onRetryRequested: (() -> Void)?
    /// 交互回 idle（手势结束/动画完成）后通知 VC 串行 drain 删除/隐藏队列；不在此处执行 performBatchUpdates。
    var onZoomTransactionDidBecomeIdle: (() -> Void)?
    private(set) var itemID: String?
    /// cell 级加载 token（docs/09 D02：回填前校验 cell 未被复用给另一张照片）
    private(set) var loadToken = 0
    /// VC 挂载的在途加载任务（离屏/复用即取消，docs/13 S08）
    var loadTask: Task<Void, Never>?

    /// 纯值诊断；手势回调内只更新数字。
    private(set) var diagnostics = ZoomDiagnostics()
    /// 当前内容 aspectFit 尺寸（layoutSubviews 维护；与 policy 的 contentWidth/Height 一致）
    private var currentFitSize: CGSize = .zero
    private var lastViewportSize: CGSize = .zero
    private var hasAppliedLayout = false

    override init(frame: CGRect) {
        // controller 需要 viewportView，先建视图再建 controller
        zoomController = ZoomInteractionController(viewportView: viewportScrollView)
        super.init(frame: frame)
        contentView.backgroundColor = DSColor.bgViewer
        contentView.addSubview(viewportScrollView)
        viewportScrollView.addSubview(imageView)
        contentView.addSubview(cloudBox)
        cloudBox.addSubview(cloudIcon)
        cloudBox.addSubview(cloudLabel)
        cloudBox.addSubview(downloadButton)

        cloudBox.isHidden = true
        cloudBox.translatesAutoresizingMaskIntoConstraints = false
        cloudIcon.tintColor = DSColor.textSecondary
        cloudIcon.translatesAutoresizingMaskIntoConstraints = false
        cloudLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.setTitle("下载", for: .normal)
        downloadButton.setTitleColor(DSColor.tint, for: .normal)
        downloadButton.titleLabel?.font = DSTypography.font(.body)
        downloadButton.translatesAutoresizingMaskIntoConstraints = false

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = DSColor.tint.cgColor
        progressLayer.lineWidth = 3
        progressLayer.lineCap = .round
        progressLayer.isHidden = true
        downloadButton.layer.addSublayer(progressLayer)

        downloadButton.addAction(UIAction { [weak self] _ in
            if let retry = self?.onRetryRequested {
                retry()
                return
            }
            guard let id = self?.itemID else { return }
            self?.onDownloadRequested?(id)
        }, for: .touchUpInside)

        zoomController.onTransformChanged = { [weak self] t in
            self?.applyTransform(t)
        }
        zoomController.onInteractionStateChanged = { [weak self] interacting in
            self?.syncInteraction?(interacting)
        }
        zoomController.onInteractionDidEnd = { [weak self] in
            guard let self else { return }
            self.diagnostics.zoomEndCount += 1
            self.diagnostics.lastActivity = CACurrentMediaTime()
            self.diagnostics.currentScale = CGFloat(self.zoomController.scale)
            ViewerTrace.log("zoom=end id=\(self.itemID?.prefix(8) ?? "-") scale=\(String(format: "%.2f", self.diagnostics.currentScale))")
            DispatchQueue.main.async { [weak self] in
                self?.onZoomTransactionDidBecomeIdle?()
            }
        }

        NSLayoutConstraint.activate([
            viewportScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            viewportScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            viewportScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            viewportScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            cloudBox.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cloudBox.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            cloudBox.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            cloudIcon.centerXAnchor.constraint(equalTo: cloudBox.centerXAnchor),
            cloudIcon.topAnchor.constraint(equalTo: cloudBox.topAnchor),
            cloudIcon.widthAnchor.constraint(equalToConstant: 40),
            cloudIcon.heightAnchor.constraint(equalToConstant: 40),
            cloudLabel.topAnchor.constraint(equalTo: cloudIcon.bottomAnchor, constant: 12),
            cloudLabel.leadingAnchor.constraint(equalTo: cloudBox.leadingAnchor),
            cloudLabel.trailingAnchor.constraint(equalTo: cloudBox.trailingAnchor),
            downloadButton.centerXAnchor.constraint(equalTo: cloudBox.centerXAnchor),
            downloadButton.topAnchor.constraint(equalTo: cloudLabel.bottomAnchor, constant: 16),
            downloadButton.widthAnchor.constraint(equalToConstant: 64),
            downloadButton.heightAnchor.constraint(equalToConstant: 44),
            cloudBox.bottomAnchor.constraint(equalTo: downloadButton.bottomAnchor),
        ])
    }

    /// VC 挂载的交互状态回调（缩放交互期间禁用翻页/滚动；结束恢复）
    var syncInteraction: ((Bool) -> Void)?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - 加载 token（docs/09 D02：回填前校验 cell 未被复用给另一张照片）

    /// 开始一次在途加载：token 递增，旧 token 立即失配。
    @discardableResult
    func beginLoad() -> Int {
        loadToken += 1
        return loadToken
    }

    /// 回填前校验：token 未被后续 beginLoad / cancelLoad / configure 递增。
    func matches(token: Int) -> Bool {
        loadToken == token
    }

    /// 离屏/复用取消：在途任务取消 + token 失配（回填即使到达也被丢弃）。
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadToken += 1
        progressLayer.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onZoomTransactionDidBecomeIdle = nil
        syncInteraction = nil
        cancelLoad()
        imageView.image = nil
        imageView.transform = .identity
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        itemID = nil
        diagnostics = ZoomDiagnostics()
        currentFitSize = .zero
        lastViewportSize = .zero
        hasAppliedLayout = false
        zoomController.reset(animated: false)
        refreshInteraction()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        relayoutForViewportChange()
        let center = CGPoint(x: downloadButton.bounds.midX, y: downloadButton.bounds.midY)
        progressLayer.frame = downloadButton.bounds
        progressLayer.path = UIBezierPath(arcCenter: center, radius: 17,
                                          startAngle: -.pi / 2, endAngle: .pi * 1.5,
                                          clockwise: true).cgPath
    }

    // MARK: - 对外接口

    var zoomScale: CGFloat { diagnostics.currentScale }

    var isZoomed: Bool { diagnostics.currentScale > 1.01 }

    /// 当前缩放状态快照（B1 互斥判定信号源：纯值，不读任何 UIScrollView 几何）。
    /// 宽限窗口计时来自控制器的用户活动时间戳——程序性 reset/布局不算"活动"，
    /// 否则翻页/复用/旋转后翻页会被宽限窗口卡住 1 秒。
    var zoomState: ViewerGesturePolicy.CellState {
        ViewerGesturePolicy.CellState(isZooming: zoomController.isInteracting,
                                      zoomScale: diagnostics.currentScale,
                                      secondsSinceZoomActivity: zoomController.secondsSinceActivity,
                                      geometryState: .idle)
    }

    /// 是否已有图（VC appear 重挂判断 + DEBUG 横幅 img 字段）
    var hasImage: Bool { imageView.image != nil }

    /// 调试/取证用只读快照：不含图片像素。
    var imageViewFrameWidth: CGFloat { imageView.frame.width }

    func setZoomTransactionIdleHandler(_ handler: (() -> Void)?) {
        onZoomTransactionDidBecomeIdle = handler
    }

    func setDownloadHandler(_ handler: ((String) -> Void)?) { onDownloadRequested = handler }

    /// 显示大图；image 为 nil 且 iCloud-only 时进入占位态。
    func configure(item: PhotoItem, image: UIImage?) {
        onZoomTransactionDidBecomeIdle = nil
        itemID = item.id
        configureToken += 1
        loadToken += 1
        onRetryRequested = nil
        cloudIcon.image = UIImage(systemName: "icloud")
        cloudLabel.text = "这张照片存储在 iCloud，需要下载后才能操作"
        downloadButton.setTitle("下载", for: .normal)
        let isPlaceholder = (image == nil && item.isCloudOnly)
        cloudBox.isHidden = !isPlaceholder
        imageView.image = image
        diagnostics = ZoomDiagnostics()
        currentFitSize = .zero
        lastViewportSize = .zero
        hasAppliedLayout = false
        zoomController.reset(animated: false)
        relayoutForViewportChange()
        refreshInteraction()
    }

    /// VC 收到 fullImage 的 inCloud 回传后调用（上游 isCloudOnly 判定缺失时的自救占位）
    func showCloudPlaceholder() {
        onRetryRequested = nil
        cloudIcon.image = UIImage(systemName: "icloud")
        cloudLabel.text = "这张照片存储在 iCloud，需要下载后才能操作"
        downloadButton.setTitle("下载", for: .normal)
        cloudBox.isHidden = false
        progressLayer.isHidden = true
        refreshInteraction()
    }

    /// 大图加载失败（非 iCloud）：占位 + 中文重试（docs/22 Phase 4 查看器）
    func showFailurePlaceholder(onRetry: @escaping () -> Void) {
        onRetryRequested = onRetry
        cloudIcon.image = UIImage(systemName: "exclamationmark.triangle")
        cloudLabel.text = "加载失败，请检查照片是否仍在本机"
        downloadButton.setTitle("重试", for: .normal)
        cloudBox.isHidden = false
        progressLayer.isHidden = true
        refreshInteraction()
    }

    /// 下载完成回填（iCloud → 大图）
    func applyDownloadedImage(_ image: UIImage) {
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        imageView.image = image
        currentFitSize = .zero
        hasAppliedLayout = false
        zoomController.reset(animated: false)
        relayoutForViewportChange()
        refreshInteraction()
        ViewerTrace.log("img=ok id=\(itemID?.prefix(8) ?? "-") w=\(Int(image.size.width)) h=\(Int(image.size.height))")
    }

    func updateDownloadProgress(_ fraction: Double) {
        progressLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(max(0.02, min(1, fraction)))
        CATransaction.commit()
    }

    /// 状态变化后刷新图片内容（收藏/隐藏不改图片，占位）
    func setImage(_ image: UIImage?) {
        if let image {
            imageView.image = image
        }
    }

    /// 回到 1× 居中（翻页/复用/旋转路径）。
    func resetZoom() {
        zoomController.reset(animated: false)
    }

    // MARK: - 布局（全部经 ZoomGeometry / ZoomTransformPolicy，零散几何值不得出现）

    /// viewport 尺寸或图片变化时重算 aspectFit；旋转用 ZoomTransformPolicy.relayout 保持中心内容点。
    private func relayoutForViewportChange() {
        let viewport = viewportScrollView.bounds.size
        guard let image = imageView.image,
              viewport.width > 0, viewport.height > 0 else { return }
        let fit = ZoomGeometry.aspectFitSize(imageWidth: Double(image.size.width),
                                             imageHeight: Double(image.size.height),
                                             viewportWidth: Double(viewport.width),
                                             viewportHeight: Double(viewport.height))
        guard fit.width > 0, fit.height > 0 else { return }
        let fitSize = CGSize(width: fit.width, height: fit.height)
        let viewportChanged = !hasAppliedLayout || lastViewportSize != viewport
        guard fitSize != currentFitSize || viewportChanged else { return }

        if viewportChanged, hasAppliedLayout, currentFitSize.width > 0 {
            // 旋转/尺寸变化：保持中心内容点，重新钳制（docs/25 §4.5）
            let t = ZoomTransformPolicy.relayout(current: zoomController.transform,
                                                 oldViewport: (Double(lastViewportSize.width), Double(lastViewportSize.height)),
                                                 newViewport: (Double(viewport.width), Double(viewport.height)),
                                                 contentWidth: Double(currentFitSize.width),
                                                 contentHeight: Double(currentFitSize.height))
            zoomController.applyRelayout(t)
        } else if !hasAppliedLayout {
            // 首次布局：回 1× 居中
            zoomController.applyRelayout(.identity)
        }
        currentFitSize = fitSize
        lastViewportSize = viewport
        hasAppliedLayout = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.bounds.size = fitSize
        CATransaction.commit()
        applyTransform(zoomController.transform)
        zoomController.updateLayout(contentFitSize: fitSize, viewportSize: viewport)
        refreshInteraction()
    }

    /// 变换应用：transform 缩放绕中心；center = viewport 中心 + translation（与 policy 模型一致）。
    private func applyTransform(_ t: ZoomTransform) {
        let viewport = viewportScrollView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.transform = CGAffineTransform(scaleX: CGFloat(t.scale), y: CGFloat(t.scale))
        imageView.center = CGPoint(x: viewport.width / 2 + CGFloat(t.translationX),
                                   y: viewport.height / 2 + CGFloat(t.translationY))
        CATransaction.commit()
        diagnostics.currentScale = CGFloat(t.scale)
        diagnostics.lastActivity = CACurrentMediaTime()
    }

    /// 交互护栏：有图 && 视口有效 && 非占位态。无图时捏合/双击整体关闭。
    private func refreshInteraction() {
        let allowed = imageView.image != nil
            && viewportScrollView.bounds.width > 0 && viewportScrollView.bounds.height > 0
            && cloudBox.isHidden
        zoomController.setGesturesEnabled(allowed)
    }
}

#if DEBUG
// 单元测试锚点（Release 不编译）
extension ZoomableImageCell {
    var test_scrollView: UIScrollView { viewportScrollView }
    var test_imageView: UIImageView { imageView }
    var test_cloudBox: UIView { cloudBox }
    var test_zoomController: ZoomInteractionController { zoomController }
    var test_imageViewFrame: CGRect { imageView.frame }
    /// 单测无 runloop：显式写入一个变换并断言几何
    func test_applyTransform(scale: Double, translationX: Double, translationY: Double) {
        zoomController.applyRelayout(ZoomTransform(scale: scale, translationX: translationX, translationY: translationY))
    }
}
#endif
