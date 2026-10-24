// MARK: - 职责说明：二级缓存——磁盘 LRU（docs/03 §5.2：Library/Caches/ThumbCache，上限 200MB，按修改时间淘汰）。
// 读命中时刷新 modificationDate（LRU 语义）；写入后检查总量，超限从最旧开始删。全部为阻塞文件操作，
// 调用方必须放到后台（ImagePipeline 内已用 Task.detached(priority: .utility) 包裹）。

import Foundation

final class DiskCache {
    static let limitBytes: Int64 = 200 * 1024 * 1024

    private let directory: URL
    private let fileManager = FileManager.default

    /// - Parameter limit: 容量上限；测试可注入小值
    init(directory: URL? = nil, limit: Int64 = DiskCache.limitBytes) {
        self.limit = limit
        if let directory {
            self.directory = directory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = caches.appendingPathComponent("ThumbCache", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private let limit: Int64

    func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(ThumbnailRequest.fnv1a64(key) + ".jpg")
    }

    /// 读命中：返回数据并刷新 LRU 时间戳
    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// 写入并按容量淘汰（返回是否写入成功）。淘汰扫描 O(n)，节流为每 20 次写入一次。
    @discardableResult
    func store(_ data: Data, forKey key: String) -> Bool {
        let url = fileURL(forKey: key)
        guard fileManager.createFile(atPath: url.path, contents: data) else { return false }
        writeCount += 1
        if writeCount % 20 == 0 {
            evictIfNeeded()
        }
        return true
    }

    private var writeCount = 0

    /// 清空（设置页「清理缓存」入口，M7 接线）
    func clear() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: - LRU 淘汰

    private func evictIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = files.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (url, values?.contentModificationDate ?? .distantPast, Int64(values?.fileSize ?? 0))
        }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limit else { return }

        entries.sort { $0.date < $1.date }   // 最旧优先
        var remaining = total
        for entry in entries {
            guard remaining > limit else { break }
            try? fileManager.removeItem(at: entry.url)
            remaining -= entry.size
        }
    }
}
