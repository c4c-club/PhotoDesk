// MARK: - 职责说明：设计系统字体 token（docs/04 §5.2）——只用系统字体（SF Pro），
// 不引自定义字体；经 UIFontMetrics 缩放以支持动态字体（docs/04 §6 无障碍）。

import UIKit

/// 语义字号（对应 docs/04 §5.2 表格）
enum DSTextStyle {
    /// 大标题 34 Bold
    case largeTitle
    /// 分组头 17 Semibold
    case sectionHeader
    /// 正文 17 Regular
    case body
    /// Toast 15 Semibold
    case toast
    /// 角标 11 Medium
    case badge
}

enum DSTypography {
    /// - Parameter traits: 传入 traitCollection 以参与动态字体缩放（cell 内用 self.traitCollection）
    static func font(_ style: DSTextStyle, compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        switch style {
        case .largeTitle:
            return scaled(.systemFont(ofSize: 34, weight: .bold), .largeTitle, traits)
        case .sectionHeader:
            return scaled(.systemFont(ofSize: 17, weight: .semibold), .headline, traits)
        case .body:
            return scaled(.systemFont(ofSize: 17, weight: .regular), .body, traits)
        case .toast:
            return scaled(.systemFont(ofSize: 15, weight: .semibold), .subheadline, traits)
        case .badge:
            return scaled(.systemFont(ofSize: 11, weight: .medium), .caption2, traits)
        }
    }

    private static func scaled(_ base: UIFont, _ textStyle: UIFont.TextStyle,
                               _ traits: UITraitCollection?) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base, compatibleWith: traits)
    }
}
