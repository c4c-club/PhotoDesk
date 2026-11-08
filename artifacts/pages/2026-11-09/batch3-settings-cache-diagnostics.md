# M15 批次3 页面档案（2026-11-09）

## 11. 设置 SettingsView（PhotoDesk/Features/Settings/SettingsView.swift）
- 现状：分组入口齐（手势/外观/隐私/安全/缓存/无障碍/教学/诊断）。
- 缺口：关于页只有「版本 AppVersion.display + 构建通道」，缺构建号、系统版本、开源许可声明（FR-K8）。
- 改动：AppVersion 新增 marketingVersion/build 两个只读出处；关于页加「版本 / 构建号 / 系统版本 iOS x.y / 构建通道」四行 + 新「开源许可」Section（仅系统框架声明）；import UIKit。
- 验收：版本/构建号与 project.yml 一致（CI 构建后 Info.plist 注入）。

## 16. 缓存与存储 CacheManagerView（PhotoDesk/Features/Settings/CacheManagerView.swift）
- 结论：**已具备**。磁盘缓存占用来自 imagePipeline.diskCacheBytes（真实文件大小）、撤销副本占用来自 trashBin.allRecords() byteSize 求和（真实）；清理走 confirmationDialog 二次确认；「LRU 淘汰，上限 200 MB」「NSCache 自动管理（上限 60 MB）」自动淘汰说明在列。零改动。

## 17. 诊断日志 DiagnosticsView（PhotoDesk/Features/Settings/DiagnosticsView.swift + Core/Support/DiagnosticsExporter.swift）
- 现状：导出并分享（临时文件 + ActivityView）+ 日志大小已有。
- 缺口：一键复制诊断摘要、清空日志。
- 改动：DiagnosticsExporter 新增 summaryText(now:)（日志占用 + last-exception 尾 60 行 + viewer-trace 尾 100 行，flush 同步屏障）与 clearLogs()（删三个日志文件，按需重建）；DiagnosticsView 新增「诊断摘要」Section（复制诊断摘要 Diagnostics-Copy-Summary / 清空日志 Diagnostics-Clear + confirmationDialog 二次确认 + statusMessage 回执）。
- 验收：摘要可复制进剪贴板；清空后 logBytes 归零；导出文件可打开、不联网（既有）。
