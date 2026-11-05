// MARK: - 职责说明：Toast v3（docs/04 §3.2 规格 + docs/13 S05 + docs/16 M12 R04）——
// 距底部黑玻璃胶囊：左图标 + 文案 + 独立环形倒计时视图 + 「撤销」按钮。
// v3 修复（R04）：① 倒计时环移入独立 countdownRingView（自身 layoutSubviews 用自身 bounds 画路径，
//   尺寸 DSSpacing.toastRingSize，置于「撤销」按钮外侧——旧版环层叠在撤销文字上）；
// ② 唯一时钟：倒计时由 AppContainer.shared.undoCountdownDriver 驱动（30fps 单泵），
//   本视图只渲染 updateRing(fraction)，删除内部自算到期与自行 dismiss 分支（与 UndoCenter 双时钟根因）；
// ③ 动态字体：effectView.heightAnchor >= 44、按钮最小命中区 >= 44（旧版 equal 44 在放大字体下裁切）；
// ④ 保留 S05 修复：全部子视图关 autoresizing、init 即隐藏、dismiss 后 isHidden、generation 令牌、
//   hitTest 只放行撤销按钮（Toast 本体不拦截网格/工具栏触摸）。

import UIKit

final class DSToast: UIView {
    /// 独立倒计时环（R04：不再挂在 undoButton.layer 上，不与文字重叠）
    private final class CountdownRingView: UIView {
        let ringLayer = CAShapeLayer()
        var progress: CGFloat = 1 {
            didSet {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                ringLayer.strokeEnd = max(0, min(1, progress))
                CATransaction.commit()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            ringLayer.fillColor = UIColor.clear.cgColor
            ringLayer.strokeColor = DSColor.tint.cgColor
            ringLayer.lineWidth = 2
            ringLayer.lineCap = .round
            layer.addSublayer(ringLayer)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) 未使用")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // 环路径用自身 bounds 计算（不依赖 undoButton.bounds——动态字体变化后自然同步）
            ringLayer.frame = bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = max(1, min(bounds.width, bounds.height) / 2 - ringLayer.lineWidth / 2)
            ringLayer.path = UIBezierPath(arcCenter: center,
                                          radius: radius,
                                          startAngle: -.pi / 2,
                                          endAngle: .pi * 1.5,
                                          clockwise: true).cgPath
        }
    }

    private let effectView: UIVisualEffectView
    private let iconView = UIImageView()
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.toast)   // 15pt Semibold（docs/04 §5.2）
        label.textColor = DSColor.textPrimary
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let undoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("撤销", for: .normal)
        button.setTitleColor(DSColor.tint, for: .normal)
        button.titleLabel?.font = DSTypography.font(.toast)
        button.titleLabel?.adjustsFontForContentSizeCategory = true   // R04：动态字体跟随
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        button.accessibilityIdentifier = "Toast-Undo"
        return button
    }()
    /// 独立环形倒计时视图（R04 ①）
    private let countdownRingView = CountdownRingView()
    /// 倒计时会话 id（唯一时钟驱动；dismiss/show 时换签）
    private var countdownSession: UUID?
    /// 最近一次展示时长（环渲染用）
    private var ringDuration: TimeInterval = 5

    private var onUndo: (() -> Void)?
    private var onExpire: (() -> Void)?
    private var onDismissFinished: (() -> Void)?
    /// 展示代际：新的 show 使旧 dismiss 的完成回调失效（docs/13 S05）
    private var generation = 0

    private var usesMotion: Bool {
        !(UIAccessibility.isReduceMotionEnabled && AppContainer.shared.settings.respectReduceMotion)
    }

    override init(frame: CGRect) {
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        effectView = UIVisualEffectView(effect: blur)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    private func setup() {
        accessibilityIdentifier = "DSToast"   // 稳定性 UI 测试锚点（S05：断言不可命中）
        // 减弱透明度：材质降级为实色（docs/04 §6）
        if UIAccessibility.isReduceTransparencyEnabled {
            effectView.effect = nil
            effectView.backgroundColor = DSColor.bgSecondary
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = 22
        effectView.layer.masksToBounds = true
        effectView.contentView.addSubview(iconView)
        effectView.contentView.addSubview(messageLabel)
        effectView.contentView.addSubview(countdownRingView)
        effectView.contentView.addSubview(undoButton)
        addSubview(effectView)

        // docs/13 S05 根因 1：三个内容子视图必须关闭 autoresizing（旧版缺失 → 塌陷成空玻璃胶囊）
        iconView.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownRingView.translatesAutoresizingMaskIntoConstraints = false
        undoButton.translatesAutoresizingMaskIntoConstraints = false

        layer.shadowOpacity = 0.25
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 4)

        iconView.tintColor = DSColor.textPrimary
        iconView.contentMode = .scaleAspectFit

        undoButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onUndo?()
            self.dismiss()
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            messageLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),

            // R04 ②：环在「撤销」按钮外侧（左），不与文字重叠；尺寸进 token
            countdownRingView.trailingAnchor.constraint(equalTo: undoButton.leadingAnchor, constant: -6),
            countdownRingView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            countdownRingView.widthAnchor.constraint(equalToConstant: DSSpacing.toastRingSize),
            countdownRingView.heightAnchor.constraint(equalToConstant: DSSpacing.toastRingSize),

            undoButton.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -14),
            undoButton.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: countdownRingView.leadingAnchor, constant: -8),
            // R04 ③：动态字体——高度下限 44（去掉 equal 44 硬约束），按钮最小命中区 44
            effectView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            undoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            undoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        // docs/13 S05 根因 3：init 即隐藏——不占位、不参与命中测试
        isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // effectView >= 44 + 按钮动态字体可能撑高：内容视图跟随实际高度居中（Auto Layout 已保证，
        // 这里只处理 cornerRadius 跟随）
        effectView.layer.cornerRadius = min(22, bounds.height / 2)
    }

    // MARK: - 命中测试隔离（docs/13 S05 根因 4：只放行撤销按钮，其余区域不拦截）

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, !undoButton.isHidden else { return nil }
        let undoPoint = convert(point, to: undoButton)
        guard undoButton.bounds.contains(undoPoint) else { return nil }
        return undoButton
    }

    /// 展示：duration 为唯一时长来源（settings.undoWindow）；倒计时由 UndoCountdownDriver 驱动。
    /// allowUndo=false：环与按钮都隐藏且不注册驱动会话（R04 ④）。
    func show(icon: String, text: String, duration: TimeInterval, allowUndo: Bool,
              onUndo: (() -> Void)?, onExpire: (() -> Void)? = nil,
              onDismissFinished: (() -> Void)?) {
        generation += 1
        self.onUndo = onUndo
        self.onExpire = onExpire
        self.onDismissFinished = onDismissFinished
        iconView.image = UIImage(systemName: icon)
        messageLabel.text = text
        undoButton.isHidden = !allowUndo
        countdownRingView.isHidden = !allowUndo

        isHidden = false
        ringDuration = max(0.05, duration)
        countdownRingView.progress = allowUndo ? 1 : 0
        restartCountdown(allowUndo: allowUndo)

        // 弹入（减弱动效时直接出现，docs/04 §6）
        guard usesMotion else {
            alpha = 1
            transform = .identity
            return
        }
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 20)
        UIView.animate(withDuration: DSMotion.toastDuration, delay: 0, options: DSMotion.fadeOptions) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func dismiss() {
        cancelCountdown()
        let currentGeneration = generation
        let finish = { [weak self] in
            guard let self, currentGeneration == self.generation else { return }
            self.alpha = 0
            self.isHidden = true   // docs/13 S05：dismiss 完成必须隐藏（旧版只 alpha=0 仍拦截触摸）
            self.onDismissFinished?()
        }
        guard usesMotion else {
            finish()
            return
        }
        UIView.animate(withDuration: DSMotion.toastDuration, animations: {
            self.alpha = 0
        }, completion: { _ in finish() })
    }

    /// DEBUG 诊断（Viewer 横幅用；Release 无引用）
    var debugState: String {
        "toast a=\(String(format: "%.1f", alpha)) hidden=\(isHidden) text=\(messageLabel.text ?? "-")"
    }

    // MARK: - 倒计时（唯一时钟驱动；R04 ②：本视图不再自算到期/自行 dismiss）

    private func restartCountdown(allowUndo: Bool) {
        cancelCountdown()
        guard allowUndo else { return }
        let generation = self.generation
        let duration = ringDuration
        countdownSession = AppContainer.shared.undoCountdownDriver.start(
            duration: duration,
            onTick: { [weak self] fraction in
                guard let self, self.generation == generation else { return }
                self.updateRing(fraction: fraction)
            },
            onExpire: { [weak self] in
                guard let self, self.generation == generation else { return }
                let expire = self.onExpire
                self.dismiss()
                expire?()   // 提交/到期清理由调用方完成（驱动统一到点触发）
            })
    }

    private func cancelCountdown() {
        if let session = countdownSession {
            AppContainer.shared.undoCountdownDriver.cancel(id: session)
            countdownSession = nil
        }
    }

    /// 环渲染（唯一职责）：fraction 0...1，先做有限值守卫
    private func updateRing(fraction: Double) {
        guard fraction.isFinite else { return }
        countdownRingView.progress = CGFloat(max(0, min(1, fraction)))
    }
}

#if DEBUG
// 单元测试断言锚点（docs/16 M12 R04；Release 不编译）
extension DSToast {
    var test_countdownRingView: UIView { countdownRingView }
    var test_undoButton: UIButton { undoButton }
    var test_effectView: UIView { effectView }
    var test_messageLabel: UILabel { messageLabel }
}
#endif
