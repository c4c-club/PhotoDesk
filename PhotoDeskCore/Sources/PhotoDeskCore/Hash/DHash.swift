// MARK: - 职责说明：dHash 感知哈希（docs/02 §3.3）——9×8 灰度差值 → 64 bit 指纹。
// 输入约定：行优先灰度 [UInt8]（0...255）且尺寸恰为 9×8（App 侧用 CGContext 渲染到该尺寸；
// 尺寸变换属于取图准备，不属于算法内核——红线 2 下核心包保持 Foundation-only）。
// TODO(P4) 已实现：M2 占位逻辑由本实现取代；单测见 HashAlgorithmTests（同图距离 0 / 旋转 / 加噪）。

public enum DHash {
    public static let requiredWidth = 9
    public static let requiredHeight = 8

    /// - Returns: 64 bit 指纹；输入尺寸不符时返回 nil
    public static func compute(grayscale: [UInt8], width: Int, height: Int) -> UInt64? {
        guard width == requiredWidth, height == requiredHeight, grayscale.count == width * height else {
            return nil
        }
        var hash: UInt64 = 0
        for row in 0..<height {
            for col in 0..<(width - 1) {
                let left = grayscale[row * width + col]
                let right = grayscale[row * width + col + 1]
                if left > right {
                    let bit = UInt64(row * (width - 1) + col)
                    hash |= (1 << bit)
                }
            }
        }
        return hash
    }
}
