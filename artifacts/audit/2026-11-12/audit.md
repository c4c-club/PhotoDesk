# PhotoDesk M16 基线审查（generatedAt 2026-11-14T04:36:50+08:00）

## 1. 基线

| 项 | 值 |
|---|---|
| 分支 | fix/m16-20261112 |
| HEAD | f7267c27971310dfdea446be5484dcf83d5725e4 |
| 最后提交 | f7267c27971310dfdea446be5484dcf83d5725e4 2026-11-14 02:55:33 +0800 test(position): deep 测试轮询 all≥500 等深库就绪 |
| 扫描器 | rg |

### 版本

| 键 | 值 |
|---|---|
| MARKETING_VERSION | 1.5.0 |
| CURRENT_PROJECT_VERSION | 6 |
| IPHONEOS_DEPLOYMENT_TARGET | 16.0 |
| SWIFT_VERSION | 5.9 |

### 规模

| 目录 | Swift 文件 | 行数 |
|---|---:|---:|
| PhotoDesk | 111 | 19782 |
| PhotoDeskCore/Sources | 33 | 2990 |
| PhotoDeskCore/Tests | 29 | 3913 |
| PhotoDeskTests | 32 | 5054 |
| PhotoDeskUITests | 10 | 3251 |

## 2. 红线（命中 6 · 违规 0）

| 检查 | 命中 | 违规 |
|---|---:|---:|
| coreAppleImport | 0 | 0 |
| urlSession | 0 | 0 |
| tryForce | 0 | 0 |
| asForce | 2 | 0 |
| ios17Api | 0 | 0 |
| forbiddenCopy | 4 | 0 |

判定规则（确定性）：asForce 仅生产代码计违规（测试 target 豁免）；forbiddenCopy 仅非否定语境计违规（否定句/说明语境属合规，M15 先例 docs/05 变更 17）；其余检查命中即违规。

### 豁免明细

| 检查 | 文件:行 | 代码 | 豁免原因 |
|---|---|---|---|
| asForce | PhotoDeskTests/MetadataParserTests.swift:59 | var gps = properties[kCGImagePropertyGPSDictionary as String] as! [String: Any] | 豁免：测试 target 断言转换 |
| asForce | PhotoDeskTests/MetadataParserTests.swift:72 | var exif = properties[kCGImagePropertyExifDictionary as String] as! [String: Any] | 豁免：测试 target 断言转换 |
| forbiddenCopy | PhotoDesk/Core/Support/SettingsStore.swift:13 | /// 展示名（docs/04 §7 文案口径：删除一律「移到最近删除」，禁用「彻底删除」） | 豁免：否定句/说明语境 |
| forbiddenCopy | PhotoDesk/Features/Library/RecentlyDeletedView.swift:74 | faqRow("应用能帮我彻底删除照片吗？", | 豁免：否定句/说明语境 |
| forbiddenCopy | PhotoDesk/Features/Settings/GestureSettingsView.swift:84 | Text("上下滑标记不会立刻删除：先进入待删除清单，点「全部移到最近删除」时 iOS 弹一次系统确认（每批一次，不是每张一次）。照片进入系统「最近删除」保留 30 天，本 App 不提供永久删除。") | 豁免：否定句/说明语境 |
| forbiddenCopy | PhotoDesk/Features/Settings/PrivacyView.swift:33 | detail: "所有「删除」都是移入系统「最近删除」，由系统保留 30 天后清除，本 App 不提供永久删除。") | 豁免：否定句/说明语境 |

### asForce 明细

| 文件:行 | 代码 |
|---|---|
| PhotoDeskTests/MetadataParserTests.swift:59 | var gps = properties[kCGImagePropertyGPSDictionary as String] as! [String: Any] |
| PhotoDeskTests/MetadataParserTests.swift:72 | var exif = properties[kCGImagePropertyExifDictionary as String] as! [String: Any] |

### forbiddenCopy 明细

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Core/Support/SettingsStore.swift:13 | /// 展示名（docs/04 §7 文案口径：删除一律「移到最近删除」，禁用「彻底删除」） |
| PhotoDesk/Features/Library/RecentlyDeletedView.swift:74 | faqRow("应用能帮我彻底删除照片吗？", |
| PhotoDesk/Features/Settings/GestureSettingsView.swift:84 | Text("上下滑标记不会立刻删除：先进入待删除清单，点「全部移到最近删除」时 iOS 弹一次系统确认（每批一次，不是每张一次）。照片进入系统「最近删除」保留 30 天，本 App 不提供永久删除。") |
| PhotoDesk/Features/Settings/PrivacyView.swift:33 | detail: "所有「删除」都是移入系统「最近删除」，由系统保留 30 天后清除，本 App 不提供永久删除。") |
## 3. P0-1A 查看器缩放证据

### 3.viewForZooming（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.scrollDelegate（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.zoomScaleApi（2 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Features/Viewer/ZoomableImageCell.swift:34 | view.minimumZoomScale = 1 |
| PhotoDesk/Features/Viewer/ZoomableImageCell.swift:35 | view.maximumZoomScale = 1 |

### 3.contentInset（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.gestureStateAssign（3 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Features/Viewer/ViewerViewController.swift:791 | guard gesture.state == .began else { return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:230 | gesture.state == .ended, |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:248 | guard gesture.state == .ended else { return } |

### 3.animatingGuard（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.phaseGuardDrop（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.catransactionWrite（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.resetOnReuse（0 处）

| 文件:行 | 代码 |
|---|---|

### 3.policyClamp（0 处）

| 文件:行 | 代码 |
|---|---|

## 4. P0-1B 网格捏合证据

### 4.pinchChangedColumn（0 处）

| 文件:行 | 代码 |
|---|---|

### 4.setColumnsAnimated（0 处）

| 文件:行 | 代码 |
|---|---|

### 4.setCollectionViewLayout（0 处）

| 文件:行 | 代码 |
|---|---|

### 4.reloadVisibleItems（0 处）

| 文件:行 | 代码 |
|---|---|

### 4.scrollToInTransition（0 处）

| 文件:行 | 代码 |
|---|---|

### 4.pinToVisibleBounds（0 处）

| 文件:行 | 代码 |
|---|---|

### 4.gestureStateAssign（0 处）

| 文件:行 | 代码 |
|---|---|

## 5. P0-2 位置记忆证据

### 5.saveCallSites（0 处）

| 文件:行 | 代码 |
|---|---|

### 5.storeSchema（17 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Core/Support/LibraryPositionStore.swift:12 | /// schemaVersion 1–5 兼容解码；新数据一律走 LibraryPositionV6。 |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:25 | let schemaVersion: Int |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:30 | case offsetRatio, contentHeight, viewportHeight, savedAt, schemaVersion |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:48 | schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1 |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:64 | try c.encode(schemaVersion, forKey: .schemaVersion) |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:78 | schemaVersion: Int, |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:91 | self.schemaVersion = schemaVersion |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:116 | let schemaVersion: Int |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:130 | schemaVersion: Int = 6) { |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:143 | self.schemaVersion = schemaVersion |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:149 | schemaVersion == 6 |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:175 | schemaVersion: schemaVersion) |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:194 | schemaVersion: 6) |
| PhotoDesk/Core/Support/PositionFileStore.swift:3 | // { "schemaVersion": 6, "entries": { "<queryKey>": LibraryPositionV6 } }。 |
| PhotoDesk/Core/Support/PositionFileStore.swift:13 | static let schemaVersion = 6 |
| PhotoDesk/Core/Support/PositionFileStore.swift:17 | var schemaVersion: Int = PositionFileStore.schemaVersion |
| PhotoDesk/Core/Support/PositionFileStore.swift:23 | var schemaVersion: Int = 5 |

### 5.restoreEntries（0 处）

| 文件:行 | 代码 |
|---|---|

### 5.settledGate（29 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:2 | // 唯一 save/restore 入口。保存由 Core PositionRestoreMachineV6 门禁：canSave 只在 settled |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:5 | // 补偿）→ applying（一次）→ verifying（真实 attributes；nil = 失败，v5 默认通过是假 settled 根因） |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:6 | // → settled；verify 失败重试一次，两次 → fallback（锚点 cell 顶部 / section / ratio，绝不假 settled）。 |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:30 | let isIndexComplete: Bool |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:84 | // MARK: - 保存（I1/I2：canSave 只在 settled；§5.6 触发矩阵） |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:147 | /// 只 load 一次锚点；queryKey 变化才重置状态机。无锚点直接 settled（不遮罩、可保存）。 |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:207 | case .idle, .settled: |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:217 | let phase = machine.anchorMissing(indexComplete: context.isIndexComplete) |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:226 | indexComplete: context.isIndexComplete) |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:244 | if context.isIndexComplete { |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:303 | case .settled: |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:322 | // v6：两次 verify 仍失败 → 锚点 cell 顶部兜底（不假 settled） |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:330 | /// 不在 → sectionID+index → ratio 逐级退化。全部直接收敛 settled，不再进 verify。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:2 | // idle → loading → waitingForWindow → waitingForHead → applying → verifying → settled； |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:5 | // ② waitingForHead 结束条件 = isIndexComplete && headInsertGeneration 连续两轮不变； |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:6 | // ③ applying 只允许一次，重复调用直接返回；④ verify 两次失败 → fallback（绝不假 settled）； |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:8 | // canSave 仍只在 settled。纯 Foundation，零 UIKit。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:19 | case settled |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:42 | case .idle, .settled: |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:49 | /// v6 门禁：只有恢复彻底完成（settled）才允许写盘。 |
| … |（其余 9 条见 audit.json） |

### 5.verifyNilBranch（0 处）

| 文件:行 | 代码 |
|---|---|

### 5.machineVerifyNil（0 处）

| 文件:行 | 代码 |
|---|---|

### 5.vmFirstBatchWindow（0 处）

| 文件:行 | 代码 |
|---|---|

### 5.vmHeadBackfill（0 处）

| 文件:行 | 代码 |
|---|---|

## 6. P0-3 滑动多选证据

### 6.marqueeGeometry（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.stickyHeaderOrigin（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.visibleTraversal（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.countGate（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.updateSelectionCount（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.badgeVisibility（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.axValueDebugOnly（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.scopeFromSnapshot（0 处）

| 文件:行 | 代码 |
|---|---|

### 6.slideScopeProvider（0 处）

| 文件:行 | 代码 |
|---|---|

## 7. Features 页面静态清单（入口/空态/错误态/按钮）

| 页面目录 | 文件数 | 入口标识（前 8） | 空态命中 | 错误态命中 | 按钮符号 |
|---|---:|---|---:|---:|---:|
| Albums | 2 | (none) |  | 10 | 3 |
| Cleanup | 2 | (none) | 0 | 4 | 4 |
| Editor | 4 | (none) | 0 | 4 | 2 |
| Export | 4 | (none) | 0 | 7 | 0 |
| Library | 13 | Library-Category, Library-Filter, Library-JumpBanner, Library-MonthJump, Library-RestoreMask, Library-Search, Library-Select, Library-Tools …共12 | 7 | 9 | 25 |
| Metadata | 1 | (none) | 0 | 0 | 0 |
| Onboarding | 2 | (none) | 0 | 0 | 4 |
| Search | 2 | (none) | 0 | 0 | 3 |
| Session | 2 | (none) | 0 | 4 | 5 |
| Settings | 8 | (none) | 0 | 5 | 4 |
| Vault | 3 | (none) | 0 | 6 | 8 |
| Viewer | 11 | SessionBadge, Viewer-Close, Viewer-Debug, ViewerRoot, Viewer-ZoomScrollView | 0 | 12 | 11 |

## 8. 测试清单

| 层 | 类数 | test 函数数 |
|---|---:|---:|
| PhotoDeskCore/Tests | 31 | 405 |
| PhotoDeskTests | 32 | 250 |
| PhotoDeskUITests | 10 | 77 |

## 9. 输出文件

- audit.md（本文件）
- audit.json
- root-cause.md
- test-gap.md

