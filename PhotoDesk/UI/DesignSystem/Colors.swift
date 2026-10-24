// MARK: - 职责说明：设计系统颜色 token（docs/04 §5.1）——全项目唯一取色入口，
// 禁止在 View 里硬编码 Color(...)（AGENTS.md §5）；深浅色经动态 UIColor 支持，跟随系统切换。

import UIKit
import SwiftUI

enum DSColor {
    private static func dynamic(light: UInt32, lightAlpha: CGFloat = 1,
                                dark: UInt32, darkAlpha: CGFloat = 1) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        }
    }

    /// 网格背景
    static let bgPrimary = dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// 浏览页背景（恒黑，docs/04 §1「照片是主角」）
    static let bgViewer = UIColor(hex: 0x000000)
    /// 分组头 / 卡片背景
    static let bgSecondary = dynamic(light: 0xF2F2F7, dark: 0x1C1C1E)
    /// 主文本
    static let textPrimary = dynamic(light: 0x1C1C1E, dark: 0xF2F2F7)
    /// 次文本
    static let textSecondary = dynamic(light: 0x8E8E93, dark: 0x8E8E93)
    /// 主色调
    static let tint = dynamic(light: 0x007AFF, dark: 0x0A84FF)
    /// 收藏（琥珀）
    static let accentFavorite = dynamic(light: 0xFFB300, dark: 0xFFC233)
    /// 隐藏（靛蓝）
    static let accentHide = dynamic(light: 0x5C6BC0, dark: 0x8C9EFF)
    /// 移到最近删除（红）
    static let accentDelete = dynamic(light: 0xE53935, dark: 0xFF5252)
    /// 分割线（浅色 30% / 深色 60%）
    static let separator = dynamic(light: 0xC6C6C8, lightAlpha: 0.3, dark: 0x38383A, darkAlpha: 0.6)
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: alpha)
    }
}

extension Color {
    /// DesignSystem token → SwiftUI Color（Color(uiColor:) 为 iOS 15 公开 API）
    init(ds color: UIColor) {
        self.init(uiColor: color)
    }
}
