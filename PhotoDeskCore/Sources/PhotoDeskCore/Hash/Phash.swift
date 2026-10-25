// MARK: - 职责说明：pHash 感知哈希（docs/02 §3.3）——32×32 灰度 → DCT-II 取左上 8×8 → 中位数二值化 → 64 bit。
// 抗压缩/缩放能力强于 dHash，与 dHash 组合提升去重置信度（docs/03 §5.4）。
// 输入约定：行优先灰度 [UInt8]，尺寸恰为 32×32（App 侧 CGContext 渲染；红线 2 下核心包 Foundation-only）。

import Foundation

public enum PHash {
    public static let requiredSize = 32
    public static let outputSize = 8

    /// - Returns: 64 bit 指纹；输入尺寸不符时返回 nil
    public static func compute(grayscale: [UInt8], width: Int, height: Int) -> UInt64? {
        guard width == requiredSize, height == requiredSize, grayscale.count == width * height else {
            return nil
        }
        // 预计算余弦表：cosTable[x][u] = cos((2x+1)·uπ / (2N))
        var cosTable = [[Double]](repeating: [Double](repeating: 0, count: outputSize), count: width)
        let denominator = 2.0 * Double(width)
        for x in 0..<width {
            for u in 0..<outputSize {
                cosTable[x][u] = cos(((2.0 * Double(x) + 1.0) * Double(u) * .pi) / denominator)
            }
        }

        // 二维 DCT-II，取左上 8×8 低频分量
        var dct = [[Double]](repeating: [Double](repeating: 0, count: outputSize), count: outputSize)
        for u in 0..<outputSize {
            for v in 0..<outputSize {
                var sum = 0.0
                for x in 0..<width {
                    let cx = cosTable[x][u]
                    let row = x * width
                    for y in 0..<height {
                        sum += Double(grayscale[row + y]) * cx * cosTable[y][v]
                    }
                }
                dct[u][v] = sum
            }
        }

        // 中位数（排除 DC 分量 F[0][0]）
        var values = [Double]()
        values.reserveCapacity(outputSize * outputSize - 1)
        for u in 0..<outputSize {
            for v in 0..<outputSize where !(u == 0 && v == 0) {
                values.append(dct[u][v])
            }
        }
        values.sort()
        let median = values[values.count / 2]

        var hash: UInt64 = 0
        for u in 0..<outputSize {
            for v in 0..<outputSize {
                if dct[u][v] > median {
                    let bit = UInt64(u * outputSize + v)
                    hash |= (1 << bit)
                }
            }
        }
        return hash
    }
}
