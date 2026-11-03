// MARK: - 职责说明：可缩放大图 cell v2（docs/13 §3.3 / S01 重写）——
// 视图层级：contentView → scrollView → zoomContentView → imageView；viewForZooming 返回 zoomContentView。
// 铁律：① 只有 bounds > 0 且 image != nil 才布局/允许缩放；② 缩放过程中绝不改 zoomContentView.frame
//（scrollViewDidZoom 只更新 contentInset）；③ 双击只调用一次 zoom(to:)，rect 由 ZoomGeometry.clampedZoomRect
// 钳制；④ 全部几何来自 PhotoDeskCore.ZoomGeometry（红线 2）。
// iCloud-only：未下载时显示占位 + 「下载」按钮 + 环形进度（docs/04 §4.13）。

import UIKit
import PhotoDeskCore

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
        return view
    }()
    /// 缩放载体（viewForZooming 返回它）；imageView 只负责显示
    private let zoomContentView = UIView()
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

    private var zoomTapGesture: UITapGestureRecognizer!
    /// 复用/离屏竞态防护
    private var configureToken = 0
    private var onZoomChanged: ((CGFloat) -> Void)?
    private var onDownloadRequested: ((String) -> Void)?
    private(set) var itemID: String?
    /// cell 级加载 token（docs/09 D02：回填前校验 cell 未被复用给另一张照片）
    private(set) var loadToken = 0
    /// VC 挂载的在途加载任务（离屏/复用即取消，docs/13 S08）
    var loadTask: Task<Void, Never>?

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
            guard let id = self?.itemID else { return }
            self?.onDownloadRequested?(id)
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

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

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad()
        imageView.image = nil
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        resetZoom()
        scrollView.isUserInteractionEnabled = false
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

    /// 任务 2.2：暴露当前缩放
    var zoomScale: CGFloat { scrollView.zoomScale }

    var isZoomed: Bool { scrollView.zoomScale > 1.01 }

    func setZoomCallback(_ callback: ((CGFloat) -> Void)?) { onZoomChanged = callback }
    func setDownloadHandler(_ handler: ((String) -> Void)?) { onDownloadRequested = handler }

    /// 显示大图；image 为 nil 且 iCloud-only 时进入占位态。
    /// docs/09 D02：设置新 item 时必须清空 imageView + resetZoom（复用瞬间不得显示上一张）
    func configure(item: PhotoItem, image: UIImage?) {
        itemID = item.id
        configureToken += 1
        loadToken += 1   // 使在途回填失效（新 item → 旧 token 不匹配）
        let isPlaceholder = (image == nil && item.isCloudOnly)
        cloudBox.isHidden = !isPlaceholder
        // 无图（含占位/未加载）时禁用捏合（docs/13 S01：image == nil → 禁交互）
        scrollView.isUserInteractionEnabled = (image != nil && !isPlaceholder)
        imageView.image = image   // nil 也赋值：清空旧图
        resetZoom()
        layoutImageContent()
    }

    /// 下载完成回填（iCloud → 大图）
    func applyDownloadedImage(_ image: UIImage) {
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        imageView.image = image
        scrollView.isUserInteractionEnabled = true
        resetZoom()
        layoutImageContent()
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

    /// 回到 1×（仅在 bounds 有效时执行，docs/13 S01）
    func resetZoom() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        scrollView.setZoomScale(Self.minZoomScale, animated: false)
        updateCenteringInset()
    }

    // MARK: - 布局（全部经 ZoomGeometry，零散几何值不得出现）

    /// aspectFit 布局：只在 bounds > 0 且 image != nil 且未放大时执行；缩放中绝不改 frame
    private func layoutImageContent() {
        guard let image = imageView.image,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              scrollView.zoomScale.isFinite else { return }
        // 缩放中（zoomScale > 1.001）不重设 frame：UIScrollView 通过 transform 缩放，外部改 frame 会打架
        guard scrollView.zoomScale <= Self.minZoomScale + 0.001 else { return }
        let fit = ZoomGeometry.aspectFitSize(imageWidth: Double(image.size.width),
                                             imageHeight: Double(image.size.height),
                                             viewportWidth: Double(scrollView.bounds.width),
                                             viewportHeight: Double(scrollView.bounds.height))
        guard fit.width > 0, fit.height > 0 else { return }
        zoomContentView.frame = CGRect(origin: .zero,
                                       size: CGSize(width: fit.width, height: fit.height))
        scrollView.contentSize = zoomContentView.frame.size
        updateCenteringInset()
    }

    /// 内容居中 inset（scrollViewDidZoom / 布局后调用；只改 contentInset，不改任何 frame）
    private func updateCenteringInset() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        let inset = ZoomGeometry.centeredInset(contentWidth: Double(zoomContentView.frame.width),
                                               contentHeight: Double(zoomContentView.frame.height),
                                               viewportWidth: Double(scrollView.bounds.width),
                                               viewportHeight: Double(scrollView.bounds.height),
                                               zoomScale: Double(scrollView.zoomScale))
        scrollView.contentInset = UIEdgeInsets(top: inset.top, left: inset.left,
                                               bottom: inset.bottom, right: inset.right)
    }

    // MARK: - 双击缩放（docs/04 §4.4：点击点为中心，1×↔2.5×；只调用一次 zoom(to:)）

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard imageView.image != nil,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              scrollView.zoomScale.isFinite else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled && AppContainer.shared.settings.respectReduceMotion
        let animated = !reduceMotion

        if scrollView.zoomScale > Self.minZoomScale + 0.01 {
            // 已放大 → 回到 1×（单次调用）
            scrollView.setZoomScale(Self.minZoomScale, animated: animated)
            return
        }
        guard zoomContentView.frame.width > 0, zoomContentView.frame.height > 0 else { return }
        let point = gesture.location(in: zoomContentView)
        guard let rect = ZoomGeometry.clampedZoomRect(
            zoomScale: 2.5,
            focusX: Double(point.x), focusY: Double(point.y),
            viewportWidth: Double(scrollView.bounds.width),
            viewportHeight: Double(scrollView.bounds.height),
            imageWidth: Double(zoomContentView.frame.width),
            imageHeight: Double(zoomContentView.frame.height)
        ) else { return }
        // 显式 CGFloat 转换（避免 Double/CGFloat 混合表达式拖慢类型检查）
        let targetRect = CGRect(x: CGFloat(rect.x), y: CGFloat(rect.y),
                                width: CGFloat(rect.width), height: CGFloat(rect.height))
        scrollView.zoom(to: targetRect, animated: animated)
    }
}

extension ZoomableImageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomContentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 铁律：缩放过程中只更新 contentInset 居中，绝不改 zoomContentView.frame（docs/13 S01 根因 2）
        updateCenteringInset()
        onZoomChanged?(scrollView.zoomScale)
    }
}
