# M15 根因报告（2026-11-09，全新审查）

> 方法：只读生产源码 + 解析 25 份 `.ips` + grep 实证；不采用 docs/21/22/24 结论。
> 证据等级：E1 = 源码/崩溃栈实锤；行号为基线 `430cc59` 时的实际位置。

## 1. P0-1 捏合缩小/放大必崩溃

### 1.1 崩溃栈（E1，25 份 .ips 全量统计）

来源：`.m13-notes/crash5/DiagnosticReports/`（app_version 1.3.0 (4)，全部 25 份）。

| 签名 | 命中 |
|---|---|
| `EXC_BAD_ACCESS` (SIGSEGV，KERN_PROTECTION_FAILURE) | 25/25 |
| `_zoomScaleFromPresentationLayer` | 25/25 |
| `_getDelegateZoomView` | 25/25 |
| `DefaultStringInterpolation.appendInterpolation` → `swift_dynamicCast` | 25/25 |
| `viewForZooming(in:)` 显式入栈 | 16/25（其余为截断栈，同簇） |

典型栈（PhotoDesk-2026-11-07-070051.ips）：

```
libswiftCore: swift_conformsToProtocolMaybeInstantiateSuperclasses → … → swift_dynamicCast
libswiftCore: DefaultStringInterpolation.appendInterpolation<A>(_:)
PhotoDesk.debug.dylib: ZoomableImageCell.viewForZooming(in:)
UIKitCore: -[UIScrollView _getDelegateZoomView]
UIKitCore: -[UIScrollView _zoomScaleFromPresentationLayer:]
PhotoDesk.debug.dylib: ZoomableImageCell.viewForZooming(in:)   ← 重入
```

结论：崩溃不是"某行写错"，而是**缩放状态所有权在 UIScrollView**：`viewForZooming` 被
`_zoomScaleFromPresentationLayer` 递归调用，任何一次 delegate 查询路径上的字符串插值/
dynamicCast 都可能再次触发 `_getDelegateZoomView` → 栈溢出。1.4.0 只移除了方法体里的
插值（ZoomableImageCell.swift:433-435 现在只有 `return zoomContentView`），但同一
reentrancy 窗口仍在：

| 现状位置（430cc59） | 缺陷 |
|---|---|
| `ZoomableImageCell.swift:441-448` `scrollViewDidZoom` 每帧读 `scrollView.zoomScale` | 该 getter 正是 `_zoomScaleFromPresentationLayer` 入口，每帧重新进入 `_getDelegateZoomView` |
| `ZoomableImageCell.swift:344-370` `layoutImageContent` 在 `layoutSubviews` 写 `zoomContentView.frame` / `scrollView.contentSize`（:363-364）并读 `zoomScale`（:352） | 回弹动画期 `isZooming==false`，写入与 UIScrollView transform 事务打架 |
| `ZoomableImageCell.swift:373-390` `centerZoomContent` 在 `scrollViewDidEndZooming` 写 `contentInset`（:387） | 结束回调内再触发布局/滚动回调，重入窗口 |
| `ZoomableImageCell.swift:189-211 / 252-280` `prepareForReuse`/`configure` 摘 delegate 再 `setZoomScale` | 复用时缩放动画未结束 → UIScrollView 内部状态不一致 |
| `ViewerViewController.swift:514-550` 缩放 idle 回调 + 待删除队列 drain | 删除事务与缩放事务共享同一 cell，几何写入可能与 `performBatchUpdates` 同帧 |

### 1.2 修复方向

移除 UIScrollView 缩放（自管变换）：`ZoomTransformPolicy`（Core 纯几何）+
`ZoomInteractionController`（UIKit 手势状态机）；`ZoomableImageCell` 重写；
`viewForZooming` / `UIScrollViewDelegate` / `setZoomScale` / `contentInset` /
`zoomContentView` 在 `PhotoDesk/Features/Viewer` 必须仓库级 0 命中。

## 2. P0-2 上次位置记不准（概率事件）

E1 缺陷清单（行号为 430cc59 实测）：

| # | 缺陷 | 位置 |
|---|---|---|
| 1 | 位置写 `UserDefaults`（`defaults.set(data, forKey:)`，非原子文件） | `PhotoDesk/Core/Support/LibraryPositionStore.swift:127-135` |
| 2 | 无"本次启动恢复完成"保存门禁；`state.isInFlight` 之外任何保存都能写 | `LibraryPositionCoordinator.swift:65-83`、`LibraryViewController.swift:1662-1676` |
| 3 | `beginRestore` 每 queryKey 只执行一次，恢复失败不再重试 | `LibraryPositionCoordinator.swift:139-154` |
| 4 | 状态机硬编码 `maxAttempts = 3`、`timeout = 3` 秒 | `PhotoDeskCore/.../PositionRestoreStateMachine.swift:27-31` |
| 5 | `verify` 用刚写入的 minY 反算 visualY（自证循环） | `LibraryPositionCoordinator.swift:219-247` |
| 6 | 前插补偿最多 3 个 layout pass | `LibraryViewController.swift:1416-1444` |
| 7 | `viewWillDisappear` 无条件保存（打开查看器/弹 sheet 也写） | `LibraryViewController.swift:198-202` |
| 8 | `fetchFirstBatch` 找不到锚点静默回退最新 500 | `LibraryViewModel.swift:309-322` |

修复方向：v5 = 原子文件存储（Application Support/LibraryPosition/anchors-v5.json）+
单一 `PositionRestoreMachine`（无 3s 超时；`canSave` 只在 settled）+ 保存触发源收敛
（见 docs/25 §5.6）。

## 3. P0-3/P0-4 滑动多选（整行带 + 只加不减）

E1 证据：

| 位置 | 现状 |
|---|---|
| `PhotoDeskCore/Sources/PhotoDeskCore/SlideSelectRangePolicy.swift:48-81` | `cells(anchor:current:)` 按行带展开整行所有列（用户报"左侧下滑会选中整行"即此处） |
| `PhotoDesk/Features/Library/SlideSelectGestureController.swift:128-131` | `target = baseIDs` 后只 `target.insert(id)`，从不 remove → 无法滑动取消 |
| `PhotoDesk/Features/Library/SlideSelectGestureController.swift:103-108` | 激活帧无条件把 anchor 插入 → 已选格起拖也进"加选" |
| `PhotoDesk/Features/Library/LibraryViewController.swift:742` | 提示文案「单指按住滑动可整行连续选择；双指滚动」固化错误语义 |
| `PhotoDeskCore/Tests/PhotoDeskCoreTests/SlideSelectRangePolicyTests.swift`（7 条） | 全部锁定整行带语义 |

修复方向：矩形框选（marquee）：矩形与 cell 相交即命中；起手已选 → deselect 模式；
回拖自然收缩。删除 `SlideSelectRangePolicy` 全部代码与测试。

## 4. 必须删除/重写的旧测试清单

| 文件 | 处置 |
|---|---|
| `PhotoDeskCore/Tests/PhotoDeskCoreTests/SlideSelectRangePolicyTests.swift`（7 条整行带） | 删除 |
| `PhotoDeskUITests/StabilityUITests.swift:961` `testVerticalSlideSelectSelectsLeftColumns` | 重写为矩形语义（断言只选左列） |
| `StabilityUITests.swift:997` `testSlideSelectDragBackRestores` | 重写为矩形回拖收缩 |
| `StabilityUITests.swift:886` `testDragBackRemovesPreviouslySelected` | 重写为 deselect 语义 |
| `StabilityUITests.swift:905` `testDragBackRestoresOriginal` | 重写为 deselect 语义 |
| `StabilityUITests.swift:449` `testPinchHitsInnerScrollView` | 保留名字，断言改为 viewport 存在 + 100 轮存活 |
| `PhotoDeskTests/LibraryPositionRestoreTests.swift` 中 schemaVersion==4 断言 | 更新为 5 |
| `StabilityUITests.swift:1150` `testPositionRestoredAfterRelaunch` | "≤1 行"容差废止，改 ±2pt |
| 任何 `vfz` / `viewForZooming` / `contentSize` 追踪断言（`ViewerViewController.swift:265` trace） | 删除 |

## 5. 页面级新发现（详见 docs/25 §2.5）

工具页 navigationViewStyle 挂错层级、相簿列表无封面、相簿详情一次性 limit:total、
导出无取消、已隐藏按钮文案与行为不符、设置关于缺 Build/许可、缓存页只有静态上限、
外观页 UserDefaults 文案、PhotoGridCell.prepareForReuse 不复位选中态（:139-145）。
