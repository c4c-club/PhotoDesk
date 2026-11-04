// MARK: - 职责说明：未捕获异常 + 信号级崩溃取证（docs/13 §3.9 / docs/16 M12 Phase 1）——
// install() 两层：
// ① NSSetUncaughtExceptionHandler：NSException（OC 层异常）→ name/reason/调用栈 + 最近 50 条
//    ViewerTrace 写入 Application Support/Logs/last-exception.log；
// ② signal() 兜底 SIGABRT/SIGILL/SIGSEGV/SIGBUS/SIGFPE/SIGTRAP：Swift fatal（precondition 失败 /
//    强制解包 nil / 数组越界）不产生 NSException、只有信号——处理器内用异步信号安全系统调用
//    （open/write/close）写一行标记；路径与文案字节在 install 时写入 malloc 固定缓冲，
//    处理器内零堆分配、零锁、零 Objective-C 运行时调用。
// 能力边界（如实声明，不得宣称更多）：
// - 信号处理器内无法安全采集符号栈（走 runtime/堆分配都可能死锁）——完整崩溃栈由系统 .ips 承载；
// - 抓不到 jetsam（内存压力由系统直接终止，不经过任何信号）与 watchdog 终止（0x8badf00d）；
// - 只做取证，不拦截、不吞异常：写完标记后恢复默认信号处理，让崩溃照常发生并生成 .ips。

import Darwin
import Foundation

enum AppCrashLogger {
    private static var installed = false
    /// 信号处理器用的预计算缓冲（install 时 malloc + 填充；处理器内只读）
    static let signalPathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: 1024)
    static var signalSuffixBuffer: UnsafeMutablePointer<UInt8>?
    static var signalSuffixCount = 0

    static func install() {
        guard !installed else { return }
        installed = true
        NSSetUncaughtExceptionHandler { exception in
            AppCrashLogger.write(exception: exception)
        }
        installSignalHandlers()
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

    // MARK: - 信号级兜底（docs/16 M12 Phase 1）

    private static func installSignalHandlers() {
        guard let url = logFileURL,
              let pathBytes = url.path.cString(using: .utf8),
              pathBytes.count <= 1024 else { return }
        // 固定缓冲一次性填充（进程生命周期持有；处理器内只读、零分配）
        pathBytes.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                _ = memcpy(signalPathBuffer, base, pathBytes.count)
            }
        }
        // 文案在 install 时预算（处理器内不构造 String；时间戳由文件 mtime 与系统 .ips 承载）
        let suffix = "\n(信号级兜底：无符号栈——完整崩溃栈见系统 .ips；操作面包屑见同目录 viewer-trace.log)\n"
        let suffixBytes = Array(suffix.utf8)
        let suffixBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: suffixBytes.count)
        suffixBytes.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                _ = memcpy(suffixBuffer, base, suffixBytes.count)
            }
        }
        signalSuffixBuffer = suffixBuffer
        signalSuffixCount = suffixBytes.count

        for code in [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGTRAP] {
            signal(code, signalCrashHandler)
        }
    }
}

/// 信号处理器（顶层函数，可安全转 @convention(c)）：只调用异步信号安全 API（open/write/close），
/// 零堆分配——路径与文案字节由 AppCrashLogger 在 install 时预写入 malloc 缓冲；
/// 头部 "signal=" 与信号码用栈上元组承载（Darwin 信号 1–31，最多 2 位十进制）。
private func signalCrashHandler(_ code: Int32) {
    let path = AppCrashLogger.signalPathBuffer   // 固定缓冲（install 时分配，非 Optional）
    guard let suffix = AppCrashLogger.signalSuffixBuffer else { return }
    let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
    guard fd >= 0 else { return }
    let prefix: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (115, 105, 103, 110, 97, 108, 61) // "signal="
    let digits: (UInt8, UInt8) = code >= 10
        ? (UInt8(code / 10) + 48, UInt8(code % 10) + 48)   // "0"+d
        : (UInt8(code % 10) + 48, 0)
    let digitCount: Int = code >= 10 ? 2 : 1
    withUnsafeBytes(of: prefix) { _ = write(fd, $0.baseAddress, 7) }
    withUnsafeBytes(of: digits) { _ = write(fd, $0.baseAddress, digitCount) }
    _ = write(fd, suffix, AppCrashLogger.signalSuffixCount)
    close(fd)
    // 恢复默认处理并重发信号：取证后照常崩溃，系统生成 .ips（不拦截、不吞）
    signal(code, SIG_DFL)
    raise(code)
}
