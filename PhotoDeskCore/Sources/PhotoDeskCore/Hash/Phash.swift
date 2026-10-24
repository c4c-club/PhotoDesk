// MARK: - 职责说明：pHash 感知哈希（docs/02 §3.3）——DCT 8×8 低频分量 → 64 bit 指纹，抗压缩/缩放更强。
// 输入为基础类型（行优先灰度 [UInt8] + 宽高），与 DHash 同一套适配约定（红线 2）。
// TODO(P4): 实现（32×32 灰度 → DCT → 左上 8×8 → 中位数比较）+ 单测。

public enum PHash {
    /// - Parameters:
    ///   - grayscale: 行优先灰度像素（0...255），count 应为 width * height
    ///   - width / height: 灰度图尺寸
    /// - Returns: 64 bit 指纹；输入尺寸不足（宽 < 32 或高 < 32）时返回 nil
    public static func compute(grayscale: [UInt8], width: Int, height: Int) -> UInt64? {
        // TODO(P4): 32×32 → DCT-II → 8×8 低频 → 中位数二值化
        return nil
    }
}
