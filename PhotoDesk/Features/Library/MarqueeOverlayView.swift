// MARK: - 职责说明：框选矩形覆盖层（M17 T06，docs/32 §2.5）——单层 CALayer 承载 12pt 圆角
// 矩形：选择模式 tint 10% 填充 + 1.5pt 描边，取消模式 danger 8% 填充 + 1.5pt 描边；
// 每帧只改 frame 不重建（G7 性能预算）；不拦截触摸、不进 AX 树。

import UIKit

final class MarqueeOverlayView: UIView {

    private(set) var isDeselectMode = false

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.borderWidth = 1.5
        applyColors(deselect: false)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "Marquee-Overlay"
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用（纯代码视图）")
    }

    /// 取消模式配色切换（fill 10%→8%，stroke tint→danger）
    func setDeselectMode(_ deselect: Bool) {
        guard isDeselectMode != deselect else { return }
        isDeselectMode = deselect
        applyColors(deselect: deselect)
    }

    /// 每帧只改 frame（docs/32 §2.5 G7：不重建 layer）；nil = 隐藏
    func update(rect: CGRect?) {
        guard let rect else {
            isHidden = true
            return
        }
        frame = rect
        isHidden = false
    }

    /// 深浅色跟随（动态 UIColor 的 cgColor 需要显式刷新）
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            applyColors(deselect: isDeselectMode)
        }
    }

    private func applyColors(deselect: Bool) {
        let color = deselect ? DSColor.danger : DSColor.tint
        backgroundColor = color.withAlphaComponent(deselect ? 0.08 : 0.10)
        layer.borderColor = color.cgColor
    }
}
