// MARK: - 职责说明：位置记忆 v6 原子文件存储（docs/28 §5.3 / M16 T03）——
// 路径 Application Support/LibraryPosition/anchors-v6.json，结构
// { "schemaVersion": 6, "entries": { "<queryKey>": LibraryPositionV6 } }。
// 写：串行 utility 队列 + Data.write(options: .atomic)（杀进程不留半截 JSON；写失败旧文件原样保留）；
// 读：init 一次性加载内存字典，损坏 JSON → 备份 .corrupt-<timestamp> 后从空字典开始，不崩溃；
// 首次初始化（v6 文件不存在且 v5 文件存在）→ v5 只读迁移一次（迁移后 v5 文件原样保留，绝不改写）；
// v6 文件已存在（含损坏备份场景）→ 跳过迁移（迁移只执行一次的标记 = v6 文件存在）；
// 容量 64 个 queryKey，按 savedAt 淘汰最旧；flush() 供 willResignActive / scenePhase 调用。

import Foundation

final class PositionFileStore {
    static let schemaVersion = 6
    static let capacity = 64

    private struct FileModel: Codable {
        var schemaVersion: Int = PositionFileStore.schemaVersion
        var entries: [String: LibraryPositionV6] = [:]
    }

    /// v5 迁移源结构（只读；解码失败的单条跳过，不影响其它条目）
    private struct LegacyV5FileModel: Codable {
        var schemaVersion: Int = 5
        var entries: [String: LibraryPosition] = [:]
    }

    private let directory: URL
    private let fileURL: URL
    private let legacyFileURL: URL
    private let writeQueue: DispatchQueue
    private let stateLock = NSLock()
    /// 内存字典（stateLock 保护；快照入队，写队列只读快照）
    private var entries: [String: LibraryPositionV6] = [:]
    /// 迁移时注入保存时的列数（生产读 grid.columns；测试可注入固定值）
    private let migratedGridColumns: () -> Int

    /// 测试可注入目录；生产默认 Application Support/LibraryPosition
    init(directory: URL? = nil, migratedGridColumns: (() -> Int)? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryPosition", isDirectory: true)
        self.directory = base
        self.fileURL = base.appendingPathComponent("anchors-v6.json")
        self.legacyFileURL = base.appendingPathComponent("anchors-v5.json")
        self.migratedGridColumns = migratedGridColumns ?? {
            LibraryPositionStore.currentGridColumns(defaults: .standard)
        }
        self.writeQueue = DispatchQueue(label: "position-file-write", qos: .utility)
        loadFromDisk()
        migrateV5IfNeeded()
    }

    var entryCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return entries.count
    }

    // MARK: - 读

    func load(queryKey: String) -> LibraryPositionV6? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return entries[queryKey]
    }

    // MARK: - 写

    /// 内存即时生效，落盘走串行队列（原子写）。queryKey 盖进结构体：往返不变量要求
    /// load 出的 position.queryKey 与存储键一致（防御调用方未填充）。
    func save(_ position: LibraryPositionV6, queryKey: String) {
        guard !queryKey.isEmpty else { return }
        var stamped = position
        stamped.queryKey = queryKey
        let snapshot: [String: LibraryPositionV6] = withLockedState { entries in
            entries[queryKey] = stamped
            evictIfNeeded(&entries)
            return entries
        }
        enqueuePersist(snapshot: snapshot)
    }

    func remove(queryKey: String) {
        let snapshot: [String: LibraryPositionV6]? = withLockedState { entries in
            guard entries.removeValue(forKey: queryKey) != nil else { return nil }
            return entries
        }
        if let snapshot { enqueuePersist(snapshot: snapshot) }
    }

    func removeAll() {
        let snapshot: [String: LibraryPositionV6]? = withLockedState { entries in
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

    private func withLockedState<T>(_ body: (inout [String: LibraryPositionV6]) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(&entries)
    }

    /// 容量超限时按 savedAt 淘汰最旧（调用方已持锁）。
    private func evictIfNeeded(_ entries: inout [String: LibraryPositionV6]) {
        guard entries.count > Self.capacity else { return }
        let overflow = entries.count - Self.capacity
        let oldest = entries.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(overflow).map(\.key)
        for key in oldest {
            entries.removeValue(forKey: key)
        }
    }

    private func enqueuePersist(snapshot: [String: LibraryPositionV6]) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.persist(snapshot: snapshot)
        }
    }

    private func persist(snapshot: [String: LibraryPositionV6]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let model = FileModel(entries: snapshot)
            let data = try JSONEncoder().encode(model)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 原子写失败 → 旧文件原样保留（docs/28 §5.6：写失败保留旧文件），只记诊断
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
            // 损坏 JSON：备份留证，从空字典开始（不崩溃、不半读）。
            // 不回迁 v5：v6 文件已存在 = 迁移已完成，损坏走 fallback 链（§5.3）。
            let backupName = "anchors-v6.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = directory.appendingPathComponent(backupName)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: backupURL, options: .atomic)
            ViewerTrace.log("position.file corrupt backup=\(backupName) error=\(error.localizedDescription.prefix(80))")
            stateLock.lock()
            entries = [:]
            stateLock.unlock()
        }
    }

    // MARK: - v5 → v6 只读迁移

    /// 仅当 v6 文件不存在且 v5 文件存在时执行一次；v5 文件只读（一个字节都不改写）；
    /// 迁移结果立即同步落盘（完成标记 = v6 文件存在）。
    private func migrateV5IfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path) == false,
              FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }
        guard let data = try? Data(contentsOf: legacyFileURL),
              let legacy = try? JSONDecoder().decode(LegacyV5FileModel.self, from: data) else {
            ViewerTrace.log("position.migrate v5→v6 skip legacy-unreadable")
            return
        }
        var migrated: [String: LibraryPositionV6] = [:]
        for (key, old) in legacy.entries {
            var position = old.toV6(gridColumns: migratedGridColumns())
            position.queryKey = key
            migrated[key] = position
        }
        stateLock.lock()
        entries = migrated
        stateLock.unlock()
        persist(snapshot: migrated)
        ViewerTrace.log("position.migrate v5→v6 count=\(migrated.count)")
    }
}