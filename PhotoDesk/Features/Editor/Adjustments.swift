// MARK: - 职责说明：编辑调整参数（docs/05 M6 任务 6.2）——
// 五滑杆中性值结构（Core Image 滤镜值域映射在 EditorViewModel.renderCIImage）。
// Foundation-only 纯值类型（可序列化为 PHAdjustmentData）。

import Foundation

public struct Adjustments: Equatable, Codable {
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

    public static let neutral = Adjustments()

    public var isNeutral: Bool { self == .neutral }
}
