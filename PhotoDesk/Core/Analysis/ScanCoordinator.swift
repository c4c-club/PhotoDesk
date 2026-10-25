// MARK: - 职责说明：扫描协调器（docs/05 M4 任务 4.2 / docs/03 §5.4）——
// 指纹扫描：分批 500 → TaskGroup(maxConcurrent 4) + qos .utility → 每 200 条落库 →
// ScanSession.cursor 持久化（中断恢复）→ 每批 Task.isCancelled 检查 → 进度发布。
// 并发结构：扫描管线 nonisolated（重活全部跑在 utility 后台，UI 不卡）；@MainActor 仅承载 @Published 状态。
// 取消语义：Task.isCancelled 在批间检查；已落库指纹幂等，重扫自动续接。
// 专项：重复分组（core 并查集）/ 截图 / 大文件 / 模糊（方差阈值可调，docs/01 §F）。

import CoreData
import Foundation
import PhotoDeskCore
import Photos
import UIKit

@MainActor
final class ScanCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(scanned: Int, total: Int)
        case completed(ScanSummary)
        case cancelled
        case failed(String)
    }

    /// 扫描结果摘要（结果卡片数据，docs/04 §3.3）
    struct ScanSummary: Equatable {
        var duplicateGroups: [DuplicateGroup] = []
        var screenshotIDs: [String] = []
        var largeFileIDs: [String] = []
        var blurryIDs: [String] = []
        /// 各类可省空间（字节，fileSize 未知的不计）
        var screenshotBytes: Int64 = 0
        var largeFileBytes: Int64 = 0
        var blurryBytes: Int64 = 0
    }

    // MARK: - 专项阈值（docs/01 §F：视频 > 100MB / 照片 > 10MB；模糊方差 < 60 设置可调）
    static let largeVideoBytes: Int64 = 100 * 1024 * 1024
    static let largePhotoBytes: Int64 = 10 * 1024 * 1024

    @Published private(set) var phase: Phase = .idle

    private let repository: AssetRepositoryProtocol
    private let fingerprintService: FingerprintService
    private let persistence: PersistenceController
    private let settings: SettingsStore
    private var scanTask: Task<Void, Never>?

    init(repository: AssetRepositoryProtocol,
         fingerprintService: FingerprintService,
         persistence: PersistenceController = .shared,
         settings: SettingsStore) {
        self.repository = repository
        self.fingerprintService = fingerprintService
        self.persistence = persistence
        self.settings = settings
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func cancel() {
        scanTask?.cancel()
    }

    /// 全量扫描。阈值在主线程快照后传入后台；管线在 utility 后台执行，进度经闭包回主线程发布。
    func startScan() {
        guard !isRunning else { return }
        let inputs = ScanInputs(repository: repository,
                                fingerprintService: fingerprintService,
                                persistence: persistence,
                                distanceThreshold: settings.dedupHammingDistance,
                                blurThreshold: settings.blurVarianceThreshold)
        phase = .running(scanned: 0, total: 0)
        // 强持有至扫描结束（取消经 scanTask?.cancel() 生效，引用不妨碍取消）
        let coordinator = self
        scanTask = Task.detached(priority: .utility) {
            let summary = await ScanPipeline.run(inputs: inputs) { scanned, total in
                Task { @MainActor in
                    coordinator.phase = .running(scanned: scanned, total: total)
                }
            }
            await MainActor.run {
                if Task.isCancelled {
                    coordinator.phase = .cancelled
                } else if let summary {
                    coordinator.phase = .completed(summary)
                } else {
                    coordinator.phase = .cancelled
                }
            }
        }
    }
}

/// 扫描管线输入（主线程快照）
struct ScanInputs {
    let repository: AssetRepositoryProtocol
    let fingerprintService: FingerprintService
    let persistence: PersistenceController
    let distanceThreshold: Int
    let blurThreshold: Double
}

/// 扫描管线（nonisolated：重活跑在 utility 后台；@MainActor 依赖的方法调用处自动 hop）
private enum ScanPipeline {
    /// - Returns: nil = 被取消
    static func run(inputs: ScanInputs,
                    onProgress: @escaping @Sendable (Int, Int) -> Void) async -> ScanCoordinator.ScanSummary? {
        var summary = ScanCoordinator.ScanSummary()
        let persistence = inputs.persistence

        // 1. 会话（断点续扫：cursor 记录已处理条数；指纹缓存幂等，重扫自动续接）
        let total = await inputs.repository.prepare(scope: .all)
        guard total > 0 else { return summary }
        let sessionID = createSession(persistence: persistence, total: total)
        defer { finishSession(persistence: persistence, sessionID: sessionID) }

        // 2. 拉全量条目（PhotoItem 轻量结构）
        var items: [PhotoItem] = []
        var cursor = resumeCursor(persistence: persistence)
        while cursor < total {
            if Task.isCancelled { return nil }
            let batch = await inputs.repository.fetch(scope: .all, offset: cursor, limit: AssetRepository.batchSize)
            guard !batch.isEmpty else { break }
            items.append(contentsOf: batch)
            cursor += batch.count
        }

        // 3. 指纹扫描（跳过已计算且 algoVersion 匹配的 asset；TaskGroup 并发 4）
        let cached = inputs.fingerprintService.cachedFingerprints()
        var fresh: [String: (dhash: UInt64, phash: UInt64?)] = [:]
        var blurVariances: [String: Double] = [:]
        let pending = items.filter { cached[$0.id] == nil }
        var scanned = 0

        for batch in pending.chunked(by: 200) {
            if Task.isCancelled { return nil }
            await withTaskGroup(of: (String, FingerprintService.Fingerprints?).self) { group in
                for item in batch {
                    group.addTask(priority: .utility) {
                        let fingerprints = await inputs.fingerprintService.compute(forAssetID: item.id)
                        return (item.id, fingerprints)
                    }
                }
                for await (assetID, fingerprints) in group {
                    guard let fingerprints else { continue }
                    fresh[assetID] = (fingerprints.dhash, fingerprints.phash)
                    if let variance = fingerprints.blurVariance {
                        blurVariances[assetID] = variance
                    }
                    if let item = items.first(where: { $0.id == assetID }) {
                        inputs.fingerprintService.save(assetID: assetID,
                                                       aspect: aspect(item),
                                                       pixelArea: item.pixelWidth * item.pixelHeight,
                                                       hasEdits: hasEdits(item),
                                                       createdAt: item.creationDate,
                                                       fingerprints: fingerprints)
                    }
                }
            }
            scanned += batch.count
            updateSession(persistence: persistence, sessionID: sessionID, scanned: scanned, cursor: cursor)
            onProgress(scanned, pending.count)
        }

        // 4. 合并缓存 → 分组（阈值设置可调）
        var merged = cached
        for (id, value) in fresh {
            merged[id] = FingerprintService.Cached(dhash: value.dhash, phash: value.phash)
        }
        let candidates = inputs.fingerprintService.candidates(items: items, cache: merged)
        summary.duplicateGroups = DuplicateGrouper.groups(from: candidates,
                                                          distanceThreshold: inputs.distanceThreshold)

        // 5. 专项：截图 / 大文件 / 模糊
        for item in items {
            let size = fileSize(of: item.id)
            if item.mediaSubtypes.contains(.photoScreenshot) {
                summary.screenshotIDs.append(item.id)
                summary.screenshotBytes += size
            }
            let isLarge = (item.mediaType == .video && size > ScanCoordinator.largeVideoBytes)
                || (item.mediaType == .image && size > ScanCoordinator.largePhotoBytes)
            if isLarge {
                summary.largeFileIDs.append(item.id)
                summary.largeFileBytes += size
            }
            if let variance = blurVariances[item.id],
               BlurDetector.isBlurry(variance: variance, threshold: inputs.blurThreshold) {
                summary.blurryIDs.append(item.id)
                summary.blurryBytes += size
            }
        }
        return summary
    }
}

extension Array {
    /// 按固定大小分批（扫描批处理用）
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

    // MARK: - helpers（nonisolated）

    private static func aspect(_ item: PhotoItem) -> Double {
        item.pixelHeight > 0 ? Double(item.pixelWidth) / Double(item.pixelHeight) : 1
    }

    private static func hasEdits(_ item: PhotoItem) -> Bool {
        guard let created = item.creationDate, let modified = item.modificationDate else { return false }
        return modified.timeIntervalSince(created) > 1
    }

    private static func fileSize(of assetID: String) -> Int64 {
        PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject?.fileSizeBytes ?? 0
    }

    // MARK: - ScanSession 持久化（cursor 断点；viewContext.performAndWait 线程安全）

    private static func resumeCursor(persistence: PersistenceController) -> Int {
        var cursor = 0
        persistence.container.viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ScanSession")
            request.predicate = NSPredicate(format: "status == %d", 1)
            request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
            request.fetchLimit = 1
            if let row = (try? persistence.container.viewContext.fetch(request))?.first {
                cursor = Int(row.value(forKey: "cursor") as? Int32 ?? 0)
            }
        }
        return cursor
    }

    private static func createSession(persistence: PersistenceController, total: Int) -> UUID {
        let sessionID = UUID()
        persistence.performSync { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: "ScanSession", into: context)
            object.setValue(sessionID, forKey: "id")
            object.setValue(Int16(0), forKey: "kind")
            object.setValue(Date(), forKey: "startedAt")
            object.setValue(Int32(0), forKey: "scanned")
            object.setValue(Int32(total), forKey: "total")
            object.setValue(Int32(0), forKey: "cursor")
            object.setValue(Int16(1), forKey: "status")   // 1 = running
            try? context.save()
        }
        return sessionID
    }

}
