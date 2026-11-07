// MARK: - 职责说明：UI 测试日期种子（docs/19 §5 / M13 审计）——
// DEBUG-only：simctl addmedia 不保证把 EXIF DateTimeOriginal 映射成 PHAsset.creationDate，
// 这里改为 PHAssetCreationRequest 显式写入 creationDate，保证 2020–2026 每月数据在筛选/月份/位置测试里稳定可复现。
// 性能约束（docs/21 §6 绿轮教训）：seeding 在 viewState 进入 .ready 前阻塞 loadIfNeeded，
// 超过 UI 测试网格超时会被杀进程且 didSeedKey 无法落盘，导致每次启动重试级联失败——
// 因此必须单张小图 + 单批事务，把总耗时压到秒级。只使用系统 Photos API、零网络、零第三方依赖；
// 不带 -uiTestingSeedDatedPhotos 启动参数时完全惰性不写库。

#if DEBUG
import Foundation
import Photos
import UIKit

enum UITestDatedPhotoSeeder {
    private static let didSeedKey = "uitest.datedPhotos.seeded.v1"

    enum SeedError: Error { case photoLibraryRejected }

    /// viewState 进入 .ready 前 await：每个进程/沙盒只写一次，重复启动不重建。
    @MainActor
    static func seedIfNeeded() async {
        guard UITestHooks.enabled("-uiTestingSeedDatedPhotos") else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedKey) else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        let dates = makeDates()
        await performChanges(dates: dates)
        defaults.set(true, forKey: didSeedKey)
    }

    private static func makeDates() -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var result: [Date] = []
        for year in 2020...2026 {
            for month in 1...12 {
                if year == 2026, month > 10 { break }
                for day in [3, 17] {
                    let components = DateComponents(year: year, month: month, day: day, hour: 12)
                    if let date = calendar.date(from: components) { result.append(date) }
                }
            }
        }
        // 极端比例测试图保留可预测年份，仍走同一条 creationDate 写入路径。
        for index in 0..<3 {
            let components = DateComponents(year: 2026, month: 10, day: 18 + index, hour: 12)
            if let date = calendar.date(from: components) { result.append(date) }
        }
        return result
    }

    /// 测试只关心 creationDate 元数据，不关心像素内容：渲染一张小图、编码一次、
    /// 全部 creation 请求复用同一个文件，把渲染/编码成本从 O(n) 降到 O(1)。
    private static func makeSeedImageURL() -> URL? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor(hue: 0.55, saturation: 0.7, brightness: 0.85, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-dated-seed.jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    @MainActor
    private static func performChanges(dates: [Date]) async {
        guard let url = makeSeedImageURL() else { return }
        defer {
            do { try FileManager.default.removeItem(at: url) } catch { }
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    for date in dates {
                        guard let request = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url) else { continue }
                        request.creationDate = date
                    }
                } completionHandler: { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: SeedError.photoLibraryRejected) }
                }
            }
        } catch {
            return
        }
    }
}
#endif
