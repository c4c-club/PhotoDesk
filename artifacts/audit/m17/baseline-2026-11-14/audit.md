# M17 基线审查（自动生成，只读扫描）

- generatedAt: 2026-11-13T23:39:58Z
- root: C:/Users/RuiZh/Desktop/photo_manager
- blocking failures: 9 / 19

| 编号 | 级别 | 检查 | 期望 | 结果 | 命中数 |
|---|---|---|---|---|---|
| A01 | WARN | 框选几何来源：DSSpacing 估算 vs 真实 layoutAttributes | empty | FAIL | 1 |
| A02 | WARN | supplementary attributes 参与命中（粘性头可能污染 originY，需实测） | empty | FAIL | 3 |
| A03 | INFO | 网格粘性头开关（记录用） | present | PASS | 2 |
| A04 | BLOCKING | 网格必须支持长按进入多选 | present | FAIL | 0 |
| A05 | BLOCKING | 多选模式不得用双指规则劫持单指滚动 | empty | FAIL | 2 |
| A06 | BLOCKING | 框选必须有方向锁（垂直拖动让位滚动） | present | FAIL | 0 |
| A07 | BLOCKING | 框选必须有可视反馈（选框/压暗/动画） | present | FAIL | 0 |
| A08 | BLOCKING | 多选 scope 必须取全量筛选结果 | empty | FAIL | 3 |
| A09 | BLOCKING | 框选每帧不得 O(n log n) 全量排序替换 | empty | FAIL | 1 |
| A10 | BLOCKING | Feature 层不得直接引用 PHAsset（AGENTS 3.1） | empty | FAIL | 13 |
| A11 | BLOCKING | iOS 16 基线：不得出现 iOS 17+ API | empty | PASS | 0 |
| A12 | BLOCKING | 禁止 try! / as! | empty | PASS | 0 |
| A13 | WARN | 红线 1 文案：人工核对永久删除/彻底删除出现处 | empty | FAIL | 4 |
| A14 | BLOCKING | UI 测试必须覆盖长按进入 | present | FAIL | 0 |
| A15 | BLOCKING | 命中计算不得每帧遍历全部 section 查询布局 | empty | FAIL | 1 |
| A16 | INFO | DEBUG 自动滚动诊断采样（记录用） | present | PASS | 3 |
| A17 | INFO | 布局横向 interItemSpacing 已显式设置（与几何公式需一致性核对） | present | PASS | 1 |
| A18 | BLOCKING | PhotoDeskCore 零 Apple UI 依赖 | empty | PASS | 0 |
| A19 | WARN | SlideSelectPolicy 遗留方向锁/往返统计函数是否仍被引用（死代码） | empty | PASS | 0 |

## 命中明细

### A01 - 框选几何来源：DSSpacing 估算 vs 真实 layoutAttributes [FAIL]
- PhotoDesk/Features/Library/LibraryViewController.swift:963 - let itemSide = (width - spacing * Double(max(1, columns - 1))) / Double(max(1, columns))

### A02 - supplementary attributes 参与命中（粘性头可能污染 originY，需实测） [FAIL]
- PhotoDesk/Features/Library/LibraryViewController.swift:972 - if let attrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
- PhotoDesk/Features/Library/LibraryViewController.swift:1547 - let headerAttrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
- PhotoDesk/Features/Library/LibraryViewController.swift:1602 - guard let attrs = collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(

### A03 - 网格粘性头开关（记录用） [PASS]
- PhotoDesk/Features/Library/LibraryViewController.swift:3 - // 粘性分组头（boundarySupplementaryItem.pinToVisibleBounds）+ Prefetching + 分页（接近底部续页 500/批）+
- PhotoDesk/Features/Library/LibraryViewController.swift:1748 - header.pinToVisibleBounds = true

### A05 - 多选模式不得用双指规则劫持单指滚动 [FAIL]
- PhotoDesk/Features/Library/LibraryViewController.swift:802 - collectionView.panGestureRecognizer.minimumNumberOfTouches = 2
- PhotoDesk/Features/Library/LibraryViewController.swift:832 - collectionView.panGestureRecognizer.minimumNumberOfTouches = 2

### A08 - 多选 scope 必须取全量筛选结果 [FAIL]
- PhotoDesk/Features/Library/LibraryViewController.swift:797 - let scope = scopeOverride ?? Set(currentItemsBySection.flatMap { $0.map(\.id) })
- PhotoDesk/Features/Library/LibraryViewController.swift:940 - let scope = Set(self.currentItemsBySection.flatMap { $0.map(\.id) })
- PhotoDesk/Features/Library/LibraryViewController.swift:1229 - let newScope = Set(self.currentItemsBySection.flatMap { $0.map(\.id) })

### A09 - 框选每帧不得 O(n log n) 全量排序替换 [FAIL]
- PhotoDesk/Features/Library/LibraryViewController.swift:994 - selectionState.replaceSelection(Array(ids).sorted())

### A10 - Feature 层不得直接引用 PHAsset（AGENTS 3.1） [FAIL]
- PhotoDesk/Features/Albums/AlbumsView.swift:124 - private func fetchSummaries(type: PHAssetCollectionType) -> [AlbumSummary] {
- PhotoDesk/Features/Albums/AlbumsView.swift:125 - let result = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
- PhotoDesk/Features/Albums/AlbumsView.swift:129 - let assets = PHAsset.fetchAssets(in: collection, options: nil)
- PhotoDesk/Features/Albums/AlbumsView.swift:134 - let cover = PHAsset.fetchAssets(in: collection, options: firstOptions).firstObject
- PhotoDesk/Features/Editor/EditorViewModel.swift:57 - let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
- PhotoDesk/Features/Export/ExportViewModel.swift:3 - // ExportRenderer 文件渲染 → 保存到相册（PHAssetCreationRequest）或分享（临时 URL → ActivityViewWrapper）。
- PhotoDesk/Features/Export/ExportViewModel.swift:51 - let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
- PhotoDesk/Features/Export/ExportViewModel.swift:116 - /// 保存到相册（PHAssetCreationRequest；creationDate 沿用原件）
- PhotoDesk/Features/Metadata/MetadataView.swift:2 - // 尺寸/字节数/格式（PHAssetResource originalFilename 后缀 + UTType）+ EXIF 行
- PhotoDesk/Features/Metadata/MetadataView.swift:198 - /// 字节数 + 格式（PHAssetResource；fileSize KVC 失败回退 0——M1 KVC 崩溃教训）
- PhotoDesk/Features/Metadata/MetadataView.swift:200 - let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)
- PhotoDesk/Features/Metadata/MetadataView.swift:202 - let resources = PHAssetResource.assetResources(for: asset)
- PhotoDesk/Features/Metadata/MetadataView.swift:224 - let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil)

### A13 - 红线 1 文案：人工核对永久删除/彻底删除出现处 [FAIL]
- PhotoDesk/Core/Support/SettingsStore.swift:13 - /// 展示名（docs/04 §7 文案口径：删除一律「移到最近删除」，禁用「彻底删除」）
- PhotoDesk/Features/Library/RecentlyDeletedView.swift:74 - faqRow("应用能帮我彻底删除照片吗？",
- PhotoDesk/Features/Settings/GestureSettingsView.swift:84 - Text("上下滑标记不会立刻删除：先进入待删除清单，点「全部移到最近删除」时 iOS 弹一次系统确认（每批一次，不是每张一次）。照片进入系统「最近删除」保留 30 天，本 App 不提供永久删除。")
- PhotoDesk/Features/Settings/PrivacyView.swift:33 - detail: "所有「删除」都是移入系统「最近删除」，由系统保留 30 天后清除，本 App 不提供永久删除。")

### A15 - 命中计算不得每帧遍历全部 section 查询布局 [FAIL]
- PhotoDesk/Features/Library/LibraryViewController.swift:970 - for section in 0..<counts.count {

### A16 - DEBUG 自动滚动诊断采样（记录用） [PASS]
- PhotoDesk/Features/Library/SlideSelectGestureController.swift:41 - private var scrollDeltaSum: Double = 0
- PhotoDesk/Features/Library/SlideSelectGestureController.swift:45 - "delta=\(Int(scrollDeltaSum)) mem=\(holdScrollDirection?.direction.description ?? "nil")"
- PhotoDesk/Features/Library/SlideSelectGestureController.swift:222 - scrollDeltaSum += abs(Double(target) - Double(collectionView.contentOffset.y)) == 0

### A17 - 布局横向 interItemSpacing 已显式设置（与几何公式需一致性核对） [PASS]
- PhotoDesk/Features/Library/LibraryViewController.swift:1736 - group.interItemSpacing = .fixed(DSSpacing.gridSpacing)
