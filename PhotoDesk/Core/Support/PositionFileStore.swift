// MARK: - 职责说明：位置记忆 v5 原子文件存储（docs/25 §5.3 / M15 P0-2）——
// 路径 Application Support/LibraryPosition/anchors-v5.json，结构
// { "schemaVersion": 5, "entries": { "<queryKey>": LibraryPosition } }。
// 写：串行 utility 队列 + Data.write(options: .atomic)（I3：杀进程不留半截 JSON）；
// 读：init 一次性加载内存字典，损坏 JSON → 备份 .corrupt-<timestamp> 后从空字典开始，不崩溃；
// 容量 64 个 queryKey，按 savedAt 淘汰最旧；flush() 供 willResignActive / scenePhase 调用。
// nonisolated：内存字典用 NSLock 保护（store 可能从非主线程构造），落盘只做编码/写文件。

import Foundation

final class PositionFileStore {
    static let schemaVersion = 5
    static let capacity = 64

    private struct FileModel: Codable {
        var schemaVersion: Int = PositionFileStore.schemaVersion
        var entries: [String: LibraryPosition] = [:]
    }

    private let directory: URL
    private let fileURL: URL
    private let writeQueue: DispatchQueue
    private let stateLock = NSLock()
    /// 内存字典（stateLock 保护；快照入队，写队列只读快照）
    private var entries: [String: LibraryPosition] = [:]

    /// 测试可注入目录；生产默认 Application Support/LibraryPosition
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryPosition", isDirectory: true)
        self.directory = base
        self.fileURL = base.appendingPathComponent("anchors-v5.json")
        self.writeQueue = DispatchQueue(label: "position-file-write", qos: .utility)
        loadFromDisk()
    }

    var entryCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return entries.count
    }

    // MARK: - 读

    func load(queryKey: String) -> LibraryPosition? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return entries[queryKey]
    }

    // MARK: - 写

    /// 内存即时生效，落盘走串行队列（原子写）。queryKey 盖进结构体：I5 往返不变量要求
    /// load 出的 position.queryKey 与存储键一致（防御调用方未填充）。
    func save(_ position: LibraryPosition, queryKey: String) {
        guard !queryKey.isEmpty else { return }
        var stamped = position
        stamped.queryKey = queryKey
        let snapshot: [String: LibraryPosition] = withLockedState { entries in
            entries[queryKey] = stamped
            evictIfNeeded(&entries)
            return entries
        }
        enqueuePersist(snapshot: snapshot)
    }

    func remove(queryKey: String) {
        let snapshot: [String: LibraryPosition]? = withLockedState { entries in
            guard entries.removeValue(forKey: queryKey) != nil else { return nil }
            return entries
        }
        if let snapshot { enqueuePersist(snapshot: snapshot) }
    }

    func removeAll() {
        let snapshot: [String: LibraryPosition]? = withLockedState { entries in
            guard !entries.isEmpty else { return nil }
            entries.removeAll()
            return entries
        }
        if let snapshot { enqueuePersist(snapshot: snapshot) }
    }

    /// 切后台/杀进程前的最后一笔：等队列里已入队的写全部落盘再返回。
    func flush() {
        writeQueue.sync { }
    }

    // MARK: - 内部

    private func withLockedState<T>(_ body: (inout [String: LibraryPosition]) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(&entries)
    }

    /// 容量超限时按 savedAt 淘汰最旧（调用方已持锁）。
    private func evictIfNeeded(_ entries: inout [String: LibraryPosition]) {
        guard entries.count > Self.capacity else { return }
        let overflow = entries.count - Self.capacity
        let oldest = entries.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(overflow).map(\.key)
        for key in oldest {
            entries.removeValue(forKey: key)
        }
    }

    private func enqueuePersist(snapshot: [String: LibraryPosition]) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.persist(snapshot: snapshot)
        }
    }

    private func persist(snapshot: [String: LibraryPosition]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let model = FileModel(entries: snapshot)
            let data = try JSONEncoder().encode(model)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            ViewerTrace.log("position.file write-failed \(error.localizedDescription.prefix(80))")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let model = try JSONDecoder().decode(FileModel.self, from: data)
            stateLock.lock()
            entries = model.entries
            stateLock.unlock()
        } catch {
            // 损坏 JSON：备份留证，从空字典开始（不崩溃、不半读）
            let backupName = "anchors-v5.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = directory.appendingPathComponent(backupName)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: backupURL, options: .atomic)
            ViewerTrace.log("position.file corrupt backup=\(backupName) error=\(error.localizedDescription.prefix(80))")
            entries = [:]
        }
    }
}
