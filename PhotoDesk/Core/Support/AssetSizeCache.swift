// MARK: - 职责说明：资产字节磁盘缓存（docs/09 D07）——Application Support/AssetSizeCache.json，
// 按 assetID + modificationDate 缓存 bytes（原文件变了才重算）。JSON 存储（不给 Core Data 加实体——
// 程序化模型未启用自动迁移，docs/09 明令）。写节流由 StorageStatsService 控制（完成/超时时统一落盘）。

import Foundation

@MainActor
final class AssetSizeCache {
    struct Entry: Codable, Equatable {
        let modificationDate: Date
        let bytes: Int64
    }

    struct Payload: Codable {
        var schemaVersion: Int = 1
        var entries: [String: Entry] = [:]
    }

    private let fileURL: URL
    private(set) var payload: Payload

    init(directoryOverride: URL? = nil) {
        let fileManager = FileManager.default
        let directory: URL
        if let directoryOverride {
            directory = directoryOverride
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            directory = base
        }
        fileURL = directory.appendingPathComponent("AssetSizeCache.json", isDirectory: false)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        } else {
            payload = Payload()
        }
    }

    // MARK: - 查询

    /// 命中：id 存在且 modificationDate 一致
    func hit(assetID: String, modificationDate: Date?) -> Entry? {
        guard let entry = payload.entries[assetID] else { return nil }
        guard let modificationDate else { return entry }
        return abs(entry.modificationDate.timeIntervalSince(modificationDate)) < 0.5 ? entry : nil
    }

    func bytes(for ids: [(id: String, modificationDate: Date?)]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for item in ids {
            if let entry = hit(assetID: item.id, modificationDate: item.modificationDate) {
                result[item.id] = entry.bytes
            }
        }
        return result
    }

    // MARK: - 更新

    func update(entries: [(id: String, modificationDate: Date?, bytes: Int64)]) {
        for item in entries {
            payload.entries[item.id] = Entry(modificationDate: item.modificationDate ?? .distantPast,
                                             bytes: item.bytes)
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        payload = Payload()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
