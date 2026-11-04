// MARK: - 职责说明：诊断导出取证链单测（docs/16 M12 Phase 1）——
// 基线红：导出文件必须包含 viewer-trace.log 内容与段头（取证链要求用户能从「设置→诊断」拿到崩溃日志）。
// 实现绿：DiagnosticsExporter 纳入 last-exception.log + viewer-trace.log 后全绿。

import XCTest
@testable import PhotoDesk

final class DiagnosticsExportTests: XCTestCase {
    /// 导出文件必须包含本次写入的 viewer-trace 面包屑（段头 + 内容）
    func testDiagnosticsExportIncludesViewerTrace() throws {
        let marker = "trace-export-marker-\(UUID().uuidString)"
        ViewerTrace.log(marker)
        let url = try XCTUnwrap(DiagnosticsExporter.export(hours: 24))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("viewer-trace.log"),
                      "导出文件缺 viewer-trace 段头（取证链未纳入面包屑日志）")
        XCTAssertTrue(text.contains(marker),
                      "导出文件未包含刚写入的 viewer-trace 内容：\(marker)")
    }

    /// 导出文件必须包含 last-exception.log 段（无崩溃时也要有段头与「无记录」占位）
    func testDiagnosticsExportIncludesLastExceptionSection() throws {
        let url = try XCTUnwrap(DiagnosticsExporter.export(hours: 24))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("last-exception.log"),
                      "导出文件缺 last-exception.log 段头（取证链未纳入崩溃日志）")
    }
}
