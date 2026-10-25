// MARK: - 职责说明：编辑几何变换（docs/05 M6 任务 6.1）——
// 裁剪（归一化矩形，显示坐标系）+ 90° 旋转（0-3 圈）+ 水平翻转的状态与几何换算。
// 约定：渲染管线 = 原图 → 旋转 quarterTurns 次（顺时针）→ 水平翻转 → 按裁剪矩形裁切 → 输出。
// 纯 Foundation 几何（红线 2）；App 侧换算为 CGAffineTransform/CGRect 后作用于 CIImage。
// 旋转/翻转按钮重映射裁剪矩形，保证「已选内容」不丢（EditorTransformTests 验证）。

import Foundation

/// 裁剪比例预设（自由 = 不约束）
public struct CropAspectRatio: Equatable {
    public let name: String
    /// 目标宽高比（宽/高）；nil = 自由
    public let ratio: Double?

    public init(name: String, ratio: Double?) {
        self.name = name
        self.ratio = ratio
    }

    public static let free = CropAspectRatio(name: "自由", ratio: nil)
    public static let original = CropAspectRatio(name: "原比例", ratio: nil)   // ratio 由调用方按原图填
    public static let square = CropAspectRatio(name: "1:1", ratio: 1)
    public static let ratio4x3 = CropAspectRatio(name: "4:3", ratio: 4.0 / 3.0)
    public static let ratio16x9 = CropAspectRatio(name: "16:9", ratio: 16.0 / 9.0)
    public static let ratio3x4 = CropAspectRatio(name: "3:4", ratio: 3.0 / 4.0)
    public static let ratio9x16 = CropAspectRatio(name: "9:16", ratio: 9.0 / 16.0)

    public static let presets: [CropAspectRatio] = [.free, .original, .square, .ratio4x3, .ratio16x9, .ratio3x4, .ratio9x16]
}

/// 像素尺寸（displayedSize 返回值；核心包无 CGGeometry，自定义最小结构）
public struct Size: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// 旋转/翻转/裁剪状态（值类型，可比较可序列化）
public struct EditorTransform: Equatable {
    /// 裁剪矩形（显示坐标系归一化 0...1，宽高 > 0）
    public var cropX: Double
    public var cropY: Double
    public var cropWidth: Double
    public var cropHeight: Double
    /// 顺时针 90° 旋转次数（0...3）
    public var quarterTurns: Int
    public var isHorizontallyFlipped: Bool

    public init(cropX: Double = 0, cropY: Double = 0,
                cropWidth: Double = 1, cropHeight: Double = 1,
                quarterTurns: Int = 0, isHorizontallyFlipped: Bool = false) {
        self.cropX = min(1, max(0, cropX))
        self.cropY = min(1, max(0, cropY))
        self.cropWidth = min(1 - self.cropX, max(0.01, cropWidth))
        self.cropHeight = min(1 - self.cropY, max(0.01, cropHeight))
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.isHorizontallyFlipped = isHorizontallyFlipped
    }

    /// 是否未做任何几何修改
    public var isNeutral: Bool {
        cropX == 0 && cropY == 0 && cropWidth == 1 && cropHeight == 1
            && quarterTurns == 0 && !isHorizontallyFlipped
    }

    /// 旋转/翻转后的显示尺寸（宽高在奇数次旋转时互换）
    public func displayedSize(originalWidth: Int, originalHeight: Int) -> Size {
        quarterTurns % 2 == 1
            ? Size(width: originalHeight, height: originalWidth)
            : Size(width: originalWidth, height: originalHeight)
    }

    /// 裁剪矩形在「显示后像素空间」中的位置与尺寸
    public func cropRectPixels(originalWidth: Int, originalHeight: Int)
        -> (x: Int, y: Int, width: Int, height: Int) {
        let size = displayedSize(originalWidth: originalWidth, originalHeight: originalHeight)
        return (Int((cropX * Double(size.width)).rounded()),
                Int((cropY * Double(size.height)).rounded()),
                max(1, Int((cropWidth * Double(size.width)).rounded())),
                max(1, Int((cropHeight * Double(size.height)).rounded())))
    }

    /// 顺时针旋转 90°：显示空间整体旋转，裁剪矩形重映射保持所选内容
    public mutating func rotate90Clockwise() {
        let newX = 1 - cropY - cropHeight
        let newY = cropX
        let newW = cropHeight
        let newH = cropWidth
        cropX = newX
        cropY = newY
        cropWidth = newW
        cropHeight = newH
        quarterTurns = (quarterTurns + 1) % 4
    }

    /// 水平翻转：裁剪矩形水平镜像重映射
    public mutating func flipHorizontally() {
        cropX = 1 - cropX - cropWidth
        isHorizontallyFlipped.toggle()
    }

    /// 按比例预设返回居中裁剪矩形（自由 → 全幅；原比例 → 全幅）
    public static func centeredCropRect(for ratio: Double?, displayAspect: Double) -> EditorTransform {
        guard let target = ratio, target > 0, displayAspect > 0 else { return EditorTransform() }
        var width = 1.0
        var height = 1.0
        if target > displayAspect {
            // 目标更宽：宽度占满，高度 = displayAspect / target
            height = displayAspect / target
        } else {
            // 目标更高：高度占满，宽度 = target / displayAspect
            width = target / displayAspect
        }
        return EditorTransform(cropX: (1 - width) / 2,
                               cropY: (1 - height) / 2,
                               cropWidth: width,
                               cropHeight: height)
    }
}
