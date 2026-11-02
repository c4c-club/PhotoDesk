// MARK: - 职责说明：待处理队列持久化（docs/09 D16 §2）——Application Support/PendingActions/session-v1.json。
// 原子写 + 0.2s debounce（由 ReviewSessionController 编排）；启动加载；文件损坏 → 改名备份后从空队列开始，
// 绝不 crash；不给 Core Data 加实体（程序化模型未启用自动迁移，docs/09 D07 明令）。

import Foundation
import PhotoDeskCore

@MainActor
final class PendingActionStore {
    struct Payload: Codable {
        var schemaVersion: Int = 1
        var entries: [PendingEntry] = []
    }

    private let fileManager = FileManager.default
    /// 测试/mock 可注入目录；生产 = Application Support/PendingActions
    private let directory: URL

    private var fileURL: URL {
        directory.appendingPathComponent("session-v1.json", isDirectory: false)
    }

    /// nonisolated：允许作为默认参数在 nonisolated 上下文构造（init 内只做目录准备，无共享态）
    nonisolated init(directoryOverride: URL? = nil) {
        if let directoryOverride {
            directory = directoryOverride
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            directory = base.appendingPathComponent("PendingActions", isDirectory: true)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - 读取（启动恢复）

    /// 文件不存在 → 空会话；损坏 → 备份改名（corrupt-<时间戳>）后返回空会话
    func load() -> ReviewSession {
        guard let data = try? Data(contentsOf: fileURL) else { return ReviewSession() }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.schemaVersion == 1 else { return ReviewSession() }
            return ReviewSession(entries: payload.entries)
        } catch {
            let backup = directory.appendingPathComponent("session-v1.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: fileURL, to: backup)
            return ReviewSession()
        }
    }

    // MARK: - 写入（原子）

    func save(_ session: ReviewSession) {
        let payload = Payload(schemaVersion: 1, entries: session.entries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 写失败不致命：内存队列仍在；下次入队再试（docs/09 §7 风险表：原子写 + 启动恢复）
        }
    }

    /// 提交成功清空后调用（删文件即可）
    func clearIfEmpty(_ session: ReviewSession) {
        if session.isEmpty {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
