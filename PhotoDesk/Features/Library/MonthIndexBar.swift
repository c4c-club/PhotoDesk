// MARK: - 职责说明：右侧月份快速索引条 v2（docs/04 §3.1 + docs/13 S09 增强）——自定义 UIControl：
// 每个月分组一个刻度（跨年处显示年份文本，其余为圆点）；拖动实时回调跳转分组；
// v2：拖动时左侧浮层显示「2024年5月」（Entry.detail）、AX 标识 MonthIndexBar + 共 N 个月。
// 符合 UIControl 触控语义（begin/continue/end）。

import UIKit

final class MonthIndexBar: UIControl {
    struct Entry: Equatable {
        /// 显示文本；nil = 圆点刻度
        let label: String?
        /// 拖动浮层文本（月份完整标题，如「2024年5月」）；nil 不显示浮层
        var detail: String? = nil
    }

    private(set) var entries: [Entry] = []
    private(set) var highlightedIndex: Int = -1
    /// 拖动/点按改变选中组时回调（主线程）
    var onIndexChange: ((Int) -> Void)?

    /// 拖动浮层（条形左侧，显示当前月份标题）
    private let overlayLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.isHidden = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private var overlayCenterYConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(overlayLabel)
        let centerY = overlayLabel.centerYAnchor.constraint(equalTo: topAnchor)
        overlayCenterYConstraint = centerY
        NSLayoutConstraint.activate([
            centerY,
            overlayLabel.trailingAnchor.constraint(equalTo: leadingAnchor, constant: -8),
            overlayLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            overlayLabel.heightAnchor.constraint(equalToConstant: 28),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityIdentifier = "MonthIndexBar"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    // MARK: - 数据

    func update(entries: [Entry], highlightedIndex: Int) {
        self.entries = entries
        self.highlightedIndex = highlightedIndex
        accessibilityValue = "共 \(entries.count) 个月"
        setNeedsDisplay()
    }

    func setHighlighted(index: Int, notify: Bool) {
        guard index != highlightedIndex, index >= -1, index < entries.count else { return }
        highlightedIndex = index
        setNeedsDisplay()
        if notify {
            onIndexChange?(index)
        }
    }

    // MARK: - 触控

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateIndex(for: touch, notify: true)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateIndex(for: touch, notify: true)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        highlightedIndex = -1
        hideOverlay()
        setNeedsDisplay()
    }

    override func cancelTracking(with event: UIEvent?) {
        highlightedIndex = -1
        hideOverlay()
        setNeedsDisplay()
    }

    private func updateIndex(for touch: UITouch, notify: Bool) {
        guard !entries.isEmpty else { return }
        let y = touch.location(in: self).y
        let step = bounds.height / CGFloat(entries.count)
        let index = min(entries.count - 1, max(0, Int(y / step)))
        setHighlighted(index: index, notify: notify)
        showOverlay(for: index)
    }

    // MARK: - 拖动浮层（docs/13 S09：显示「2024年5月」）

    private func showOverlay(for index: Int) {
        guard index >= 0, index < entries.count, let detail = entries[index].detail else {
            hideOverlay()
            return
        }
        overlayLabel.text = detail
        overlayLabel.isHidden = false
        // 浮层纵向跟随当前刻度
        let step = bounds.height / CGFloat(max(1, entries.count))
        overlayCenterYConstraint?.constant = step * (CGFloat(index) + 0.5)
    }

    private func hideOverlay() {
        overlayLabel.isHidden = true
    }

    // MARK: - 绘制

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !entries.isEmpty else { return }
        let step = rect.height / CGFloat(entries.count)
        let labelFont = UIFont.systemFont(ofSize: 9, weight: .medium)

        for (index, entry) in entries.enumerated() {
            let centerY = rect.minY + step * (CGFloat(index) + 0.5)
            let isHighlighted = (index == highlightedIndex)
            let color = isHighlighted ? DSColor.tint.resolvedColor(with: traitCollection)
                                      : DSColor.textSecondary.resolvedColor(with: traitCollection).withAlphaComponent(0.7)

            if let label = entry.label {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: isHighlighted ? UIFont.systemFont(ofSize: 10, weight: .bold) : labelFont,
                    .foregroundColor: color,
                ]
                let size = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(at: CGPoint(x: rect.maxX - size.width - 2,
                                                     y: centerY - size.height / 2),
                                         withAttributes: attributes)
            } else {
                let dot = isHighlighted ? 3.0 : 2.0
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: CGRect(x: rect.maxX - 8, y: centerY - dot / 2, width: dot, height: dot))
            }
        }
    }
}
