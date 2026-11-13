# M16 测试缺口与红测试计划（fresh audit）

> 生成：audit-m16.ps1（generatedAt 2026-11-14T04:36:50+08:00）。基线 = 864af86。计划类名以本文件为准；后续任务卡执行时若与类名有出入，以任务卡为准并在 docs/31 验收记录对齐。

## P0 缺口（红测试先行）

| 编号 | 缺口 | 计划新增测试类 | 任务 |
|---|---|---|---|
| P0-1A | 查看器缩放无事务边界：动画中捏合被取消、复用/翻页与动画竞态；Core 侧缩放钳制无事务单测 | ViewerZoomTransactionTests（PhotoDeskTests）<br>ZoomTransformTransactionBoundaryTests（PhotoDeskCore/Tests） | T01 |
| P0-1B | 网格捏合逐帧换列无单飞事务；reloadItems 绕过 Diffable 无回归测试 | GridPinchTransactionTests（PhotoDeskTests）<br>GridColumnsPolicyTests（PhotoDeskCore/Tests，若换列事务下沉 Core） | T02 |
| P0-2 | 保存触发矩阵、settled 门禁、verify nil 分支、head 回填补偿均无直接断言；UI 断言宽松（±2pt 未见） | PositionRestoreV6Tests（PhotoDeskCore/Tests）<br>PositionSaveTriggerMatrixTests（PhotoDeskTests）<br>PositionFakeSettledGuardTests（PhotoDeskTests） | T03 |
| P0-3 | 粘性头几何命中、等量替换计数、badge 双标志渲染、scope 全量语义均无测试 | MarqueeStickyHeaderGeometryTests（PhotoDeskCore/Tests）<br>SlideSelectGeometryTests（PhotoDeskTests）<br>SelectionRenderSingleSourceTests（PhotoDeskTests） | T04 |

## §7A X01–X16 缺口（T11A 收口，每条红→绿）

| ID | 缺口（当前源码） | 计划新增测试类 | 现状 | 任务 |
|---|---|---|---|---|
| X01 | BatchCommitCoordinator 批间失败丢 committed、队列不清 | BatchCommitPartialFailureTests（PhotoDeskTests） | 缺失（红） | T11A |
| X02 | PhotoWriter.createAlbum 按 title 重查取第一个同名相簿 | PhotoWriterCreateAlbumTests（PhotoDeskTests） | 缺失（红） | T11A |
| X03 | AssetRepository.isCloudOnly 恒 false，iCloud-only 无法识别 | AssetRepositoryCloudOnlyTests（PhotoDeskTests） | 缺失（红） | T11A |
| X04 | EditorViewController 裁剪遮罩/applyCrop 坐标空间混用 | EditorCropCoordinateTests（PhotoDeskTests） | 缺失（红） | T11A |
| X05 | EditorViewModel.applyAspect 读到已更新 transform，旋转/翻转被重置 | EditorViewModelAspectTests（PhotoDeskTests） | 缺失（红） | T11A |
| X06 | StorageStatsService 缓存回写 O(n²) 卡主线程 | StorageStatsPerfTests（PhotoDeskTests） | 缺失（红） | T11A |
| X07 | TrashBin.storeCopy 主线程同步拷贝大文件 | TrashBinAsyncCopyTests（PhotoDeskTests） | 缺失（红） | T11A |
| X08 | VaultViewModel 隐藏库一次取全部，绕过分批约束 | VaultPagedFetchTests（PhotoDeskTests） | 缺失（红） | T11A |
| X09 | AlbumDetailView.removeFromAlbum 不递减 total，loadMore 空转 | AlbumDetailTotalTests（PhotoDeskTests） | 缺失（红） | T11A |
| X10 | PhotoWriter.renameAlbum 未 trim/空标题校验 | PhotoWriterRenameValidationTests（PhotoDeskTests） | 缺失（红） | T11A |
| X11 | MemoryCache block-based observer token 泄漏 | MemoryCacheObserverTests（PhotoDeskTests） | 缺失（红） | T11A |
| X12 | purgeTrash 清空 TrashBin 不同步 UndoCenter | TrashPurgeUndoTests（PhotoDeskTests） | 缺失（红） | T11A |
| X13 | DiagnosticsExporter 临时文件无生命周期所有者 | DiagnosticsCleanupTests（PhotoDeskTests） | 缺失（红） | T11A |
| X14 | AppLockController.isBiometryAvailable 判定写反、unlockedThisSession 未参与 | AppLockGateTests（PhotoDeskTests） | 缺失（红） | T11A |
| X15 | EditorViewController.revertTapped try? 静默吞错 | EditorRevertErrorTests（PhotoDeskTests） | 缺失（红） | T11A |
| X16 | ExportViewModel/ExportRenderer 导出临时文件不清理 | ExportTempCleanupTests（PhotoDeskTests） | 缺失（红） | T11A |

## 假绿审计（现有断言盲区）

- PhotoGridCell.accessibilityValue 仅 #if DEBUG 写入（选中态 AX 与视觉可能分叉）——T04 必须断言真实图层（badge isHidden + borderWidth），AX 仅作辅助。
- 现有缩放/位置 UI 测试以宽松范围断言，无 ±2pt 精度与 500/200/20 次重复场景——T01–T03 各自补压力维度。
- Core 层 ZoomTransformPolicyTests/ZoomGeometryTransactionTests 存在但未覆盖事务边界（动画中并入/取消路径）——T01 下沉逻辑时补。

## 现有测试规模

| 层 | 类数 | test 函数数 |
|---|---:|---:|
| PhotoDeskCore/Tests | 31 | 405 |
| PhotoDeskTests | 32 | 250 |
| PhotoDeskUITests | 10 | 77 |

