// MARK: - 职责说明：Toast（docs/04 §3.2 规格）——
// 距底部 16pt 黑玻璃胶囊（UIBlurEffect 系统材质），左图标 + 文案，右「撤销」按钮 + 环形倒计时；
// 窗口结束自动收起；尊重「减弱动态效果」（docs/04 §6）与「减弱透明度」（材质降级实色）。

import UIKit

final class DSToast: UIView {
    private let effectView: UIVisualEffectView
    private let iconView = UIImageView()
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.toast)   // 15pt Semibold（docs/04 §5.2）
        label.textColor = DSColor.textPrimary
        return label
    }()
    private let undoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("撤销", for: .normal)
        button.setTitleColor(DSColor.tint, for: .normal)
        button.titleLabel?.font = DSTypography.font(.toast)
        return button
    }()
    /// 环形倒计时描边
    private let ringLayer = CAShapeLayer()
    private var ringTimer: Timer?
    private var ringStart: Date = .distantPast
    private var ringDuration: TimeInterval = 5

    private var onUndo: (() -> Void)?
    private var onDismissFinished: (() -> Void)?

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
        effectView.contentView.addSubview(undoButton)
        addSubview(effectView)

        layer.shadowOpacity = 0.25
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 4)

        iconView.tintColor = DSColor.textPrimary
        iconView.contentMode = .scaleAspectFit

        // 环形倒计时（描边圆，从满到空）
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = DSColor.tint.cgColor
        ringLayer.lineWidth = 2
        ringLayer.lineCap = .round
        undoButton.layer.addSublayer(ringLayer)

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

            undoButton.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -14),
            undoButton.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: undoButton.leadingAnchor, constant: -8),
            effectView.heightAnchor.constraint(equalToConstant: 44),
            undoButton.widthAnchor.constraint(equalToConstant: 44),
            undoButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: undoButton.bounds.midX, y: undoButton.bounds.midY)
        let radius: CGFloat = 17
        ringLayer.frame = undoButton.bounds
        ringLayer.path = UIBezierPath(arcCenter: center,
                                      radius: radius,
                                      startAngle: -.pi / 2,
                                      endAngle: .pi * 1.5,
                                      clockwise: true).cgPath
    }

    /// 展示：autoAdvance 场景由 VC 调用；duration 与 UndoCenter 窗口一致
    func show(icon: String, text: String, duration: TimeInterval, allowUndo: Bool,
              onUndo: (() -> Void)?, onDismissFinished: (() -> Void)?) {
        self.onUndo = onUndo
        self.onDismissFinished = onDismissFinished
        iconView.image = UIImage(systemName: icon)
        messageLabel.text = text
        undoButton.isHidden = !allowUndo
        ringLayer.isHidden = !allowUndo

        ringDuration = duration
        ringStart = Date()
        if allowUndo {
            startRingTimer()
        }

        // 弹入（减弱动效时直接出现，docs/04 §6）
        guard usesMotion else {
            alpha = 1
            transform = .identity
            return
        }
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 20)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func dismiss() {
        stopRingTimer()
        let finish = {
            self.alpha = 0
            self.onDismissFinished?()
        }
        guard usesMotion else {
            finish()
            return
        }
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { _ in finish() })
    }

    /// DEBUG 诊断（Viewer 横幅用；Release 无引用）
    var debugState: String {
        "toast a=\(String(format: "%.1f", alpha)) hidden=\(isHidden) text=\(messageLabel.text ?? "-")"
    }

    // MARK: - 环形倒计时（每帧刷新 strokeEnd）

    private func startRingTimer() {
        stopRingTimer()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickRing()
            }
        }
    }

    private func stopRingTimer() {
        ringTimer?.invalidate()
        ringTimer = nil
    }

    private func tickRing() {
        let elapsed = Date().timeIntervalSince(ringStart)
        let remaining = max(0, 1 - elapsed / ringDuration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.strokeEnd = remaining
        CATransaction.commit()
        if remaining <= 0 {
            stopRingTimer()
            dismiss()
        }
    }
}
