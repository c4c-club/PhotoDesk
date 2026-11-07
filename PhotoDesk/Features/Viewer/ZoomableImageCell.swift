// MARK: - 职责说明：可缩放大图 cell v4（M13 P1 缩放事务状态机；docs/19 §3.1 / docs/20）——
// 视图层级：contentView → scrollView → zoomContentView → imageView；viewForZooming 返回 zoomContentView。
// 铁律：① 只有 bounds > 0 且 image != nil 才布局/允许缩放；② 缩放事务 idle | active | settling：
// active 期间 configure / layoutSubviews / layoutImageContent / updateCenteringInset / scrollViewDidZoom
// 一律只记 pendingGeometry，绝不写 zoomContentView.frame / contentSize / contentInset；
// settling 用一次 CATransaction + layoutIfNeeded 合并提交，提交前校验全部有限且 >0（Core
// ZoomGeometryTransaction），非有限丢弃并写 ViewerTrace；③ 双击只调用一次 zoom(to:)，rect 由
// ZoomGeometry.clampedZoomRect 钳制；④ 全部几何来自 PhotoDeskCore（红线 2）。
// M12 v3 修复保留：A1 imageView 四边约束；B2 交互三条件护栏；B3 inset 用未变换 bounds；
// A2 showCloudPlaceholder()。M13 新增：viewForZooming 返回 nil 写含几何快照的 Release 面包屑；
// Release 写 zoom=、img=、appear、pendingDeleteCount、非有限值（VC + 本文件共同覆盖），只写本地、零上传、
// 不含用户照片像素。iCloud-only：未下载时显示占位 +「下载」按钮 + 环形进度（docs/04 §4.13）。

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
        view.accessibilityIdentifier = "Viewer-ZoomScrollView"
        return view
    }()
    /// 缩放载体（viewForZooming 返回它）；imageView 只负责显示
    private let zoomContentView = UIView()
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false   // M12 A1：四边约束（旧版无约束恒 .zero）
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
    /// 缩放事务进入 idle 后通知 VC 串行 drain 删除/隐藏队列；不在此处执行 performBatchUpdates。
    var onZoomTransactionDidBecomeIdle: (() -> Void)?
    private(set) var itemID: String?
    /// cell 级加载 token（docs/09 D02：回填前校验 cell 未被复用给另一张照片）
    private(set) var loadToken = 0
    /// VC 挂载的在途加载任务（离屏/复用即取消，docs/13 S08）
    var loadTask: Task<Void, Never>?
    /// 最近一次缩放活动时间（scrollViewDidZoom 刷新；回弹窗口判定用，DSMotion.zoomActivityGrace）
    private var lastZoomActivity: TimeInterval = 0
    /// M13：缩放事务状态机；active 冻结几何写入，settling 一次批量提交，idle 才允许删除事务。
    private(set) var zoomTransactionState: ZoomTransactionState = .idle
    /// 活跃期只累积待提交几何，合并逻辑来自 PhotoDeskCore.ZoomGeometryTransaction。
    private var pendingGeometry: [ZoomGeometryCommit] = []
    private var settleTimer: Timer?
    private var lastLoggedZoomScale: Double = -1
    private var didLogNonFiniteZoom = false

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

            // M12 A1：imageView 四边约束到 zoomContentView——frame 恒随内容视图（I5′ 不变量）
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
        settleTimer?.invalidate()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        settleTimer?.invalidate()
        settleTimer = nil
        pendingGeometry.removeAll()
        zoomTransactionState = .idle
        onZoomTransactionDidBecomeIdle = nil
        cancelLoad()
        imageView.image = nil
        cloudBox.isHidden = true
        progressLayer.isHidden = true
        resetZoom()
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

    /// 任务 2.2：暴露当前缩放
    var zoomScale: CGFloat { scrollView.zoomScale }

    var isZoomed: Bool { scrollView.zoomScale > 1.01 }

    /// 当前缩放状态快照（B1 互斥判定信号源：捏合进行中 / zoomScale / 回弹宽限 / 几何事务态）
    var zoomState: ViewerGesturePolicy.CellState {
        ViewerGesturePolicy.CellState(isZooming: scrollView.isZooming,
                                      zoomScale: scrollView.zoomScale,
                                      secondsSinceZoomActivity: CACurrentMediaTime() - lastZoomActivity,
                                      geometryState: zoomTransactionState)
    }

    /// 是否已有图（VC appear 重挂判断 + DEBUG 横幅 img 字段）
    var hasImage: Bool { imageView.image != nil }

    /// Release 几何面包屑与 UI 取证用只读快照：不含图片像素。
    var zoomContentViewFrameWidth: CGFloat { zoomContentView.frame.width }
    var imageViewFrameWidth: CGFloat { imageView.frame.width }
    var innerContentSize: String { "\(Int(scrollView.contentSize.width))x\(Int(scrollView.contentSize.height))" }

    func setZoomTransactionIdleHandler(_ handler: (() -> Void)?) {
        onZoomTransactionDidBecomeIdle = handler
    }

    func setZoomCallback(_ callback: ((CGFloat) -> Void)?) { onZoomChanged = callback }
    func setDownloadHandler(_ handler: ((String) -> Void)?) { onDownloadRequested = handler }

    /// 显示大图；image 为 nil 且 iCloud-only 时进入占位态。
    /// docs/09 D02：设置新 item 时必须清空 imageView + resetZoom（复用瞬间不得显示上一张）。
    /// M13：configure 在 active 期也只记录 pendingGeometry，不写任何缩放几何属性。
    func configure(item: PhotoItem, image: UIImage?) {
        settleTimer?.invalidate()
        settleTimer = nil
        pendingGeometry.removeAll()
        zoomTransactionState = .idle
        onZoomTransactionDidBecomeIdle = nil

        itemID = item.id
        configureToken += 1
        loadToken += 1   // 使在途回填失效（新 item → 旧 token 不匹配）
        let isPlaceholder = (image == nil && item.isCloudOnly)
        cloudBox.isHidden = !isPlaceholder
        imageView.image = image   // nil 也赋值：清空旧图
        resetZoom()
        layoutImageContent()
        // M12 B2：交互不在 configure 里直接置 true——由 layoutImageContent 成功路径决定
        refreshInteraction()
    }

    /// M12 A2：VC 收到 fullImage 的 inCloud 回传后调用（上游 isCloudOnly 判定缺失时的自救占位）
    func showCloudPlaceholder() {
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
        // M12 Phase 1：img 面包屑（回填成功取证；加载失败路径由 VC loadImage 的 loadEnd ok=false 覆盖）
        // M13：Release 同样写 img=，不含像素、零上传。
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

    /// 回到 1×（仅在 bounds 有效时执行；active 期冻结 setZoomScale / contentInset 写入）。
    func resetZoom() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        if isGeometryFrozen {
            recordPendingGeometry(scale: Self.minZoomScale)
            return
        }
        scrollView.setZoomScale(Self.minZoomScale, animated: false)
        updateCenteringInset()
    }

    // MARK: - 布局（全部经 ZoomGeometry，零散几何值不得出现）

    private var isGeometryFrozen: Bool {
        zoomTransactionState != .idle || ViewerGesturePolicy.isZoomTransactionActive(zoomState)
    }

    /// aspectFit 布局：idle 时一次性写 frame/contentSize/inset；active 期只累积 pendingGeometry。
    private func layoutImageContent() {
        guard let image = imageView.image,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              scrollView.zoomScale.isFinite else { return }
        // 缩放中（zoomScale > 1.001）不重设 frame：UIScrollView 通过 transform 缩放，外部改 frame 会打架
        guard scrollView.zoomScale <= Self.minZoomScale + 0.001 else { return }

        if isGeometryFrozen {
            recordPendingGeometry(scale: scrollView.zoomScale)
            return
        }

        let fit = ZoomGeometry.aspectFitSize(imageWidth: Double(image.size.width),
                                             imageHeight: Double(image.size.height),
                                             viewportWidth: Double(scrollView.bounds.width),
                                             viewportHeight: Double(scrollView.bounds.height))
        guard fit.width > 0, fit.height > 0 else { return }
        let viewport = DoubleSize(width: Double(scrollView.bounds.width),
                                  height: Double(scrollView.bounds.height))
        let insets = ZoomGeometryTransaction.centeringInsets(content: fit,
                                                             viewport: viewport,
                                                             zoomScale: Double(scrollView.zoomScale))
        let commit = ZoomGeometryCommit(contentSize: fit, insets: insets,
                                        zoomScale: Double(scrollView.zoomScale))
        guard ZoomGeometryTransaction.sanitized(commit) != nil else {
            ViewerTrace.log("geometry non-finite size=\(fit.width)x\(fit.height) scale=\(scrollView.zoomScale)")
            return
        }
        apply(commit)
        refreshInteraction()
    }

    /// M12 B2：交互三条件护栏——image != nil && bounds > 0 && contentSize > 0 且非占位态
    private func refreshInteraction() {
        let allowed = imageView.image != nil
            && scrollView.bounds.width > 0 && scrollView.bounds.height > 0
            && scrollView.contentSize.width > 0 && scrollView.contentSize.height > 0
            && cloudBox.isHidden
        scrollView.isUserInteractionEnabled = allowed
    }

    /// 内容居中 inset（idle 时写 contentInset；active/settling 期只累积 pendingGeometry）。
    /// M12 B3：入参用 zoomContentView.bounds（不受 transform 影响）——旧版读 frame（缩放中是
    /// 变换后包围盒）再乘 zoomScale → 双倍缩放 inset；M13 改用 Core ZoomGeometryTransaction。
    private func updateCenteringInset() {
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        if isGeometryFrozen {
            recordPendingGeometry(scale: scrollView.zoomScale)
            return
        }
        let content = DoubleSize(width: Double(zoomContentView.bounds.width),
                                 height: Double(zoomContentView.bounds.height))
        // 绿7 实锤：无图/占位期内容为空是常态（每次查看器打开都有），静默跳过；
        // 旧实现把它记成 "non-finite"（非正 ≠ 非有限），污染 traceNonFinite 取证口径。
        guard content.width > 0, content.height > 0 else { return }
        let viewport = DoubleSize(width: Double(scrollView.bounds.width),
                                  height: Double(scrollView.bounds.height))
        let insets = ZoomGeometryTransaction.centeringInsets(content: content,
                                                             viewport: viewport,
                                                             zoomScale: Double(scrollView.zoomScale))
        let commit = ZoomGeometryCommit(contentSize: content, insets: insets,
                                        zoomScale: Double(scrollView.zoomScale))
        guard ZoomGeometryTransaction.sanitized(commit) != nil else {
            ViewerTrace.log("geometry non-finite inset content=\(content.width)x\(content.height) scale=\(scrollView.zoomScale)")
            return
        }
        scrollView.contentInset = UIEdgeInsets(top: insets.top, left: insets.left,
                                               bottom: insets.bottom, right: insets.right)
    }

    /// 活跃期只记录待提交几何；非有限 / 非正项直接丢弃并写 Release 面包屑，绝不写 UIKit 属性。
    private func recordPendingGeometry(scale: CGFloat) {
        guard let image = imageView.image else { return }
        let fit = ZoomGeometry.aspectFitSize(imageWidth: Double(image.size.width),
                                             imageHeight: Double(image.size.height),
                                             viewportWidth: Double(scrollView.bounds.width),
                                             viewportHeight: Double(scrollView.bounds.height))
        let viewport = DoubleSize(width: Double(scrollView.bounds.width),
                                  height: Double(scrollView.bounds.height))
        let insets = ZoomGeometryTransaction.centeringInsets(content: fit,
                                                             viewport: viewport,
                                                             zoomScale: Double(scale))
        let commit = ZoomGeometryCommit(contentSize: fit, insets: insets, zoomScale: Double(scale))
        guard ZoomGeometryTransaction.sanitized(commit) != nil else {
            ViewerTrace.log("geometry non-finite pending size=\(fit.width)x\(fit.height) scale=\(scale)")
            return
        }
        pendingGeometry.append(commit)
    }

    /// settling：一次 CATransaction + layoutIfNeeded 批量提交合并后的唯一几何快照。
    /// 校验全部有限且 >0；非有限则丢弃、写 ViewerTrace，并回到 idle 让 VC drain 删除队列。
    @objc private func commitPendingGeometry() {
        settleTimer?.invalidate()
        settleTimer = nil
        guard zoomTransactionState != .idle else { return }
        zoomTransactionState = .settling
        let snapshots = ZoomGeometryTransaction.coalesced(pendingGeometry)
        pendingGeometry.removeAll()

        guard let commit = snapshots.first else {
            // 绿7 实锤：纯捏合路径（scrollViewDidZoom 只刷时间戳）结算时 pending 为空但缩放已变化，
            // 此时只需按「未变换 bounds × 当前 zoomScale」重算居中 inset（B3）；frame/contentSize
            // 归 UIScrollView 自管，绝不干预。空内容（无图/占位）静默结算，两者都不算 non-finite。
            applyInsetOnlyAfterZoom()
            finishZoomTransaction()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(commit)
        layoutIfNeeded()
        CATransaction.commit()
        ViewerTrace.log("geometry commit once size=\(commit.contentSize.width)x\(commit.contentSize.height) scale=\(commit.zoomScale)")
        finishZoomTransaction()
    }

    /// 结算期 inset 兜底：zoomContentView.bounds 不受 transform 污染（B3 入参语义不变）。
    private func applyInsetOnlyAfterZoom() {
        let content = DoubleSize(width: Double(zoomContentView.bounds.width),
                                 height: Double(zoomContentView.bounds.height))
        guard content.width > 0, content.height > 0 else { return }
        let viewport = DoubleSize(width: Double(scrollView.bounds.width),
                                  height: Double(scrollView.bounds.height))
        let insets = ZoomGeometryTransaction.centeringInsets(content: content,
                                                             viewport: viewport,
                                                             zoomScale: Double(scrollView.zoomScale))
        let commit = ZoomGeometryCommit(contentSize: content, insets: insets,
                                        zoomScale: Double(scrollView.zoomScale))
        guard ZoomGeometryTransaction.sanitized(commit) != nil else {
            ViewerTrace.log("geometry non-finite inset-only content=\(content.width)x\(content.height) scale=\(scrollView.zoomScale)")
            return
        }
        scrollView.contentInset = UIEdgeInsets(top: insets.top, left: insets.left,
                                               bottom: insets.bottom, right: insets.right)
        ViewerTrace.log("geometry commit inset-only top=\(Int(insets.top)) scale=\(String(format: "%.2f", scrollView.zoomScale))")
    }

    private func apply(_ commit: ZoomGeometryCommit) {
        let size = CGSize(width: commit.contentSize.width, height: commit.contentSize.height)
        zoomContentView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        scrollView.contentInset = UIEdgeInsets(top: commit.insets.top,
                                               left: commit.insets.left,
                                               bottom: commit.insets.bottom,
                                               right: commit.insets.right)
        refreshInteraction()
    }

    private func beginZoomTransaction() {
        settleTimer?.invalidate()
        if zoomTransactionState != .active {
            zoomTransactionState = .active
            ViewerTrace.log("zoom=begin id=\(itemID?.prefix(8) ?? "-") scale=\(scrollView.zoomScale)")
        }
        scheduleSettling()
    }

    private func scheduleSettling() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(timeInterval: DSMotion.zoomActivityGrace,
                                           target: self,
                                           selector: #selector(commitPendingGeometry),
                                           userInfo: nil,
                                           repeats: false)
    }

    private func finishZoomTransaction() {
        zoomTransactionState = .idle
        ViewerTrace.log("zoom=idle id=\(itemID?.prefix(8) ?? "-") scale=\(scrollView.zoomScale)")
        onZoomTransactionDidBecomeIdle?()
    }

    // MARK: - 双击缩放（docs/04 §4.4：点击点为中心，1×↔2.5×；只调用一次 zoom(to:)）

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard imageView.image != nil,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0,
              scrollView.zoomScale.isFinite else { return }
        beginZoomTransaction()
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
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // M12 B2：零 contentSize 时返回 nil——旧版返回零尺寸 view 却允许捏合 →
        // UIScrollView 内部除零 → CALayer position contains NaN。
        // M13：nil 时写含 contentSize / frame / zoomScale 的 Release 面包屑，便于真机 .ips 还原时序。
        // 注意：本方法内禁止读 scrollView.zoomScale——UIScrollView 在 delegate 回调内经
        // _getDelegateZoomView 重入计算 zoomScale，读它会无限递归（绿5 SIGSEGV 实证）；
        // 面包屑用 transform.a 等价取当前缩放。
        guard scrollView.contentSize.width > 0, scrollView.contentSize.height > 0,
              zoomContentView.frame.width > 0, zoomContentView.frame.height > 0 else {
            ViewerTrace.log("viewForZooming nil contentSize=\(scrollView.contentSize) zoomContentView=\(zoomContentView.frame) imageView=\(imageView.frame) zoomScale=\(zoomContentView.transform.a) state=\(zoomTransactionState)")
            return nil
        }
        return zoomContentView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        lastZoomActivity = CACurrentMediaTime()
        beginZoomTransaction()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // M13 铁律：缩放回调只刷时间戳 + 日志 + onZoomChanged；绝不写 contentInset / frame / contentSize。
        lastZoomActivity = CACurrentMediaTime()
        beginZoomTransaction()
        let value = Double(scrollView.zoomScale)
        if value.isFinite {
            if abs(value - lastLoggedZoomScale) > 0.1 {
                lastLoggedZoomScale = value
                ViewerTrace.log("zoom=\(String(format: "%.2f", value)) id=\(itemID?.prefix(8) ?? "-") state=active")
            }
        } else if !didLogNonFiniteZoom {
            didLogNonFiniteZoom = true
            ViewerTrace.log("zoom=\(scrollView.zoomScale) id=\(itemID?.prefix(8) ?? "-")（非有限值）")
        }
        onZoomChanged?(scrollView.zoomScale)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        lastZoomActivity = CACurrentMediaTime()
        scheduleSettling()
    }
}

#if DEBUG
// 单元测试 I5′ / 交互护栏断言锚点（Release 不编译，docs/16 M12 R01/R02）
extension ZoomableImageCell {
    var test_scrollView: UIScrollView { scrollView }
    var test_zoomContentView: UIView { zoomContentView }
    var test_imageView: UIImageView { imageView }
    var test_cloudBox: UIView { cloudBox }
    /// 单测无 runloop：显式驱动缩放事务进入 settling（生产路径由 DSMotion.zoomActivityGrace 定时器触发）
    func test_flushPendingGeometry() {
        commitPendingGeometry()
    }
}
#endif
