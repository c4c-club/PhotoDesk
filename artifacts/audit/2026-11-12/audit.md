# PhotoDesk M16 基线审查（generatedAt 2026-11-13T00:44:13+08:00）

## 1. 基线

| 项 | 值 |
|---|---|
| 分支 | fix/m16-20261112 |
| HEAD | 864af86510feec9b6c0369b8ea6025c8473e82a9 |
| 最后提交 | 864af86510feec9b6c0369b8ea6025c8473e82a9 2026-11-12 23:07:45 +0800 docs(m15): 全量绿最终数字回填 docs/27（run 43128234097 全绿）+ release manifest 更新为 27fcdcb IPA |
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
| PhotoDesk | 110 | 19153 |
| PhotoDeskCore/Sources | 30 | 2627 |
| PhotoDeskCore/Tests | 26 | 3347 |
| PhotoDeskTests | 30 | 4545 |
| PhotoDeskUITests | 9 | 2823 |

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

### 3.gestureStateAssign（5 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Features/Viewer/ViewerViewController.swift:784 | guard gesture.state == .began else { return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:141 | guard !isAnimating else { gesture.state = .cancelled; return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:167 | guard !isAnimating, transform.scale > 1.01 else { gesture.state = .cancelled; return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:192 | gesture.state == .ended, !isAnimating else { return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:208 | guard gesture.state == .ended else { return } |

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

### 5.storeSchema（11 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Core/Support/LibraryPositionStore.swift:2 | // v5 = 视觉锚点 assetID + 视口内视觉 y + queryKey + schemaVersion=5；v1–v4 字段保留解码兼容。 |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:30 | let schemaVersion: Int |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:42 | schemaVersion: Int = PositionAnchorPolicy.schemaVersion, |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:54 | self.schemaVersion = schemaVersion |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:62 | case contentHeight, viewportHeight, savedAt, schemaVersion |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:81 | schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1 |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:97 | try c.encode(schemaVersion, forKey: .schemaVersion) |
| PhotoDesk/Core/Support/LibraryPositionStore.swift:112 | schemaVersion: schemaVersion) |
| PhotoDesk/Core/Support/PositionFileStore.swift:3 | // { "schemaVersion": 5, "entries": { "<queryKey>": LibraryPosition } }。 |
| PhotoDesk/Core/Support/PositionFileStore.swift:12 | static let schemaVersion = 5 |
| PhotoDesk/Core/Support/PositionFileStore.swift:16 | var schemaVersion: Int = PositionFileStore.schemaVersion |

### 5.restoreEntries（0 处）

| 文件:行 | 代码 |
|---|---|

### 5.settledGate（25 处）

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:2 | // 唯一 save/restore 入口。保存由 Core PositionRestoreMachineV5 门禁：canSave 只在 settled |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:5 | // → 钳制 → setContentOffset → verify ±0.5pt → 失败只调 offset 重试一次 → 两次仍失败 settled（不阻塞 UI）。 |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:26 | let isIndexComplete: Bool |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:71 | // MARK: - 保存（I1/I2：canSave 只在 settled） |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:120 | /// 只 load 一次锚点；queryKey 变化才重置状态机。无锚点直接 settled（不遮罩、可保存）。 |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:162 | indexComplete: context.isIndexComplete, |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:169 | indexComplete: context.isIndexComplete, |
| PhotoDesk/Features/Library/LibraryPositionCoordinator.swift:247 | case .settled: |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:2 | // idle → restoring → applying → verifying → settled / fallback； |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:4 | // canSave 只在 settled（I1：恢复完成前任何保存都不得写盘）；verify 失败只重试一次，两次仍失败 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:5 | // → settled（调用方 DEBUG 记 verify-failed，不阻塞 UI）。纯 Foundation，零 UIKit。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:14 | case settled |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:27 | /// 恢复流程是否进行中（此期间所有保存必须拒绝；settled/fallback 兜底应用也在此列）。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:30 | case .idle, .settled: |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:37 | /// v5 门禁：只有恢复彻底完成（settled）才允许写盘。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:38 | public var canSave: Bool { phase == .settled } |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:40 | /// 开始恢复：无锚点直接 settled(top)（允许保存）；有锚点进入 restoring。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:44 | phase = hasAnchor ? .restoring : .settled |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:84 | /// 校验结果：ok → settled；失败累计 attempts，第 1 次失败回 applying 重试（只调 offset）， |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:85 | /// 第 2 次仍失败 → settled（优雅放弃，不阻塞 UI）。 |
| … |（其余 5 条见 audit.json） |

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
| Library | 12 | Library-Category, Library-Filter, Library-JumpBanner, Library-MonthJump, Library-RestoreMask, Library-Search, Library-Select, Library-Tools …共12 | 7 | 7 | 25 |
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
| PhotoDeskCore/Tests | 28 | 338 |
| PhotoDeskTests | 30 | 223 |
| PhotoDeskUITests | 9 | 67 |

## 9. 输出文件

- audit.md（本文件）
- audit.json
- root-cause.md
- test-gap.md

