// MARK: - 职责说明：模糊检测（docs/03 §5.5 / docs/05 M4 任务 4.6）——
// 3×3 拉普拉斯卷积 + 方差统计：方差 < 阈值（默认 60，0-255 灰度域）判为模糊。
// 输入约定：行优先灰度 [UInt8]（推荐 128×128，App 侧渲染；核心纯 Swift，Foundation-only，红线 2）。
// 阈值由设置提供（docs/04：模糊阈值可调）。

import Foundation

public enum BlurDetector {
    /// 拉普拉斯响应 = 上 + 下 + 左 + 右 - 4×中心（3×3 拉普拉斯核与像素的离散卷积）
    /// - Returns: 响应方差；输入尺寸 < 3 时返回 nil
    public static func laplacianVariance(grayscale: [UInt8], width: Int, height: Int) -> Double? {
        guard width >= 3, height >= 3, grayscale.count == width * height else { return nil }

        var responses = [Double]()
        responses.reserveCapacity((width - 2) * (height - 2))
        var sum = 0.0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Int(grayscale[y * width + x])
                let top = Int(grayscale[(y - 1) * width + x])
                let bottom = Int(grayscale[(y + 1) * width + x])
                let left = Int(grayscale[y * width + x - 1])
                let right = Int(grayscale[y * width + x + 1])
                let laplacian = top + bottom + left + right - 4 * center
                responses.append(Double(laplacian))
                sum += Double(laplacian)
            }
        }

        let count = Double(responses.count)
        guard count > 0 else { return nil }
        let mean = sum / count
        let variance = responses.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / count
        return variance
    }

    /// - Parameter threshold: 方差阈值（默认 60，设置 blur.varianceThreshold 可调）
    public static func isBlurry(variance: Double, threshold: Double = 60) -> Bool {
        variance < threshold
    }
}
