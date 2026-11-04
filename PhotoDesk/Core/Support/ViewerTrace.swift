// MARK: - 职责说明：查看器面包屑环形缓冲（docs/13 §3.9 / docs/16 M12 Phase 1）——
// 关键节点 open/page/zoom/load/img/stage/plan/commit/remove/appear/close 写入 100 条内存环 +
// 异步串行队列落盘 Application Support/Logs/viewer-trace.log（M12：主线程不再同步 IO，
// utility 串行队列逐条保序；flush() 提供同步屏障，崩溃取证导出/测试读取前调用）。
// AppCrashLogger 在未捕获异常时附带最近 50 条。仅取证，不影响任何业务路径；Release 同样编译。

import Foundation
import os.log

enum ViewerTrace {
    static let limit = 100
    private static let lock = NSLock()
    private static var buffer: [String] = []
    private static let logger = Logger(subsystem: "com.example.PhotoDesk", category: "viewer")
    /// 异步落盘队列（串行保证逐条顺序；utility 不与 UI 抢资源）
    private static let diskQueue = DispatchQueue(label: "com.example.PhotoDesk.viewer-trace",
                                                 qos: .utility)
    /// 目录只创建一次（旧版每次 log 都 createDirectory，放大主线程开销）
    private static let logsDirectory: URL? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let logs = dir.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs
    }()

    static func log(_ line: String) {
        // DateFormatter 非线程安全：格式化与 buffer 追加在同一临界区（log 可从任意线程调用）
        let entry: String
        lock.lock()
        let stamp = stampFormatter.string(from: Date())
        entry = "\(stamp) \(line)"
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

    /// 同步屏障：等待全部在途写盘完成（诊断导出 / 崩溃取证 / 测试读取文件前调用）
    static func flush() {
        diskQueue.sync { }
    }

    static var logFileURL: URL? {
        logsDirectory?.appendingPathComponent("viewer-trace.log")
    }

    private static func appendToDisk(_ line: String) {
        guard let url = logFileURL else { return }
        let data = Data((line + "\n").utf8)
        diskQueue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
