// MARK: - 职责说明：EditorTransform 几何测试（docs/05 M6 验收）——
// 比例适配居中裁剪、旋转/翻转重映射保持所选内容、显示尺寸换算、裁剪像素换算、归一化钳制。
// Docker 与 CI core-linux 双跑。

import XCTest
import Foundation
@testable import PhotoDeskCore

final class EditorTransformTests: XCTestCase {
    // MARK: - 默认与中性

    func testDefaultIsNeutral() {
        XCTAssertTrue(EditorTransform().isNeutral)
        var transform = EditorTransform()
        transform.rotate90Clockwise()
        XCTAssertFalse(transform.isNeutral)
    }

    func testQuarterTurnsNormalized() {
        XCTAssertEqual(EditorTransform(quarterTurns: 5).quarterTurns, 1)
        XCTAssertEqual(EditorTransform(quarterTurns: -1).quarterTurns, 3)
        XCTAssertEqual(EditorTransform(quarterTurns: 4).quarterTurns, 0)
    }

    // MARK: - 显示尺寸（奇数次旋转宽高互换）

    func testDisplayedSizeSwapsOnOddTurns() {
        let landscape = EditorTransform(quarterTurns: 0)
        XCTAssertEqual(landscape.displayedSize(originalWidth: 4000, originalHeight: 3000),
                       Size(width: 4000, height: 3000))
        let rotated = EditorTransform(quarterTurns: 1)
        XCTAssertEqual(rotated.displayedSize(originalWidth: 4000, originalHeight: 3000),
                       Size(width: 3000, height: 4000))
        let twice = EditorTransform(quarterTurns: 2)
        XCTAssertEqual(twice.displayedSize(originalWidth: 4000, originalHeight: 3000),
                       Size(width: 4000, height: 3000))
    }

    // MARK: - 裁剪像素换算

    func testCropRectPixels() {
        let transform = EditorTransform(cropX: 0.25, cropY: 0.5,
                                        cropWidth: 0.5, cropHeight: 0.25,
                                        quarterTurns: 0)
        let rect = transform.cropRectPixels(originalWidth: 1000, originalHeight: 800)
        XCTAssertEqual(rect.x, 250)
        XCTAssertEqual(rect.y, 400)
        XCTAssertEqual(rect.width, 500)
        XCTAssertEqual(rect.height, 200)
    }

    func testCropRectPixelsAfterRotation() {
        // 旋转 1 次（4000×3000 → 显示 3000×4000）：归一化裁剪按显示尺寸换算
        let transform = EditorTransform(cropX: 0, cropY: 0,
                                        cropWidth: 0.5, cropHeight: 0.5,
                                        quarterTurns: 1)
        let rect = transform.cropRectPixels(originalWidth: 4000, originalHeight: 3000)
        XCTAssertEqual(rect.width, 1500)   // 0.5 × 显示宽 3000
        XCTAssertEqual(rect.height, 2000)  // 0.5 × 显示高 4000
    }

    // MARK: - 比例适配（居中裁剪）

    func testAspectCropWideTarget() {
        // 原图 4:3（displayAspect ≈ 1.333），目标 16:9（≈1.778）更宽 → 宽度占满、上下裁
        let transform = EditorTransform.centeredCropRect(for: 16.0 / 9.0, displayAspect: 4.0 / 3.0)
        XCTAssertEqual(transform.cropX, 0, accuracy: 0.0001)
        XCTAssertEqual(transform.cropWidth, 1, accuracy: 0.0001)
        XCTAssertEqual(transform.cropHeight, (4.0 / 3.0) / (16.0 / 9.0), accuracy: 0.0001)
        XCTAssertEqual(transform.cropY, (1 - transform.cropHeight) / 2, accuracy: 0.0001)
    }

    func testAspectCropTallTarget() {
        // 原图 4:3，目标 3:4（0.75）更窄 → 高度占满、左右裁
        let transform = EditorTransform.centeredCropRect(for: 3.0 / 4.0, displayAspect: 4.0 / 3.0)
        XCTAssertEqual(transform.cropY, 0, accuracy: 0.0001)
        XCTAssertEqual(transform.cropHeight, 1, accuracy: 0.0001)
        XCTAssertEqual(transform.cropWidth, (3.0 / 4.0) / (4.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(transform.cropX, (1 - transform.cropWidth) / 2, accuracy: 0.0001)
    }

    func testFreeAndOriginalGiveFullRect() {
        XCTAssertTrue(EditorTransform.centeredCropRect(for: nil, displayAspect: 1.5).isNeutral)
        XCTAssertTrue(EditorTransform.centeredCropRect(for: 1.5, displayAspect: 1.5).isNeutral)
    }

    // MARK: - 旋转/翻转重映射（所选内容保持）

    func testRotateRemapsCropRect() {
        // 右上角小裁剪块（x=0.5..1, y=0..0.5）
        var transform = EditorTransform(cropX: 0.5, cropY: 0.0,
                                        cropWidth: 0.5, cropHeight: 0.5)
        transform.rotate90Clockwise()
        // 顺时针 90°：右上块 → 右下块（nx = 1 - y - h = 0.5, ny = x = 0.5）
        XCTAssertEqual(transform.cropX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.cropY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.cropWidth, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.cropHeight, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.quarterTurns, 1)
    }

    func testRotateFourTimesReturnsToOriginal() {
        var transform = EditorTransform(cropX: 0.3, cropY: 0.2,
                                        cropWidth: 0.4, cropHeight: 0.3)
        let original = transform
        for _ in 0..<4 { transform.rotate90Clockwise() }
        // 浮点累积误差：按分量精度比较
        XCTAssertEqual(transform.cropX, original.cropX, accuracy: 1e-9)
        XCTAssertEqual(transform.cropY, original.cropY, accuracy: 1e-9)
        XCTAssertEqual(transform.cropWidth, original.cropWidth, accuracy: 1e-9)
        XCTAssertEqual(transform.cropHeight, original.cropHeight, accuracy: 1e-9)
        XCTAssertEqual(transform.quarterTurns, original.quarterTurns)
    }

    func testFlipRemapsCropRect() {
        // 左上角块 → 翻转后右上角块
        var transform = EditorTransform(cropX: 0.0, cropY: 0.0,
                                        cropWidth: 0.5, cropHeight: 0.5)
        transform.flipHorizontally()
        XCTAssertEqual(transform.cropX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(transform.cropY, 0, accuracy: 0.0001)
        XCTAssertTrue(transform.isHorizontallyFlipped)

        transform.flipHorizontally()   // 再翻回
        XCTAssertEqual(transform.cropX, 0, accuracy: 0.0001)
        XCTAssertFalse(transform.isHorizontallyFlipped)
    }

    // MARK: - 钳制

    func initClampsValues() {
        let transform = EditorTransform(cropX: -0.5, cropY: 1.5,
                                        cropWidth: 2.0, cropHeight: -1)
        XCTAssertEqual(transform.cropX, 0)
        XCTAssertEqual(transform.cropY, 1)
        XCTAssertLessThanOrEqual(transform.cropWidth, 1 - transform.cropX)
        XCTAssertGreaterThan(transform.cropHeight, 0)
    }
}
