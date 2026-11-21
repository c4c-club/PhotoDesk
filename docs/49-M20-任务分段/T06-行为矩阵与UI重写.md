# T06 — 行为矩阵与 UI 重写

> 依赖：T05。状态：⬜。预计：1d。
> 只读：00-索引、本卡；可读现有 RowBandSelectUITests、LibraryGridGeometryTests、RowBandTrailTests、SlideSelectTrailTests 与 T01 基线。不要读 T07–T08。

## 1. 目标

用用户给出的 4 列 5 步矩阵重写旧行带测试，删除横向整行/零长度整行旧契约；补齐选择按钮直拖、左回滑、长按单 cell 的 UI 证据。

## 2. 测试重写清单

### 2.1 PhotoDeskTests/LibraryGridGeometryTests.swift

- 删除或重写：
  - testRowBandHitTestHorizontalDragExactRow
  - testRowBandHitTestZeroLengthReturnsWholeBand
- 新增：
  - testTrailHitZeroLengthReturnsSingleCell
  - testTrailHitHorizontalDragReturnsOrderedCells
  - testTrailHitVerticalDragReturnsFullRows
  - testTrailHitDiagonalHorizontalDominantReturnsCells
  - testTrailHitFourColumnFiveStepMatrix（按段调用，断言每段精确集合）
- 期望集合独立按 frame 计算；禁止调用 trailHitTest 自证。

### 2.2 PhotoDeskCore/Tests/PhotoDeskCoreTests/RowBandTrailTests.swift

- 第一次 consume 改为单 anchor，不再断言整行。
- 行向下序列测试：起始行只补缺失 cell，新行整行追加；trail.path 无重复。
- 行向上 rewind 测试：只回退目的行之后的 id。
- 回滑取消测试：路径尾部 cell 可出栈，已选前两行保持。
- 旧「首帧整行」断言删除，不得保留为兼容分支。

### 2.3 PhotoDeskCore/Tests/PhotoDeskCoreTests/SelectionGestureMachineTests.swift

- 期望 .beginTrail(anchorID:)；已多选直接拖动只有 beginTrail。
- 旧 [.beginTrail] 断言删除。

### 2.4 PhotoDeskUITests/RowBandSelectUITests.swift

- 删除/重写 testHorizontalPressDragSelectsWholeRow：
  - 新测试 testHorizontalPressDragSelectsTrailingCells：从首行第 1 格拖到第 4 格，断言 4 个 cell，不是整行 8+。
- 保留跨月 scope、自动滚动、轻点不吞、长按触觉等回归；如旧测试依赖整行语义，按新语义调整期望。
- 新增 SlideSelectMatrixUITests.swift：
  - testLongPressSelectsOnlyAnchor：长按 (1,1)，count 1。
  - testHorizontalRightDragSelectsFour：从 (1,1) 到 (1,4)，count 4。
  - testVerticalDownSelectsRows：先横向选满第 1 行，再从 (1,4) 下拖到 (2,4)，count 8；继续到 (3,4)，count 12。
  - testLeftDragDeselectsTail：在 12 张基础上从 (3,4) 左拖到 (3,2)，count 10，且第 1、2 行仍选中。
  - testSelectButtonDirectDrag：点 Library-Select 后直接横拖，count 增长且不进入滚动。
- XCUI 限制说明：单次 press-thenDrag 不能合成同一手势多段转向；连续 5 段路径由 Core SlideSelectTrail 单测按有序 id 序列锁定，UI 分段验证 + 真机手动连续验证。不得伪造 XCUI 不支持的 API。

## 3. 测试基准

4 列 fixture：

- 至少 3 行可见；首行 4 个 cell 的 frame 宽度 > 1。
- 选中集合用 cell 的 accessibilityIdentifier / dataSource id 读取，不按索引猜。
- 计数读 Selection-Count，等到精确值；不要只等「大于 0」。
- 失败时输出 hierarchy、count、selected ids、debugTrailPathCount/debugExpandedCount。

## 4. 执行步骤

1. 先运行旧测试，确认旧断言按预期失败（横向整行/零长度整行）。
2. 重写 Core 测试，跑 scripts/test-core.ps1 绿。
3. 重写几何测试，跑 CI app 单测绿。
4. 重写/新增 UI 测试，跑 CI 目标测试绿。
5. 手动连续手势验证（真机或模拟器）：
   - 长按 (1,1) → 右到 (1,4) → 下到 (3,4) → 左到 (3,2)；
   - 计数依次 1 → 4 → 12 → 10；
   - 若无法真机，写 BLOCKED，保留模拟器分段证据。
6. 更新 progress；commit：test(selection): 重写 M20 四列滑选矩阵。

## 5. 验收

- A1–A6 全部有自动化证据；A5 第 1、2 行仍选中。
- 旧横向整行/零长度整行断言不再存在（grep 确认）。
- 选择按钮直接拖动不进入滚动、不吞触摸。
- 跨月 scope、自动滚动、轻点选择回归通过。
- 所有测试失败信息可定位。

## 6. BLOCKED 处理

如果模拟器无法稳定合成 4 列坐标（不同设备宽度导致列数变化），用 launchArguments 固定 4 列并记录设备型号；若仍不稳定，UI 测试可只断言首行 4 格 + Core 精确矩阵，但必须在 progress 标注手动连续验证缺口。

## 7. 下一卡

T07 — 全量门禁与文档。完成并 commit 后才能读。
