// MARK: - 职责说明：可缩放大图 cell v5（docs/22 §3.4 / P0-1）——
// 视图层级：contentView → scrollView → zoomContentView → imageView；viewForZooming 只 return zoomContentView。
// 铁律：① viewForZooming 方法体内禁止读取任何 scrollView / view 属性、禁止 ViewerTrace.log、禁止字符串插值；
// ② 缩放活跃期绝不写 zoomContentView.frame / contentSize / contentInset，几何只在
//    layoutSubviews（1×）与 scrollViewDidEndZooming 收敛；③ configure / prepareForReuse 先摘 delegate
//    再 resetZoom，复用期不触发缩放回调；④ 无图/占位通过 scrollView.isUserInteractionEnabled 与
//    pinchGestureRecognizer.isEnabled 关闭捏合，不靠 viewForZooming 返回 nil 兜底；
// ⑤ 诊断只维护纯值 ZoomDiagnostics（currentScale / zoomEndCount / lastActivity），不回调 VC 刷新 UI。
// 全部几何来自 PhotoDeskCore（红线 2）。iCloud-only 占位与下载进度沿沿旧实现。

import UIKit
import PhotoDeskCore

/// 纯值诊断快照：VC 只在翻页/定时器/用户操作时读取，delegate 内不回调 VC。
struct ZoomDiagnostics: Equatable {
    var currentScale: CGFloat = ZoomableImageCell.minZoomScale
    var zoomEndCount: Int = 0
    var lastActivity: TimeInterval = 0
}

final class ZoomableImageCell: UICollectionViewCell {
    static let reuseID = "ZoomableImageCell"
    static let minZoomScale: CGFloat = 1
    static let maxZoomScale: CGFloat = 5

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.bouncesZoom = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "Viewer-ZoomScrollView"
        return view
    }()
    /// 缩放载体（viewForZooming 返回它）；imageView 只负责显示
    private let zoomContentView = UIView()
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
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

    private var zoomTapGesture: UITapGestureRecognizer!
    /// 复用/离屏竞态防护
    private var configureToken = 0
    private var onDownloadRequested: ((String) -> Void)?
    private var onRetryRequested: (() -> Void)?
    /// 缩放结束（或几何收敛）后通知 VC 串行 drain 删除/隐藏队列；不在此处执行 performBatchUpdates。
    var onZoomTransactionDidBecomeIdle: (() -> Void)?
    private(set) var itemID: String?
    /// cell 级加载 token（docs/09 D02：回填前校验 cell 未被复用给另一张照片）
    private(set) var loadToken = 0
    /// VC 挂载的在途加载任务（离屏/复用即取消，docs/13 S08）
    var loadTask: Task<Void, Never>?

    /// 纯值诊断；delegate 内只更新数字，不触碰 VC / 数据源。
    private(set) var diagnostics = ZoomDiagnostics()
    /// 只在布局/配置路径写，不在 delegate 查询路径写。
    private var hasValidZoomContent = false
    private var isApplyingZoomLayout = false
    private var needsResetZoomOnEnd = false
    #if DEBUG
    /// 单测模拟 isZooming（Release 不编译；UIScrollView.isZooming 为只读）
    var test_zoomInProgress = false
    #endif

    private var isZoomActive: Bool {
        #if DEBUG
        if test_zoomInProgress { return true }
        #endif
        return scrollView.isZooming
    }

    /// 开始一次加载：返回 token；回填前用 matches(token:) 校验
    func beginLoad() -> Int {
        loadToken += 1
        return loadToken
    }

    func matches(token: Int) -> Bool {
        token == loadToken
    }

    /// 取消在途加载任务（didEndDisplaying / prepareForReuse，docs/13 S08）
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        configureToken += 1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DSColor.bgViewer
        contentView.addSubview(scrollView)
        scrollView.addSubview(zoomContentView)
        zoomContentView.addSubview(imageView)
        contentView.addSubview(cloudBox)
        cloudBox.addSubview(cloudIcon)
        cloudBox.addSubview(cloudLabel)
        cloudBox.addSubview(downloadButton)

        scrollView.delegate = self
        scrollView.minimumZoomScale = Self.minZoomScale
        scrollView.maximumZoomScale = Self.maxZoomScale

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

        zoomTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        zoomTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(zoomTapGesture)

        downloadButton.addAction(UIAction { [weak self] _ in
            if let retry = self?.onRetryRequested {
                retry()
                return
            }
            guard let id = self?.itemID else { return }
            self?.onDownloadRequested?(id)
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: zoomContentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: zoomContentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: zoomContentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: zoomContentView.trailingAnchor),

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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    deinit {
        loadTask?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // 先摘 delegate：resetZoom / setZoomScale 不得触发任何缩放回调。
        scrollView.delegate = nil
        scrollView.isUserInteractionEnabled = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
        onZoomTransactionDidBecomeIdle = nil
        cancelLoad()
        imageView.image = nil
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        itemID = nil
        diagnostics = ZoomDiagnostics()
        hasValidZoomContent = false
        if scrollView.bounds.width > 0, scrollView.bounds.height > 0, !isZoomActive {
            scrollView.setZoomScale(Self.minZoomScale, animated: false)
            scrollView.contentInset = .zero
        } else {
            needsResetZoomOnEnd = true
        }
        scrollView.delegate = self
        refreshInteraction()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageContent()
        let center = CGPoint(x: downloadButton.bounds.midX, y: downloadButton.bounds.midY)
        progressLayer.frame = downloadButton.bounds
        progressLayer.path = UIBezierPath(arcCenter: center, radius: 17,
                                          startAngle: -.pi / 2, endAngle: .pi * 1.5,
                                          clockwise: true).cgPath
    }

    // MARK: - 对外接口

    var zoomScale: CGFloat { diagnostics.currentScale }

    var isZoomed: Bool { diagnostics.currentScale > 1.01 }

    /// 当前缩放状态快照（B1 互斥判定信号源：纯值，不读 UIScrollView 几何）
    var zoomState: ViewerGesturePolicy.CellState {
        ViewerGesturePolicy.CellState(isZooming: isZoomActive,
                                      zoomScale: diagnostics.currentScale,
                                      secondsSinceZoomActivity: CACurrentMediaTime() - diagnostics.lastActivity,
                                      geometryState: .idle)
    }

    /// 是否已有图（VC appear 重挂判断 + DEBUG 横幅 img 字段）
    var hasImage: Bool { imageView.image != nil }

    /// 调试/取证用只读快照：不含图片像素。
    var zoomContentViewFrameWidth: CGFloat { zoomContentView.frame.width }
    var imageViewFrameWidth: CGFloat { imageView.frame.width }
    var innerContentSize: String { "\(Int(scrollView.contentSize.width))x\(Int(scrollView.contentSize.height))" }

    func setZoomTransactionIdleHandler(_ handler: (() -> Void)?) {
        onZoomTransactionDidBecomeIdle = handler
    }

    func setDownloadHandler(_ handler: ((String) -> Void)?) { onDownloadRequested = handler }

    /// 显示大图；image 为 nil 且 iCloud-only 时进入占位态。
    func configure(item: PhotoItem, image: UIImage?) {
        // 先摘 delegate，resetZoom 不触发回调；复用瞬间不显示上一张。
        scrollView.delegate = nil
        scrollView.isUserInteractionEnabled = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
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
        hasValidZoomContent = false
        needsResetZoomOnEnd = false
        if scrollView.bounds.width > 0, scrollView.bounds.height > 0, !isZoomActive {
            scrollView.setZoomScale(Self.minZoomScale, animated: false)
        } else {
            needsResetZoomOnEnd = true
        }
        layoutImageContent()
        scrollView.delegate = self
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
        resetZoom()
        layoutImageContent()
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

    /// 回到 1×（仅在 bounds 有效时执行；缩放进行中延迟到 didEndZooming）。
    func resetZoom() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        if isZoomActive {
            needsResetZoomOnEnd = true
            return
        }
        scrollView.setZoomScale(Self.minZoomScale, animated: false)
        centerZoomContent()
    }

    // MARK: - 布局（全部经 ZoomGeometry，零散几何值不得出现）

    /// aspectFit 布局：只在 1× 且未缩放时写 frame/contentSize；缩放中绝不干预。
    private func layoutImageContent() {
        guard !isApplyingZoomLayout, !isZoomActive else { return }
        guard let image = imageView.image,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        if needsResetZoomOnEnd {
            needsResetZoomOnEnd = false
            scrollView.setZoomScale(Self.minZoomScale, animated: false)
        }
        guard scrollView.zoomScale <= Self.minZoomScale + 0.001 else { return }

        let fit = ZoomGeometry.aspectFitSize(imageWidth: Double(image.size.width),
                                             imageHeight: Double(image.size.height),
                                             viewportWidth: Double(scrollView.bounds.width),
                                             viewportHeight: Double(scrollView.bounds.height))
        guard fit.width > 0, fit.height > 0 else { return }
        let size = CGSize(width: fit.width, height: fit.height)
        isApplyingZoomLayout = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoomContentView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        CATransaction.commit()
        hasValidZoomContent = true
        isApplyingZoomLayout = false
        centerZoomContent()
        refreshInteraction()
    }

    /// 内容居中 inset：用未变换 bounds（B3），只在布局与 didEndZooming 调用。
    private func centerZoomContent() {
        guard !isApplyingZoomLayout else { return }
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              zoomContentView.bounds.width > 0, zoomContentView.bounds.height > 0 else { return }
        let insets = ZoomGeometry.centeredInset(
            contentWidth: Double(zoomContentView.bounds.width),
            contentHeight: Double(zoomContentView.bounds.height),
            viewportWidth: Double(scrollView.bounds.width),
            viewportHeight: Double(scrollView.bounds.height),
            zoomScale: Double(scrollView.zoomScale)
        )
        guard insets.top.isFinite, insets.left.isFinite,
              insets.bottom.isFinite, insets.right.isFinite else { return }
        isApplyingZoomLayout = true
        scrollView.contentInset = UIEdgeInsets(top: insets.top, left: insets.left,
                                               bottom: insets.bottom, right: insets.right)
        isApplyingZoomLayout = false
    }

    /// 交互三条件护栏：image != nil && bounds > 0 && contentSize > 0 且非占位态。
    private func refreshInteraction() {
        let allowed = imageView.image != nil
            && scrollView.bounds.width > 0 && scrollView.bounds.height > 0
            && scrollView.contentSize.width > 0 && scrollView.contentSize.height > 0
            && cloudBox.isHidden
        scrollView.isUserInteractionEnabled = allowed
        scrollView.pinchGestureRecognizer?.isEnabled = allowed
    }

    // MARK: - 双击缩放（docs/04 §4.4：点击点为中心，1×↔2.5×；只调用一次 zoom(to:)）

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard imageView.image != nil, !isZoomActive,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              zoomContentView.bounds.width > 0, zoomContentView.bounds.height > 0 else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled && AppContainer.shared.settings.respectReduceMotion
        let animated = !reduceMotion

        if scrollView.zoomScale > Self.minZoomScale + 0.01 {
            scrollView.setZoomScale(Self.minZoomScale, animated: animated)
            return
        }
        let point = gesture.location(in: zoomContentView)
        guard let rect = ZoomGeometry.clampedZoomRect(
            zoomScale: 2.5,
            focusX: Double(point.x), focusY: Double(point.y),
            viewportWidth: Double(scrollView.bounds.width),
            viewportHeight: Double(scrollView.bounds.height),
            imageWidth: Double(zoomContentView.bounds.width),
            imageHeight: Double(zoomContentView.bounds.height)
        ) else { return }
        let targetRect = CGRect(x: CGFloat(rect.x), y: CGFloat(rect.y),
                                width: CGFloat(rect.width), height: CGFloat(rect.height))
        scrollView.zoom(to: targetRect, animated: animated)
    }
}

extension ZoomableImageCell: UIScrollViewDelegate {
    /// 铁律（docs/22 §3.4.3）：本方法只返回 zoomContentView。
    /// 禁止读取任何 scrollView / view 属性，禁止 ViewerTrace.log，禁止字符串插值。
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomContentView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        diagnostics.lastActivity = CACurrentMediaTime()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 只更新纯值诊断；不写 contentInset / frame / contentSize，不回调 VC。
        let scale = scrollView.zoomScale
        if scale.isFinite {
            diagnostics.currentScale = scale
        }
        diagnostics.lastActivity = CACurrentMediaTime()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        diagnostics.lastActivity = CACurrentMediaTime()
        if scale.isFinite {
            diagnostics.currentScale = scale
        }
        diagnostics.zoomEndCount += 1
        if needsResetZoomOnEnd {
            needsResetZoomOnEnd = false
            scrollView.setZoomScale(Self.minZoomScale, animated: false)
        }
        centerZoomContent()
        refreshInteraction()
        ViewerTrace.log("zoom=end id=\(itemID?.prefix(8) ?? "-") scale=\(String(format: "%.2f", diagnostics.currentScale))")
        // 队列 drain 排到下一轮主循环，避免与 CATransaction / 手势同一帧。
        DispatchQueue.main.async { [weak self] in
            self?.onZoomTransactionDidBecomeIdle?()
        }
    }
}

#if DEBUG
// 单元测试 I5′ / 交互护栏断言锚点（Release 不编译）
extension ZoomableImageCell {
    var test_scrollView: UIScrollView { scrollView }
    var test_zoomContentView: UIView { zoomContentView }
    var test_imageView: UIImageView { imageView }
    var test_cloudBox: UIView { cloudBox }
    /// 单测无 runloop：显式触发居中收敛（生产路径由 layoutSubviews / didEndZooming 调用）
    func test_recenterAfterZoom() {
        centerZoomContent()
    }
}
#endif
