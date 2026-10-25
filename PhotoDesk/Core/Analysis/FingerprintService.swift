// MARK: - 职责说明：指纹计算与缓存（docs/05 M4 任务 4.1）——
// PHImageManager 拉一次 128×128 灰度渲染 → 派生 9×8（dHash）/ 32×32（pHash）/ 128×128（模糊方差），
// 算法内核全部在 PhotoDeskCore（红线 2），本类只做取图、像素转换与 Core Data 存取。
// 存储拆分：UInt64 哈希按高低 32bit 拆两个 Int64（docs/03 §4.2 字段）；algoVersion 变化时全量重算。
// nonisolated：compute 在扫描 TaskGroup 的 utility 任务中并行执行；Core Data 经 performSync 线程安全落库。

import CoreData
import Foundation
import Photos
import PhotoDeskCore

final class FingerprintService {
    static let algoVersion: Int16 = 1

    struct Fingerprints {
        let dhash: UInt64
        let phash: UInt64?
        /// 128×128 拉普拉斯方差（模糊判定用）
        let blurVariance: Double?
    }

    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    // MARK: - 计算（单张）

    /// - Returns: nil = 原件不可用（iCloud 未下载等）
    func compute(forAssetID assetID: String) async -> Fingerprints? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fast
        options.isNetworkAccessAllowed = false     // 扫描不触网；iCloud-only 本轮跳过
        options.resizeMode = .fast

        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 128, height: 128),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded else { return }
                continuation.resume(returning: image)
            }
        }
        guard let image,
              let gray128 = Self.grayPixels(from: image, width: 128, height: 128),
              let gray32 = Self.grayPixels(from: image, width: 32, height: 32),
              let gray9 = Self.grayPixels(from: image, width: 9, height: 8) else { return nil }

        guard let dhash = DHash.compute(grayscale: gray9, width: 9, height: 8),
              let phash = PHash.compute(grayscale: gray32, width: 32, height: 32) else { return nil }
        let blurVariance = BlurDetector.laplacianVariance(grayscale: gray128, width: 128, height: 128)
        return Fingerprints(dhash: dhash, phash: phash, blurVariance: blurVariance)
    }

    // MARK: - 缓存存取（Core Data）

    struct Cached {
        let dhash: UInt64
        let phash: UInt64?
    }

    /// 全量已缓存指纹（algoVersion 匹配才有效）
    func cachedFingerprints() -> [String: Cached] {
        var result: [String: Cached] = [:]
        persistence.container.viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Fingerprint")
            request.predicate = NSPredicate(format: "algoVersion == %d", Self.algoVersion)
            let objects = (try? persistence.container.viewContext.fetch(request)) ?? []
            for object in objects {
                guard let localID = object.value(forKey: "localIdentifier") as? String else { continue }
                let lo = UInt64(bitPattern: object.value(forKey: "dhashLo") as? Int64 ?? 0)
                let hi = UInt64(bitPattern: object.value(forKey: "dhashHi") as? Int64 ?? 0)
                let dhash = (hi << 32) | lo
                let pLo = object.value(forKey: "phashLo") as? Int64
                let pHi = object.value(forKey: "phashHi") as? Int64
                var phash: UInt64?
                if let pLo, let pHi, pLo != 0 || pHi != 0 {
                    phash = (UInt64(bitPattern: pHi) << 32) | UInt64(bitPattern: pLo)
                }
                result[localID] = Cached(dhash: dhash, phash: phash)
            }
        }
        return result
    }

    /// upsert 单条指纹
    func save(assetID: String, aspect: Double, pixelArea: Int, hasEdits: Bool,
              createdAt: Date?, fingerprints: Fingerprints) {
        persistence.performSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "Fingerprint")
            request.predicate = NSPredicate(format: "localIdentifier == %@", assetID)
            let object = (try? context.fetch(request).first)
                ?? NSEntityDescription.insertNewObject(forEntityName: "Fingerprint", into: context)
            object.setValue(assetID, forKey: "localIdentifier")
            object.setValue(Int64(truncatingIfNeeded: fingerprints.dhash), forKey: "dhashLo")
            object.setValue(Int64(truncatingIfNeeded: fingerprints.dhash >> 32), forKey: "dhashHi")
            if let phash = fingerprints.phash {
                object.setValue(Int64(truncatingIfNeeded: phash), forKey: "phashLo")
                object.setValue(Int64(truncatingIfNeeded: phash >> 32), forKey: "phashHi")
            }
            object.setValue(aspect, forKey: "aspect")
            object.setValue(Int64(pixelArea), forKey: "pixelArea")
            object.setValue(hasEdits, forKey: "hasEdits")
            object.setValue(createdAt ?? Date(), forKey: "createdAt")
            object.setValue(Self.algoVersion, forKey: "algoVersion")
            try? context.save()
        }
    }

    /// 候选构造（分组的输入：跳过缓存缺失的 id）
    func candidates(items: [PhotoItem], cache: [String: Cached]) -> [DuplicateCandidate] {
        items.compactMap { item in
            guard let cached = cache[item.id] else { return nil }
            let hasEdits: Bool = {
                guard let created = item.creationDate, let modified = item.modificationDate else { return false }
                return modified.timeIntervalSince(created) > 1
            }()
            return DuplicateCandidate(id: item.id,
                                      dhash: cached.dhash,
                                      phash: cached.phash,
                                      aspect: item.pixelWidth > 0
                                          ? Double(item.pixelWidth) / Double(item.pixelHeight)
                                          : 1,
                                      createdAt: item.creationDate,
                                      pixelArea: item.pixelWidth * item.pixelHeight,
                                      hasEdits: hasEdits,
                                      modificationDate: item.modificationDate)
        }
    }

    // MARK: - 灰度渲染（CGContext 硬件路径；App 侧取图准备，非算法内核）

    nonisolated static func grayPixels(from image: UIImage, width: Int, height: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
