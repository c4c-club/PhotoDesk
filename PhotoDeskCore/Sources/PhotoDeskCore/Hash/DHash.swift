// MARK: - 职责说明：dHash 感知哈希（docs/02 §3.3）——9×8 灰度差值 → 64 bit 指纹。
// 输入为基础类型（行优先灰度 [UInt8] + 宽高），App 侧 FingerprintService 负责从缩略图取灰度（红线 2）。
// TODO(P4): 实现 + 单测（同图距离 0；旋转/压缩后距离小；与 pHash 组合策略）。

public enum DHash {
    /// - Parameters:
    ///   - grayscale: 行优先灰度像素（0...255），count 应为 width * height
    ///   - width / height: 灰度图尺寸
    /// - Returns: 64 bit 指纹；输入尺寸不足（宽 < 9 或高 < 8）时返回 nil
    public static func compute(grayscale: [UInt8], width: Int, height: Int) -> UInt64? {
        // TODO(P4): 缩放至 9×8 → 相邻像素差值 → 64 bit
        return nil
    }
}
