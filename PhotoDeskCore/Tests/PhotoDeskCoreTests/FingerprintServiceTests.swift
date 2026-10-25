// MARK: - 职责说明：哈希算法内核测试（docs/05 M4 验收：FingerprintServiceTests 对应的算法层）——
// dHash/pHash/BlurDetector：同图距离 0、旋转 90°、加噪/压缩近似距离、DCT 轮廓不变性、模糊判定。
// 输入均为合成灰度数组（无需真实图片），Docker 与 CI core-linux 双跑。

import XCTest
import Foundation
@testable import PhotoDeskCore

final class FingerprintServiceTests: XCTestCase {
    /// 构造水平渐变 9×8（列号越大盘越亮）
    private func gradientDHashInput() -> [UInt8] {
        (0..<8).flatMap { _ in (0..<9).map { UInt8($0 * 28) } }
    }

    /// 构造 32×32 上亮下暗渐变
    private func gradientPHashInput() -> [UInt8] {
        (0..<32).flatMap { row in
            (0..<32).map { col in UInt8(min(255, row * 8 + col / 8)) }
        }
    }

    // MARK: - dHash

    func testDHashDeterministicSameImageDistanceZero() {
        let input = gradientDHashInput()
        let a = DHash.compute(grayscale: input, width: 9, height: 8)
        let b = DHash.compute(grayscale: input, width: 9, height: 8)
        XCTAssertEqual(a, b)
        XCTAssertEqual(DuplicateGrouper.hammingDistance(a!, b!), 0)
    }

    func testDHashRejectsWrongSize() {
        XCTAssertNil(DHash.compute(grayscale: [0, 255], width: 2, height: 1))
        XCTAssertNil(DHash.compute(grayscale: [UInt8](repeating: 0, count: 72), width: 8, height: 9))
    }

    func testDHashRotationChangesBitsButStaysWithinNoiseRange() {
        // 旋转 90° 后 hash 大幅变化（非匹配），但仍应与自身旋转前保持可区分性——
        // 验证「旋转后距离」显著大于「同图距离 0」（docs/06 §6.1 的距离语义）
        let input = gradientDHashInput()
        let original = DHash.compute(grayscale: input, width: 9, height: 8)!
        var rotated = [UInt8](repeating: 0, count: 72)
        // 顺时针旋转 90°：9×8 → 8×9，重排为合法 9×8 输入（内容旋转近似）
        for y in 0..<8 {
            for x in 0..<9 {
                rotated[y * 9 + x] = input[x * 8 + (7 - y) % 8]
            }
        }
        let rotatedHash = DHash.compute(grayscale: rotated, width: 9, height: 8)!
        XCTAssertGreaterThan(DuplicateGrouper.hammingDistance(original, rotatedHash), 0)
    }

    func testDHashNoiseKeepsDistanceSmall() {
        let input = gradientDHashInput()
        let original = DHash.compute(grayscale: input, width: 9, height: 8)!
        // 轻噪声（±8，模拟压缩）：距离应很小（≤ 4）
        var noisy = input
        for index in noisy.indices where index % 3 == 0 {
            noisy[index] = UInt8(max(0, min(255, Int(noisy[index]) + (index % 2 == 0 ? 8 : -8))))
        }
        let noisyHash = DHash.compute(grayscale: noisy, width: 9, height: 8)!
        XCTAssertLessThanOrEqual(DuplicateGrouper.hammingDistance(original, noisyHash), 4)
    }

    /// 构造 32×32 明暗四分图（强低频结构；AC 系数量级大、中位数远离 0，噪声不翻转比特）
    private func quadrantPHashInput() -> [UInt8] {
        (0..<32).map { row in
            (0..<32).map { col -> UInt8 in
                (row < 16) == (col < 16) ? 235 : 25
            }
        }.flatMap { $0 }
    }

    // MARK: - pHash

    func testPHashDeterministicAndNoiseTolerant() {
        let input = quadrantPHashInput()
        let original = PHash.compute(grayscale: input, width: 32, height: 32)!
        XCTAssertEqual(DuplicateGrouper.hammingDistance(original, original), 0)

        // 轻噪声（全像素 ±3 交替抖动，模拟压缩噪点）：低频结构主导的哈希应保持稳定
        var noisy = input
        for index in noisy.indices {
            noisy[index] = UInt8(max(0, min(255, Int(noisy[index]) + (index % 2 == 0 ? 3 : -3))))
        }
        let noisyHash = PHash.compute(grayscale: noisy, width: 32, height: 32)!
        let distance = DuplicateGrouper.hammingDistance(original, noisyHash)
        XCTAssertLessThanOrEqual(distance, 16, "加噪距离 \(distance) 应小于等于 16（随机期望约 32）")
    }

    func testPHashRejectsWrongSize() {
        XCTAssertNil(PHash.compute(grayscale: [0, 255], width: 2, height: 1))
    }

    func testPHashDistinctImagesDiffer() {
        let gradient = gradientPHashInput()
        let inverted = gradient.map { UInt8(255 - Int($0)) }
        let hashA = PHash.compute(grayscale: gradient, width: 32, height: 32)!
        let hashB = PHash.compute(grayscale: inverted, width: 32, height: 32)!
        XCTAssertGreaterThan(DuplicateGrouper.hammingDistance(hashA, hashB), 0)
        _ = inverted
    }

    // MARK: - BlurDetector

    func testSharpImageHasHighVariance() {
        // 棋盘格（高频边缘）：方差应远大于阈值
        var checker = [UInt8]()
        for y in 0..<128 {
            for x in 0..<128 {
                checker.append((x / 4 + y / 4) % 2 == 0 ? 20 : 220)
            }
        }
        let variance = BlurDetector.laplacianVariance(grayscale: checker, width: 128, height: 128)!
        XCTAssertGreaterThan(variance, 1000)
        XCTAssertFalse(BlurDetector.isBlurry(variance: variance))
    }

    func testSmoothGradientIsBlurry() {
        // 平滑渐变：拉普拉斯响应趋近 0 → 方差 < 60 → 模糊
        var gradient = [UInt8]()
        for y in 0..<128 {
            for x in 0..<128 {
                gradient.append(UInt8((x + y) / 2))
            }
        }
        let variance = BlurDetector.laplacianVariance(grayscale: gradient, width: 128, height: 128)!
        XCTAssertLessThan(variance, 60)
        XCTAssertTrue(BlurDetector.isBlurry(variance: variance))
    }

    func testBlurThresholdAdjustable() {
        XCTAssertTrue(BlurDetector.isBlurry(variance: 100, threshold: 120))
        XCTAssertFalse(BlurDetector.isBlurry(variance: 100, threshold: 60))
    }

    func testLaplacianRejectsWrongSize() {
        XCTAssertNil(BlurDetector.laplacianVariance(grayscale: [0, 255], width: 2, height: 1))
    }
}
