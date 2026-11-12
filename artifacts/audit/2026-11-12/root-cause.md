# M16 根因取证（fresh audit，仅当前源码证据）

> 生成：audit-m16.ps1（generatedAt 2026-11-13T00:44:13+08:00）。证据全部来自本轮对当前源码的扫描（同轮 audit.json 可交叉核对）；不引用 docs/25/27 的任何历史结论。

## P0-1A 查看器缩放（入口 A）

**现象关联**：连续捏合缩小/放大时崩溃/黑屏/卡死（docs/28 §1 验收目标）。

**证据（当前源码）**：

| 文件:行 | 代码 |
|---|---|
| PhotoDesk/Features/Viewer/ViewerViewController.swift:784 | guard gesture.state == .began else { return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:141 | guard !isAnimating else { gesture.state = .cancelled; return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:167 | guard !isAnimating, transform.scale > 1.01 else { gesture.state = .cancelled; return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:192 | gesture.state == .ended, !isAnimating else { return } |
| PhotoDesk/Features/Viewer/ZoomInteractionController.swift:208 | guard gesture.state == .ended else { return } |

**触发条件**：动画/收敛窗口（Phase = animating 或 settling）内再次捏合——handlePinch 的 .began 命中 guard !isAnimating 直接置 gesture.state = .cancelled（被取消手势的后续触摸事件仍会到达）；随后 UIKit 送达的 .changed/.ended 被 guard phase == .pinching 丢弃，状态机停在非 idle 窗口；动画块内 imageView.transform/center 持续改写，与 cell 复用/翻页 zoomController.reset 竞态。

**根因分级**：R2 结构性（状态机在动画窗口拒绝新手势而不是并入事务）+ R3 概率时序（复用/翻页与动画竞态）。

## P0-1B 网格捏合换列（入口 B）

**证据（当前源码）**：

| 文件:行 | 代码 |
|---|---|

**触发条件**：捏合 .changed 每跨一次列数阈值即调 setColumns(animated: true) → setCollectionViewLayout(makeLayout, animated: true) 启动动画布局过渡；过渡未完成再次跨阈值又起新过渡；过渡完成回调内 reloadItems(indexPathsForVisibleItems) 绕过 Diffable 数据源（同文件 viewDidLayoutSubviews 注释已确认与 dataSource.apply 撞车触发 _existingNumberOfItemsInSection abort 的先例），过渡中 scrollToItem(anchor) 再触发布局。连续快速捏合时事件与过渡交错即崩。

**根因分级**：R1 直接崩溃（Diffable 批更新与动画布局过渡/裸 reloadItems 竞态）+ R2 结构性（捏合全程应单飞事务，逐帧换列无事务边界）。

## P0-2 上次浏览位置（概率事件）

**证据（当前源码）**：

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
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:90 | phase = .settled |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:94 | phase = attempts >= 2 ? .settled : .applying |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:102 | phase = .settled |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:107 | /// 用户主动接管（月份跳转/回到顶部/手动滚动取消）：立即 settled，此后允许保存。 |
| PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift:111 | phase = .settled |

**触发条件**：三条链各自带概率——① 保存链：makePositionSnapshot 在无完整可见 cell（恢复遮罩期间、索引未完成、刚切查询）返回 nil，保存静默丢失；② 首批窗口链：fetchFirstBatch 以锚点为中心截断（windowStart = anchorIndex − batchSize/2），尾部/头部索引由后台补齐，恢复时 isIndexComplete 未就绪则 anchorMinY 走估算 layoutAttributes，scrollToItem 落点偏移；③ 回填链：头部回填 allItems = freshHead + allItems 前插后，contentOffset 依赖 enforceHeadInsertAnchor 逐布局 pass 收敛，收敛期间任何一次保存（scroll 防抖、dragging/decelerating/rest/resignActive）都会把脏 offset 写盘，下次冷启动按脏值恢复。

**根因分级**：R3 概率时序（head 回填、恢复、用户滚动三者竞速）+ R4 假绿（UI 测试以 AX 值/宽松范围断言落点）。

## P0-3 滑动多选（不显示选中/数量不对）

**证据（当前源码）**：

| 文件:行 | 代码 |
|---|---|

**触发条件**：① 命中几何：marqueeGeometry 的 sectionOriginY 读 layoutAttributesForSupplementaryView 的当前 frame，而月份头 pinToVisibleBounds = true——粘性头被钉住时 minY ≠ 该 section 的静态原点，矩形命中整体偏移一个头高；② 计数：applySlideSelection 仅在 previous.count != current.count 时刷新计数——等量替换（框选与已选恰好数量相同）时顶部计数停在旧值；③ 渲染：角标可见性 = isSelectingVisible && isSelectedCell 双标志，configure/复用路径只置其一即缺角标；④ scope：enterSelectionMode 默认 scope 取 currentItemsBySection.flatMap（已提交快照）而非 filteredItems 全量，索引未完成时 scope 缺尾部照片。

**根因分级**：R2 结构性（几何/渲染/计数三处均非单一事实来源）+ R4 假绿（accessibilityValue 仅 DEBUG 写入，AX 断言不证明视觉）。

## 红线扫描（本轮命中 6 · 违规 0）

- coreAppleImport：命中 0 · 违规 0
- urlSession：命中 0 · 违规 0
- tryForce：命中 0 · 违规 0
- asForce：命中 2 · 违规 0
- ios17Api：命中 0 · 违规 0
- forbiddenCopy：命中 4 · 违规 0

判定规则：asForce 仅生产代码计违规（测试 target 豁免）；forbiddenCopy 仅非否定语境计违规（否定句/说明语境属合规，M15 先例 docs/05 变更 17）；其余检查命中即违规。

## 与测试缺口的关系

上述四条根因的红测试清单见同目录 test-gap.md（P0-1A→T01、P0-1B→T02、P0-2→T03、P0-3→T04、X01–X16→T11A）。

