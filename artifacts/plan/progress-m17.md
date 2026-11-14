# M17 执行进度

> 按 docs/33-任务分段/00-索引.md 顺序执行；每卡先红测试后实现，单独提交（先 test 后 fix，中文摘要+规定前缀）。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T01 | DONE | cfe46dc (test) + c9d8474 (docs 归档) | audit 红基线归档；CI run 43529901394 三红用例全部失败实锤 | 镜像 makeLayout 引入 1 条既有弃用警告实例，T04 消除 |
| T02 | DONE | 14e651f (test) + f74d184 (feat) + 9d2e607 (refactor) + 7b692b9 (fix) | Docker 435 tests 0 failures；CI core-linux success + 定向 Test SUCCEEDED；shouldActivate/resolvedSelection 归零 | 新增 39 用例 ≥ 25 |
| T03 | DONE | 88b13d1 (test) + 74e3585 (feat) | Docker 459 tests 0 failures；CI core-linux 复验性能用例；run id 见下 | 新增 24 用例 ≥ 20 |

## T01 — 基线复核与红测试（DONE，2026-11-14）

### audit-m17 红基线

- 脚本：`scripts/audit-m17.ps1`（19 项检查，无 -Strict，两次退出码均 0）
- 连跑两次：audit.md / audit.json / stdout 除 `generatedAt` 外逐字节一致（md_identical=json_identical=stdout_identical=True）
- 归档：`artifacts/audit/m17/baseline-2026-11-14/`（audit.md、audit.json、audit-run2.*、run1/run2-stdout.log、run1/run2-stderr.log、三条 CI 红证据文件）
- **9 项 BLOCKING 未达标（红基线）**：A04（无长按进入，0 命中）、A05（双指规则劫持单指滚动，2 处 :802/:832）、A06（无方向锁，0 命中）、A07（无框选可视反馈，0 命中）、A08（scope 未取全量筛选结果，3 处）、A09（每帧 O(n log n) 全量排序替换，1 处）、A10（Feature 层直接引用 PHAsset，13 处）、A14（UI 测试无长按覆盖，0 命中）、A15（每帧遍历全部 section 查询布局，1 处）
- WARN/INFO 未达标（非阻塞）：A01、A02、A13

### 红测试 → CI 失败证据（run 43529901394，workflow_dispatch 定向，conclusion=failure）

| 用例 | 断言 | CI 失败实况 | 对应根因 |
|---|---|---|---|
| testLongPressEntersSelection | 长按首格 0.4s → Selection-Count == 1 | `XCTAssertEqual failed: ("-1") is not equal to ("1")…count=-1`（MarqueeSelectionUITests.swift:367） | G13/G16（A04/A14） |
| testSingleFingerScrollInSelectionMode | 多选下单指上滑 offset 增量 > 200 | `XCTAssertGreaterThan failed: ("0.0") is not greater than ("200.0")…start=-44.0 end=-44.0`（:392） | G1（A05） |
| testPinnedHeaderAttributeIsPinned | offset=5000 可视段头 supplementary minY == 首格 minY − 48 | `XCTAssertEqualWithAccuracy failed: ("902.0") is not equal to ("0.0") +/- ("0.5")`（LibraryGridGeometryTests.swift:101） | G8/H1（A02） |

- **H1 判定：实锤**。探针附件（evidence-h1-sticky-header-diff902.txt）：`offset=5000.0 section=3 headerMinY=5000.0 item0MinY=4146.0 expectedMinY=4098.0 diff=902.0 pinned=true` —— supplementary attributes 被 pinToVisibleBounds 平移到视口顶（=contentOffset.y），偏差 902pt。
- 失败截图：run 工件 `failure-screenshot`（failure-sim-state.png）+ `ui-test-attachments`（含 m17-single-finger-scroll 探针、长按失败现场 D8D3D325/5945A8E0 截图）；本机副本 `artifacts/ci-evidence/m17-t01/`（不入库）
- run 链接：https://github.com/c4c-club/PhotoDesk/actions/runs/43529901394
- 门禁通过口径：产品代码零改动（`git diff --stat` 仅测试与 artifacts）；三红用例为 CI 真实失败证据，非本地未编译。

### 遗留说明

- 测试文件镜像 `makeLayout` 的 `NSCollectionLayoutGroup.horizontal(layoutSize:subitem:count:)`（CI 实证 LibraryViewController:1735、VaultGridView:54 早已存在同类弃用警告），T04 真几何改造时一并切换非弃用 API。

## T02 — Core 手势状态机（DONE，2026-11-14）

### 交付物

- `PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift`：SelectionGestureState（idle/pressing/armed/dragging/autoScrolling/ending）+ SelectionGestureEvent（六事件 + edgeEntered(direction:)/edgeExited——状态表第 7/8 行「指尖进/离边缘」的事件载体）+ SelectionGestureConfig（0.28/8/8/1.2/6/0.06）+ handle(event:now:) → [SelectionGestureEffect]；仅 `import Foundation`。
- 效果契约：holdElapsed → [haptic(.impactLight), enterSelection(anchorID), beginMarquee]；pressing 横向锁定 → dragging（未在多选先 enterSelection，isSelectionModeActive 由 App 注入）；纵向占优 → idle + releaseScroll；armed 纵向拖不拖框、scrollStarted 回 idle；dragging moved → updateMarquee + haptic(.selectionChanged)（hapticMinInterval 节流，App 侧以命中集合变化为最终闸门）；边缘进出 start/stop 严格配对；ended/cancelled 带资源收尾入 .ending、下一事件复位 idle；非有限 dx/dy/now/触点安全直回 idle。
- 删除死代码（docs/31 X10）：SlideSelectPolicy.shouldActivate / resolvedSelection / deduplicated / SlideSelectActivation / SlideSelectConfig.directionLockEpsilon 及 9 条对应测试；SlideSelectCell 保留（MarqueeSelectionPolicy 在用）；edgeVelocity / clampedOffset / 其余 config 常量保留（App 控制器在用，T05 换装）。

### 门禁证据

- 红：14e651f 落地前 Docker 编译失败实录 `artifacts/audit/m17/t02/red-compile-failure.log`（cannot find 'SelectionGestureMachine'/'SelectionGestureConfig' in scope）
- 绿：Docker swift:6.0-noble `scripts/test-core.ps1` —— feat 后 444 tests 0 failures；refactor 后 **435 tests 0 failures**（405 基线 + 39 新增 − 9 删除）
- 验收：shouldActivate / resolvedSelection 在跟踪源码命中 0；机器文件仅 import Foundation；新增用例 39 ≥ 25
- CI：core-linux（swift:6.0-noble）同一条命令复验 **success**；定向 run 43534301697 抓到 Darwin 真实差异——Foundation 导入的 CGPoint 不满足 Equatable 合成（Docker Linux 有 Equatable 故本地全绿）→ fix 7b692b9 改用 Core 自有 GridPoint（红线 2 合规）→ 复跑 43535685266：定向 Test 步骤 **TEST SUCCEEDED**（LibraryViewModelTests 14/14，App 与新 Core 编译兼容实证）。该 run 整体 failure 仅因最后无条件 Performance 步骤的基建抖动「Test runner never began executing tests after launching」（非断言失败，与 Core 改动无关；T09 全量回归复盖）。push 全量 run 已按 concurrency 组取消省额度
- 本地证据目录（不入库）：`artifacts/audit/m17/t02/`、`artifacts/ci-evidence/m17-t01/`

## T03 — Core 命中解析（DONE，2026-11-14）

### 交付物

- `PhotoDeskCore/Sources/PhotoDeskCore/MarqueeHitResolver.swift`：CellFrame（id + Double 四边）/ HitRect（anchor+current 自动归一 + 四边各扩 1pt）/ `hit(rect:cells:clipTop:) -> Set<String>`；闭区间相交（贴边即命中）、clipTop 抬矩形上边裁粘性头遮挡（抬后为空返回空集）、非有限矩形空集、非有限/退化 frame 逐个跳过、cells 乱序与同 id 重复安全；仅 import Foundation。
- `MarqueeSelectionPolicy.swift` 顶部加 deprecated 说明注释（基于 M15 估算几何，T04 迁移后整类删除；本任务不删，避免一次改太多）。
- 用例 24 条：空 / 单点 / 1pt 扩展 / 部分相交 / 包含 / 被包含 / 贴边 / 跨段 / 乱序 / 同 id 折叠与任一帧命中 / 反向拖归一 / HitRect 值语义 / NaN / ∞ / 非有限与退化 frame / clipTop 半裁 / 全裁 / 低于上边不生效 / 抬后为空 / 2 万 frame < 20ms。

### 门禁证据

- 红：88b13d1 落地前 Docker 编译失败实录 `artifacts/audit/m17/t03-red-compile-failure.log`（cannot find CellFrame/HitRect/MarqueeHitResolver）
- 绿：Docker swift:6.0-noble **459 tests 0 failures**（435 基线 + 24 新增）；过程修正 1 条测试自身矩形宽度错误（随 feat 提交，非实现缺陷）
- 验收：新增 24 ≥ 20；不引入 UIKit/CoreGraphics；性能用例由 CI core-linux 容器同一条 swift test 复验（run 43540179936 **success**：core-linux success + build success + 定向 Test SUCCEEDED + Performance 4/4 通过——上轮 T02 的 perf 步骤失败确证为 runner 基建抖动）
- 本地证据（不入库）：`artifacts/audit/m17/t03-green-test-summary.txt`

## T04 — 网格真实几何与命中（DONE，2026-11-14）

### 交付物

- `PhotoDesk/Features/Library/LibraryGridLayout.swift`：`enum LibraryGridLayout.make(columns:)`——自 VC `makeLayout` 原样搬出（行为零变化），VC 4 处调用点改指工厂。
- `PhotoDesk/Features/Library/GridHitTester.swift`：框选命中测试器（docs/32 §2.4 1–8 步）——段范围缓存自 item(0)/item(count−1) attributes（不读 supplementary → 粘性头污染免疫）；列数由首行 attributes 探测；真实行高 = 次行.minY − 首行.minY；二分找候选段 + 只枚举相交行 + 每行 ≤ columns 次查询；矩形上边钳到视口顶 + 48（G11：被钉住头遮住/滚出屏的 cell 不命中）；`invalidateGeometry()` 由 VC viewDidLayoutSubviews 统一失效（snapshot/列数/旋转最终都汇入布局 pass）；DEBUG `lastQueryCount`。
- `SlideSelectGestureController`：契约 `geometryProvider` → `hitTestProvider: (CGRect) -> Set<String>`（零尺寸矩形扩 1pt 保留在控制器）；id 映射移至 VC（`dataSource.itemIdentifier(for:)`）；anchor 仍走 itemIDProvider。
- `LibraryViewController`：删 `marqueeGeometry()`（34 行参数推算）；`layoutAttributesForSupplementaryView` 仅剩位置记忆/月跳两处（命中路径 0）。
- Core：`MarqueeSelectionPolicy` 只剩 `mode/resolved`（删 GridMetrics/MarqueeRect/cells，A09 随之根治）；`SlideSelectPolicy` 删 SlideSelectCell；Core 用例删 17 条参数推算几何用例（459 → 442）。
- `PhotoDeskTests/LibraryGridGeometryTests`：T01 镜像布局删除（改用生产工厂，弃用 API 警告随之消除）；H1 断言由「不应被 pin 污染」（不可能成立）改写为 H1 实锤行为锁（被钉住段 supplementary minY == 视口顶、diff≈902pt）；新增暴力求交一致性（2/3/4/5 列 × offset {0,2000,8000,20000}）、H3 宽度公式、a3-7 回归锁、lastQueryCount ≤ 60 四用例。

### 门禁证据

- 红：83b8ad8 CI run 43544489881 **failure**（build: Cannot find 'LibraryGridLayout'/'GridHitTester' in scope，实录 `artifacts/audit/m17/t04-red-compile-failure.log`）
- 中途红（真数据暴露的测试缺陷，实现未改）：run 43546275550 3 败（XCTUnwrap nil ×2 + H1 旧断言）→ 8737c4b；run 43548175125 2 败（首趟布局缺失）→ 27f4edb；run 43549332935 2 败（**UICollectionView.dataSource 弱引用**——解构丢弃导致 0 段空网格，此前暴力求交/lastQueryCount 两轮为空对空假绿）→ ade613e
- 绿：run 43550824419 **success**——core-linux 442 tests 0 failures；定向 LibraryGridGeometryTests **5/5**（真数据）；Performance 4/4；Docker 本地同绿 `artifacts/audit/m17/t04-green-test-summary.txt`
- 验收 grep：`marqueeGeometry` PhotoDesk 0 处；`layoutAttributesForSupplementaryView` VC 仅剩 2 处（位置记忆/月跳，命中路径外）；H1/H3 实测结论已写入测试注释（H1 成立 diff=902 → tester 全走 item attributes；H3 成立 宽=(W−s(c−1))/c）
- 警告：T01 镜像弃用 API 警告随镜像删除而消除（净 −1，无新增）
