// MARK: - 职责说明：未捕获异常取证（docs/13 §3.9）——App 启动时 install()，
// NSSetUncaughtExceptionHandler 把 name/reason/调用栈 + 最近 50 条 ViewerTrace 写入
// Application Support/Logs/last-exception.log。只做取证，不拦截、不吞异常（崩溃照常发生）。

import Foundation

enum AppCrashLogger {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NSSetUncaughtExceptionHandler { exception in
            AppCrashLogger.write(exception: exception)
        }
    }

    static var logFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let logs = dir.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("last-exception.log")
    }

    /// 是否存在未读取的崩溃记录（DiagnosticsView 入口用）
    static func hasLastException() -> Bool {
        guard let url = logFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func readLastException() -> String? {
        guard let url = logFileURL, let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    private static func write(exception: NSException) {
        guard let url = logFileURL else { return }
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("time: \(formatter.string(from: Date()))")
        lines.append("name: \(exception.name.rawValue)")
        lines.append("reason: \(exception.reason ?? "-")")
        lines.append("callStackSymbols:")
        lines.append(contentsOf: exception.callStackSymbols)
        lines.append("--- viewer trace (last 50) ---")
        lines.append(contentsOf: ViewerTrace.recentLines(count: 50))
        let text = lines.joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: url)
    }
}
