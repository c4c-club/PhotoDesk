// MARK: - 职责说明：诊断日志导出装配（docs/16 M12 Phase 1）——
// 从 DiagnosticsView 抽出为可测试纯装配：OSLogStore 近 N 小时日志 → 临时文件 → 分享面板。
// M12 后续提交把 last-exception.log 与 viewer-trace.log 一并纳入导出（取证链，docs/16 §2.2）。
// 全部只读本机文件，导出动作不联网。

import Foundation
import OSLog

enum DiagnosticsExporter {
    /// 导出诊断日志到临时文件；返回文件 URL（失败返回 nil，调用方展示错误）
    static func export(hours: Int, now: Date = Date()) -> URL? {
        var lines: [String] = ["PhotoDesk 诊断日志 — \(now)"]
        lines.append(contentsOf: oslogLines(hours: hours))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDesk-diagnostics-\(Int(now.timeIntervalSince1970)).txt")
        do {
            try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
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
