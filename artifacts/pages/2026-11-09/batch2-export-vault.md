# M15 批次2 页面档案（2026-11-09）

## 9. 导出 ExportView / ExportViewModel（PhotoDesk/Features/Export/）
- 现状：格式/长边/质量/去 GPS 齐全；iCloud 下载进度只有文字；重试（Export-Retry）已有；成功回执（savedToLibrary Label）已有。
- 缺口：导出中无法取消；取消/失败会留临时文件。
- 改动：
  - ExportViewModel：新增 activeTask 句柄 + runExport(_:)（统一收口：CancellationError→cleanupCancelledExport 删临时文件不报错；其余→errorMessage）+ cancelExport()；renderExportFile 加三处协作取消检查（起点 checkCancellation / requestSourceURL 后 checkCancellation / 文件落盘后 Task.isCancelled→删文件抛 CancellationError）。
  - ExportView：导出中显示 ProgressView(value:) 进度条 + 「取消导出」按钮（Export-Cancel）；分享按钮仅在非导出态显示；saveToLibrary 改 rethrows；GPS 弹窗两按钮也走 runExport。
- 验收：取消后无残留文件（cleanupCancelledExport + renderExportFile 删文件）；取消不弹错误；进度条可见。

## 8. 已隐藏 VaultView / VaultViewModel（PhotoDesk/Features/Vault/ + PhotoDesk/Core/Vault/）
- 现状：locked/unlocking/unlocked/failed/unavailable 状态机齐；onDisappear 即锁。
- 缺口：failed 态「使用设备密码解锁」按钮实际是 openSystemSettings()（行为与文案不符）；失败原因不可复制；进后台不锁。
- 改动：
  - BiometricGate 新增 evaluatePasswordOnly(reason:)（跳过生物识别直接 .deviceOwnerAuthentication，unavailable/failed 语义复用）。
  - VaultService 新增 unlockWithPassword()；VaultViewModel 新增 unlockWithPassword()（phase=.unlocking→成功 load()→失败按 gate.status 归位）。
  - VaultView failedView：按钮改调 unlockWithPassword（Vault-Unlock-Password）；新增「复制失败原因」（Vault-Copy-Failure，UIPasteboard + actionMessage）；新增 onChange(scenePhase)：.background→viewModel.lock()（.inactive 是 Face ID 弹窗常态不触发）。
- 验收：按钮行为与文案一致（密码弹窗）；失败原因可复制；后台立即锁定。
