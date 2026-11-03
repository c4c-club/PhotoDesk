// MARK: - 职责说明：查看器面包屑环形缓冲（docs/13 §3.9 崩溃取证）——
// 关键节点 open/page/zoom/load/stage/plan/commit/remove/close 写入 100 条内存环 + 逐条落盘
// Application Support/Logs/viewer-trace.log；AppCrashLogger 在未捕获异常时附带最近 50 条。
// 仅取证，不影响任何业务路径；Release 同样编译（真机回传日志用）。

import Foundation
import os.log

enum ViewerTrace {
    static let limit = 100
    private static let lock = NSLock()
    private static var buffer: [String] = []
    private static let logger = Logger(subsystem: "com.example.PhotoDesk", category: "viewer")
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ line: String) {
        let entry = "\(stampFormatter.string(from: Date())) \(line)"
        lock.lock()
        buffer.append(entry)
        if buffer.count > limit {
            buffer.removeFirst(buffer.count - limit)
        }
        lock.unlock()
        logger.info("\(entry, privacy: .public)")
        appendToDisk(entry)
    }

    static func recentLines(count: Int = 50) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(buffer.suffix(count))
    }

    static var logFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let logs = dir.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("viewer-trace.log")
    }

    private static func appendToDisk(_ line: String) {
        guard let url = logFileURL else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
