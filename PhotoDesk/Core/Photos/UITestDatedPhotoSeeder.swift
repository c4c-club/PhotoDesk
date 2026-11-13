// MARK: - 职责说明：UI 测试日期种子（docs/19 §5 / M13 审计 / M16 T03 深库扩展）——
// DEBUG-only：simctl addmedia 不保证把 EXIF DateTimeOriginal 映射成 PHAsset.creationDate，
// 这里改为 PHAssetCreationRequest 显式写入 creationDate，保证 2020–2026 每月数据在筛选/月份/位置测试里稳定可复现。
// 性能约束（docs/21 §6 绿轮教训）：seeding 在 viewState 进入 .ready 前阻塞 loadIfNeeded，
// 超过 UI 测试网格超时会被杀进程且 didSeedKey 无法落盘，导致每次启动重试级联失败——
// 因此必须单张小图 + 单批事务，把总耗时压到秒级。
// 正确性约束（绿5 实测 167 请求只落 23 张）：多个 creation 请求不得共享同一个临时文件——
// Photos 对同一 URL 的并发拷贝会互相失败；逐文件落盘（96×96 小图 ≈1s 总量）后单批事务稳定。
// 深库种子（-uiTestingSeedDeepLibrary，M16 T03）：2002–2019 每月 2 张共 432 张，
// 让「锚点 globalIndex > 500」的位置恢复测试有真实深锚点（总量 519）；分批事务 40/批 + 幂等补种。
// CI 五轮实锤：150/批 大事务整体报 PHPhotosErrorDomain -1（部分成功后整批回滚），12 轮全败；
// 基础种子 40/批多年绿轮，深库沿用同规格（432/40=11 批 ≤ 14 轮上限）。
// 只使用系统 Photos API、零网络、零第三方依赖；不带 -uiTestingSeedDatedPhotos 时完全惰性不写库。

#if DEBUG
import Foundation
import Photos
import UIKit

enum UITestDatedPhotoSeeder {
    private static let didSeedKey = "uitest.datedPhotos.seeded.v1"
    private static let didDeepSeedKey = "uitest.datedPhotos.deep.seeded.v1"

    enum SeedError: Error { case photoLibraryRejected, seedImageUnavailable }

    /// viewState 进入 .ready 前 await：每个进程/沙盒只写一次，重复启动不重建。
    /// 失败时不落 didSeedKey（下次启动重试），只写 trace——不让一次性失败永久跳过种子。
    @MainActor
    static func seedIfNeeded() async {
        guard UITestHooks.enabled("-uiTestingSeedDatedPhotos") else { return }
        let defaults = UserDefaults.standard
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        if !defaults.bool(forKey: didSeedKey) {
            await seedBasePhotos(defaults: defaults)
        }
        await seedDeepLibraryIfNeeded(defaults: defaults)
    }

    /// 基础种子：2020–2026 每月 2 张 + 3 张极端比例（docs/19 §5）。
    @MainActor
    private static func seedBasePhotos(defaults: UserDefaults) async {
        let wanted = Set(makeDates())
        // 绿9 实锤：performChanges 可能部分成功（库内已插入部分种子）后整体抛错——
        // didSeedKey 未落盘会让下次启动整批重插，库从 341 涨到 468/500（重复月份 4 张）。
        // 改为「缺什么补什么」的幂等补种：每次先枚举现有 creationDate，只创建缺失日期；
        // 补齐才落盘标记。部分成功的事务不会因为重试而产生重复。
        for attempt in 1...2 {
            let missing = missingSeedDates(wanted: wanted)
            if missing.isEmpty {
                defaults.set(true, forKey: didSeedKey)
                return
            }
            do {
                try await performChanges(dates: missing)
                if missingSeedDates(wanted: wanted).isEmpty {
                    defaults.set(true, forKey: didSeedKey)
                }
                return
            } catch {
                ViewerTrace.log("seed failed count=\(missing.count) attempt=\(attempt) error=\(error)")
                if attempt == 1 {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { /* 睡眠失败直接重试 */ }
                }
            }
        }
    }

    /// 深库种子：分批幂等补种（每批 40、至多 14 轮），完成后落 didDeepSeedKey（只执行一次）。
    @MainActor
    private static func seedDeepLibraryIfNeeded(defaults: UserDefaults) async {
        guard UITestHooks.enabled("-uiTestingSeedDeepLibrary"),
              !defaults.bool(forKey: didDeepSeedKey) else { return }
        let wanted = Set(makeDeepDates())
        var rounds = 0
        while rounds < 14 {
            let missing = missingSeedDates(wanted: wanted)
            if missing.isEmpty {
                defaults.set(true, forKey: didDeepSeedKey)
                ViewerTrace.log("deep-seed done wanted=\(wanted.count) rounds=\(rounds)")
                return
            }
            let chunk = Array(missing.prefix(40))
            do {
                try await performChanges(dates: chunk)
            } catch {
                ViewerTrace.log("deep-seed failed count=\(chunk.count) round=\(rounds) error=\(error)")
            }
            rounds += 1
        }
        ViewerTrace.log("deep-seed incomplete after 14 rounds")
    }

    /// 幂等去重：枚举现有图片资产的 creationDate（元数据级查询，几百张毫秒级），
    /// 返回 wanted 里尚不存在的日期。creationDate 与写入值逐字节相等（同一 Date 往返）。
    @MainActor
    private static func missingSeedDates(wanted: Set<Date>) -> [Date] {
        let fetch = PHAsset.fetchAssets(with: .image, options: nil)
        var existing = Set<Date>()
        fetch.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate { existing.insert(date) }
        }
        return wanted.subtracting(existing).sorted()
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

    /// 深库日期：2002–2019 每月 2 张（432 张；与基础种子不重叠）。
    private static func makeDeepDates() -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var result: [Date] = []
        for year in 2002...2019 {
            for month in 1...12 {
                for day in [3, 17] {
                    let components = DateComponents(year: year, month: month, day: day, hour: 12)
                    if let date = calendar.date(from: components) { result.append(date) }
                }
            }
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