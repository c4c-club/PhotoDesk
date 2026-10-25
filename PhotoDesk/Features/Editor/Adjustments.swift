// MARK: - 职责说明：编辑调整参数（docs/05 M6 任务 6.2）——
// 五滑杆中性值结构（Core Image 滤镜值域映射在 fromSliders）。
// Codable：作为 PHAdjustmentData 载荷持久化（重启后系统交回数据可复现编辑）。
// Foundation-only 值类型。

import Foundation

public struct RenderAdjustments: Equatable, Codable {
    /// -1...1（0 = 中性）
    public var brightness: Double
    /// 0.5...1.5（1 = 中性）
    public var contrast: Double
    /// 0...2（1 = 中性）
    public var saturation: Double
    /// 色温开尔文 4000...8000（6500 = 中性）
    public var temperature: Double
    /// 0...2（0 = 中性，CISharpenLuminance）
    public var sharpness: Double

    public init(brightness: Double = 0,
                contrast: Double = 1,
                saturation: Double = 1,
                temperature: Double = 6500,
                sharpness: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.sharpness = sharpness
    }

    public static let neutral = RenderAdjustments()

    public var isNeutral: Bool { self == .neutral }

    /// 滑杆 UI（-1...1 归一）→ 参数
    public static func fromSliders(brightness: Double, contrast: Double, saturation: Double,
                                   temperature: Double, sharpness: Double) -> RenderAdjustments {
        RenderAdjustments(brightness: brightness * 0.3,
                          contrast: 1 + contrast * 0.5,
                          saturation: max(0, 1 + saturation),
                          temperature: 6500 + temperature * 1500,
                          sharpness: max(0, sharpness))
    }
}
