// MARK: - 职责说明：UI 测试日期种子（docs/19 §5 / M13 审计）——
// DEBUG-only：simctl addmedia 不保证把 EXIF DateTimeOriginal 映射成 PHAsset.creationDate，
// 这里改为 PHAssetCreationRequest 显式写入 creationDate，保证 2020–2026 每月数据在筛选/月份/位置测试里稳定可复现。
// 只使用系统 Photos API、零网络、零第三方依赖；不带 -uiTestingSeedDatedPhotos 启动参数时完全惰性不写库。

#if DEBUG
import Foundation
import Photos
import UIKit

enum UITestDatedPhotoSeeder {
    private static let didSeedKey = "uitest.datedPhotos.seeded.v1"
    private static let batchSize = 40

    enum SeedError: Error { case photoLibraryRejected }

    /// viewState 进入 .ready 前 await：每个进程/沙盒只写一次，重复启动不重建。
    @MainActor
    static func seedIfNeeded() async {
        guard UITestHooks.enabled("-uiTestingSeedDatedPhotos") else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedKey) else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        let dates = makeDates()
        let images = makeImages(count: dates.count)
        await performChanges(dates: dates, images: images)
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
        // 极端比例图也保留可预测年份，仍走同一条 creationDate 写入路径。
        for index in 0..<3 {
            let components = DateComponents(year: 2026, month: 10, day: 18 + index, hour: 12)
            if let date = calendar.date(from: components) { result.append(date) }
        }
        return result
    }

    private static func makeImages(count: Int) -> [UIImage] {
        (0..<count).map { index in
            let size = extremeSize(at: index, total: count) ?? CGSize(width: 640, height: 480)
            let hue = CGFloat(index % 24) / 24
            let color = UIColor(hue: hue, saturation: 0.7, brightness: 0.85, alpha: 1)
            return UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
    }

    private static func extremeSize(at index: Int, total: Int) -> CGSize? {
        switch total - index {
        case 3:  return CGSize(width: 1200, height: 3600)
        case 2:  return CGSize(width: 3600, height: 1200)
        case 1:  return CGSize(width: 12000, height: 1000)
        default: return nil
        }
    }

    @MainActor
    private static func performChanges(dates: [Date], images: [UIImage]) async {
        let urls = images.enumerated().compactMap { index, image -> URL? in
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("uitest-dated-\(index).jpg")
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }
        defer {
            for url in urls {
                do { try FileManager.default.removeItem(at: url) } catch { }
            }
        }
        guard urls.count == dates.count else { return }
        for start in stride(from: 0, to: urls.count, by: batchSize) {
            let end = min(start + batchSize, urls.count)
            let batchURLs = Array(urls[start..<end])
            let batchDates = Array(dates[start..<end])
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    PHPhotoLibrary.shared().performChanges {
                        for (offset, url) in batchURLs.enumerated() {
                            guard let request = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url) else { continue }
                            request.creationDate = batchDates[offset]
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
}
#endif
