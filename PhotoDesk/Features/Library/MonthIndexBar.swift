// MARK: - 职责说明：右侧月份快速索引条（docs/04 §3.1）——自定义 UIControl：
// 每个月分组一个刻度（跨年处显示年份文本，其余为圆点）；拖动实时回调跳转分组；
// 高亮由外部（滚动同步）或拖动设置。符合 UIControl 触控语义（begin/continue/end）。

import UIKit

final class MonthIndexBar: UIControl {
    struct Entry: Equatable {
        /// 显示文本；nil = 圆点刻度
        let label: String?
    }

    private(set) var entries: [Entry] = []
    private(set) var highlightedIndex: Int = -1
    /// 拖动/点按改变选中组时回调（主线程）
    var onIndexChange: ((Int) -> Void)?

    // MARK: - 数据

    func update(entries: [Entry], highlightedIndex: Int) {
        self.entries = entries
        self.highlightedIndex = highlightedIndex
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
        setNeedsDisplay()
    }

    private func updateIndex(for touch: UITouch, notify: Bool) {
        guard !entries.isEmpty else { return }
        let y = touch.location(in: self).y
        let step = bounds.height / CGFloat(entries.count)
        let index = min(entries.count - 1, max(0, Int(y / step)))
        setHighlighted(index: index, notify: notify)
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
