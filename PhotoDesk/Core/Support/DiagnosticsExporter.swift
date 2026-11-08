// MARK: - 职责说明：诊断日志导出装配（docs/16 M12 Phase 1）——
// 从 DiagnosticsView 抽出为可测试纯装配，导出三段取证链：
// ① OSLogStore 近 N 小时日志；② last-exception.log（未捕获异常 + 信号级标记，无记录时占位）；
// ③ viewer-trace.log（查看器面包屑：zoom/img/appear 等，导出前 flush 同步屏障）。
// 全部只读本机文件，导出动作不联网。

import Foundation
import OSLog

enum DiagnosticsExporter {
    /// 本机诊断日志当前占用（viewer-trace + last-exception + signal-crash；OSLog 由系统管理不计入）
    static func currentLogBytes() -> Int64 {
        let urls = [ViewerTrace.logFileURL,
                    AppCrashLogger.logFileURL,
                    AppCrashLogger.signalLogFileURL].compactMap { $0 }
        return urls.reduce(0) { total, url in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber else { return total }
            return total + size.int64Value
        }
    }

    /// 导出诊断日志到临时文件；返回文件 URL（失败返回 nil，调用方展示错误）
    static func export(hours: Int, now: Date = Date()) -> URL? {
        var lines: [String] = ["PhotoDesk 诊断日志 — \(now)"]
        lines.append(contentsOf: oslogLines(hours: hours))
        lines.append("")
        lines.append("===== last-exception.log =====")
        lines.append(AppCrashLogger.readLastException() ?? "(无崩溃记录)")
        lines.append("")
        lines.append("===== viewer-trace.log =====")
        ViewerTrace.flush()   // 异步落盘同步屏障：确保面包屑已写完再读
        lines.append(readFile(ViewerTrace.logFileURL) ?? "(无查看器面包屑)")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDesk-diagnostics-\(Int(now.timeIntervalSince1970)).txt")
        do {
            try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 诊断摘要（复制用）：日志占用 + 崩溃记录尾部 + 查看器面包屑尾部，不写临时文件
    static func summaryText(now: Date = Date()) -> String {
        ViewerTrace.flush()
        var lines: [String] = ["PhotoDesk 诊断摘要 — \(now)"]
        lines.append("本机日志占用 \(currentLogBytes()) 字节")
        lines.append("")
        lines.append("===== last-exception.log（尾部 60 行）=====")
        lines.append(contentsOf: tailLines(AppCrashLogger.readLastException() ?? "(无崩溃记录)", 60))
        lines.append("")
        lines.append("===== viewer-trace.log（尾部 100 行）=====")
        lines.append(contentsOf: tailLines(readFile(ViewerTrace.logFileURL) ?? "(无查看器面包屑)", 100))
        return lines.joined(separator: "\n")
    }

    /// 清空本机日志文件（用户在诊断页显式触发；文件在下次写入时按需重建）
    static func clearLogs() {
        ViewerTrace.flush()
        for url in [ViewerTrace.logFileURL,
                    AppCrashLogger.logFileURL,
                    AppCrashLogger.signalLogFileURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func tailLines(_ text: String, _ maxLines: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: .newlines).suffix(maxLines)
    }

    private static func readFile(_ url: URL?) -> String? {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    /// OSLog 条目（iOS 15 可用 OSLogStore(scope: .currentProcessIdentifier)）
    private static func oslogLines(hours: Int) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-Double(hours) * 3600))
            let entries = try store.getEntries(at: position)
            var lines: [String] = []
            var count = 0
            for entry in entries {
                // iOS SDK 下 OSLogEntryWithPayload 的载荷属性不可见——用条目描述（NSObject 描述含时间与内容）
                lines.append(String(describing: entry))
                count += 1
                if count > 5_000 { break }   // 防超大文件
            }
            return lines
        } catch {
            return ["(OSLog 读取失败：\(error.localizedDescription))"]
        }
    }
}
