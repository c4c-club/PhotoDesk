// MARK: - 职责说明：缩略图请求规格与缓存键（docs/03 §3 Core/Imaging/ThumbnailRequest）——
// key = localIdentifier + 像素尺寸（docs/03 §5.2），保证同图不同尺寸不互相污染；
// 哈希用 FNV-1a 64（纯实现，不引入 CryptoKit——AGENTS.md §1 系统框架清单外不引入）。

import CoreGraphics
import Foundation

struct ThumbnailRequest: Hashable {
    let id: String
    /// 逻辑尺寸（pt）
    let size: CGSize
    let scale: CGFloat

    /// 像素尺寸（requestImage targetSize 按像素传入）
    var pixelSize: CGSize {
        CGSize(width: max(1, size.width * scale),
               height: max(1, size.height * scale))
    }

    /// 三级缓存统一键（内存 / 磁盘 / 在途合并共用）
    var cacheKey: String {
        Self.cacheKey(id: id, pixelSize: pixelSize)
    }

    static func cacheKey(id: String, pixelSize: CGSize) -> String {
        "\(id)|\(Int(pixelSize.width.rounded()))x\(Int(pixelSize.height.rounded()))"
    }

    /// 缓存键 → 文件名（FNV-1a 64，碰撞概率对唯一 id + 尺寸可忽略）
    var diskFileName: String {
        Self.fnv1a64(cacheKey) + ".jpg"
    }

    static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
