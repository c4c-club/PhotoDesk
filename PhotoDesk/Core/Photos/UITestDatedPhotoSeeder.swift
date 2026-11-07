// MARK: - 职责说明：UI 测试日期种子（docs/19 §5 / M13 审计）——
// DEBUG-only：simctl addmedia 不保证把 EXIF DateTimeOriginal 映射成 PHAsset.creationDate，
// 这里改为 PHAssetCreationRequest 显式写入 creationDate，保证 2020–2026 每月数据在筛选/月份/位置测试里稳定可复现。
// 性能约束（docs/21 §6 绿轮教训）：seeding 在 viewState 进入 .ready 前阻塞 loadIfNeeded，
// 超过 UI 测试网格超时会被杀进程且 didSeedKey 无法落盘，导致每次启动重试级联失败——
// 因此必须单张小图 + 单批事务，把总耗时压到秒级。
// 正确性约束（绿5 实测 167 请求只落 23 张）：多个 creation 请求不得共享同一个临时文件——
// Photos 对同一 URL 的并发拷贝会互相失败；逐文件落盘（96×96 小图 ≈1s 总量）后单批事务稳定。
// 只使用系统 Photos API、零网络、零第三方依赖；不带 -uiTestingSeedDatedPhotos 时完全惰性不写库。

#if DEBUG
import Foundation
import Photos
import UIKit

enum UITestDatedPhotoSeeder {
    private static let didSeedKey = "uitest.datedPhotos.seeded.v1"

    enum SeedError: Error { case photoLibraryRejected, seedImageUnavailable }

    /// viewState 进入 .ready 前 await：每个进程/沙盒只写一次，重复启动不重建。
    /// 失败时不落 didSeedKey（下次启动重试），只写 trace——不让一次性失败永久跳过种子。
    @MainActor
    static func seedIfNeeded() async {
        guard UITestHooks.enabled("-uiTestingSeedDatedPhotos") else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedKey) else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        let dates = makeDates()
        // 绿8 实锤：首轮 performChanges 曾抛 PHPhotosError -1（瞬时失败，didSeedKey 未落盘，
        // 后续启动重试才成功）。就地理由一次重试，保证首个测试的网格即有种子日期。
        for attempt in 1...2 {
            do {
                try await performChanges(dates: dates)
                defaults.set(true, forKey: didSeedKey)
                return
            } catch {
                ViewerTrace.log("seed failed count=\(dates.count) attempt=\(attempt) error=\(error)")
                if attempt == 1 {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { /* 睡眠失败直接重试 */ }
                }
            }
        }
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

    /// 测试只关心 creationDate 元数据，不关心像素内容：同一张 96×96 小图编码一次，
    /// 逐请求写入独立临时文件（共享 URL 会被 Photos 并发拷贝打断，绿5 实测）。
    private static func makeSeedFileURLs(count: Int) -> [URL]? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor(hue: 0.55, saturation: 0.7, brightness: 0.85, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-dated-seed", isDirectory: true)
        // 绿7 实锤：子目录不存在时 Data.write(.atomic) 不建父目录 → 首个文件即失败 →
        // seedImageUnavailable 每次启动重试失败，全库无 2020–2026 种子（月份/筛选族 8 条红的总根源）。
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var urls: [URL] = []
        for index in 0..<count {
            let url = directory.appendingPathComponent("seed-\(index).jpg")
            do {
                try data.write(to: url, options: .atomic)
                urls.append(url)
            } catch {
                for written in urls {
                    do { try FileManager.default.removeItem(at: written) } catch { }
                }
                return nil
            }
        }
        return urls
    }

    @MainActor
    private static func performChanges(dates: [Date]) async throws {
        guard let urls = makeSeedFileURLs(count: dates.count), urls.count == dates.count else {
            throw SeedError.seedImageUnavailable
        }
        defer {
            for url in urls {
                do { try FileManager.default.removeItem(at: url) } catch { }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                for (offset, url) in urls.enumerated() {
                    guard let request = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url) else { continue }
                    request.creationDate = dates[offset]
                }
            } completionHandler: { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: SeedError.photoLibraryRejected) }
            }
        }
    }
}
#endif
