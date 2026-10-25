// MARK: - 职责说明：可缩放大图 cell（docs/05 M2 任务 2.2）——
// UIScrollView 嵌套 UIImageView：双击 1×↔2.5×（0.25s 弹性动画，点击点为中心）、双指捏合 1×–5×、松手回弹边界；
// 对外暴露 zoomScale 与变化回调（Viewer 据此禁用上下滑：zoomScale > 1.01，docs/03 §5.1）。
// iCloud-only：未下载时显示占位 + 「下载」按钮 + 环形进度（docs/04 §4.13）。
// imageView 用 frame 布局（scrollView 缩放内容需手动居中，与 AutoLayout 混用会互相打架）。

import UIKit

final class ZoomableImageCell: UICollectionViewCell {
    static let reuseID = "ZoomableImageCell"

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.bouncesZoom = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DSColor.bgViewer
        contentView.addSubview(scrollView)
        scrollView.addSubview(imageView)
        contentView.addSubview(cloudBox)
        cloudBox.addSubview(cloudIcon)
        cloudBox.addSubview(cloudLabel)
        cloudBox.addSubview(downloadButton)

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5

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
        configureToken += 1
        resetZoom()
        imageView.image = nil
        cloudBox.isHidden = true
        progressLayer.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scrollView.zoomScale <= 1.01 {
            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
        }
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

    /// 显示大图；image 为 nil 且 iCloud-only 时进入占位态
    func configure(item: PhotoItem, image: UIImage?) {
        itemID = item.id
        configureToken += 1
        let isPlaceholder = (image == nil && item.isCloudOnly)
        cloudBox.isHidden = !isPlaceholder
        scrollView.isUserInteractionEnabled = !isPlaceholder
        if let image {
            imageView.image = image
        }
        imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
    }

    /// 下载完成回填（iCloud → 大图）
    func applyDownloadedImage(_ image: UIImage) {
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
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

    func resetZoom() {
        scrollView.setZoomScale(1, animated: false)
    }

    // MARK: - 双击缩放（docs/04 §4.4：点击点与 1×/2.5× 间切换，0.25s 弹性动画）

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let target: CGFloat = scrollView.zoomScale > 1.01 ? 1 : 2.5
        let point = gesture.location(in: imageView)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled && AppContainer.shared.settings.respectReduceMotion

        let rect: CGRect
        if target > 1 {
            let size = CGSize(width: scrollView.bounds.width / target,
                              height: scrollView.bounds.height / target)
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            rect = CGRect(origin: origin, size: size)
        } else {
            rect = scrollView.bounds
        }

        if reduceMotion {
            scrollView.zoom(to: rect, animated: false)
            scrollView.setZoomScale(target, animated: false)
        } else {
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           usingSpringWithDamping: 0.8,
                           initialSpringVelocity: 0.3,
                           options: [.beginFromCurrentState]) {
                self.scrollView.zoom(to: rect, animated: false)
                self.scrollView.setZoomScale(target, animated: false)
            }
        }
    }
}

extension ZoomableImageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 内容小于视口时居中（标准做法）
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }
        imageView.frame = frameToCenter
        onZoomChanged?(scrollView.zoomScale)
    }
}
