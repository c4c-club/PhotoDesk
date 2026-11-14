# M17 执行进度

> 按 docs/33-任务分段/00-索引.md 顺序执行；每卡先红测试后实现，单独提交（先 test 后 fix，中文摘要+规定前缀）。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T01 | DONE | cfe46dc (test) + c9d8474 (docs 归档) | audit 红基线归档；CI run 43529901394 三红用例全部失败实锤 | 镜像 makeLayout 引入 1 条既有弃用警告实例，T04 消除 |
| T02 | DONE | 14e651f (test) + f74d184 (feat) + 9d2e607 (refactor) + 7b692b9 (fix) | Docker 435 tests 0 failures；CI core-linux success + 定向 Test SUCCEEDED；shouldActivate/resolvedSelection 归零 | 新增 39 用例 ≥ 25 |
| T03 | DONE | 88b13d1 (test) + 74e3585 (feat) | Docker 459 tests 0 failures；CI core-linux 复验性能用例；run id 见下 | 新增 24 用例 ≥ 20 |
| T05 | DONE | c7cd2e7 (test) + b42b9bb (fix) + a29fcd2 (test) + 4cff229 (feat) + 9c9cd9d (refactor) + a92b594/0c949ca/f9e6d11 (fix) + eb3cb13 (fix) | CI run 43569488790 绿：core 442/0 + MarqueeSelectionUITests 10/10 + Performance 4/4；A05==0 | holdElapsed 定时器交付 + 逐帧边缘监视两处接线缺陷根治 |
| T06 | DONE | 7ad3830 (test) + 57461fd (feat) + 3282246/f39cba9 (fix) + d707089/21b2f6c/ecce878/3dac53b/46b2afc (fix) + 6e53ac7 (fix) + b1549b0/93d5ae0/76426f7/9585327/cc65b08/4599649/8fb5552/8c33727 (fix) + 728f460/409d71b/9057e40/bd7b53b (fix) | CI run 43617711164 绿：core 442/0 + MarqueeSelectionUITests 12/12 + Performance；A07 命中 10 | 角标/压暗/边框单一入口 + 覆盖层坐标补父系偏移（真 bug）+ 精确描边色像素取证 |

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

## T05 — 长按与滚动共存接线（DONE，2026-11-14）

### 交付物

- `PhotoDesk/Features/Library/LibrarySelectionController.swift`（新建）：三识别器组装（TouchDownObserver minimumPressDuration=0 / 长按 0.28s+allowableMovement 取自 SelectionGestureConfig / marqueePan 单指；均 cancelsTouchesInView=false + delegate=self）；机器事件映射与效果执行——enterSelection→VC enterSelectionMode、beginMarquee/endMarquee 与 isScrollEnabled 成对、releaseScroll→marqueePan.state=.failed、G6 触觉以命中集合变化（pendingSelectionHaptic）为最终闸门；processFinger（按下点→指尖矩形、零尺寸扩 1pt、MarqueeSelectionPolicy.resolved）；autoScrollTick 用 SlideSelectPolicy.edgeVelocity + clampedOffset；DEBUG 取证（ticks/edge/vy/vB/state + lastMarqueeRect）。
- **holdElapsed 双通道交付**（接线缺陷根治①）：UILongPress 识别器 + 按下定时器（触点仍在屏时按同一 config 时长补发；机器 state==.pressing + 位移资格守卫保证幂等、语义与 Core 单测一致）——CI 合成触控按压相位识别器偶发不触发，纯识别器交付不可靠。
- **逐帧边缘监视**（接线缺陷根治②）：dragging/autoScrolling 期间 CADisplayLink 每帧 feedEdgeEvents——指尖停在边缘区不动（无 .changed 事件）也能进入 autoScrolling，落实 docs/32 §2.4「停边缘持续滚动」。
- `LibraryViewController`：slideSelectController→selectionController 接线块整体替换；enter/exitSelectionMode 删 `minimumNumberOfTouches = 2`（A05 根治）；didSelectItemAt 加 isConsumingTouch 闸门（touch-up 后 0.3s 内防重 toggle）；scrollViewWillBeginDragging 转发 handleScrollStarted；手势代理扩展重写（shouldBegin=命中 cell 才起步；simultaneous 与 pinch=false 其余 true）；提示文案改「长按照片可框选；从已选照片起拖可取消；单指滑动仍可滚动」。
- 删除 `SlideSelectGestureController.swift`（双指滚动规则载体）；`SlideSelectConfig` 退役 activationThreshold（保留 edgeBuffer/minStep/maxStep）。
- `PhotoDeskUITests/MarqueeSelectionUITests.swift` 重写 10 用例（全部精确 assetID/计数断言）：长按进入、长按拖框（col-0 行 0-4 五格精确）、多选单指上滑 delta>200 且计数不变、底缘拖 2s 自动滚动选入屏外（屏外 id 精确）、横向按压拖行（行 1 三格）、已选锚点拖动取消→0、二次手势收缩 5→3、斜向矩形 8 格、全选后框选取消、轻点不吞。`-uiTestingLongPressMovement` 旗标放宽 allowableMovement 8→40（仅 UI 测试；Core 单测仍钉 8pt 语义）。

### 门禁证据

- 红（Core）：c7cd2e7 Docker 红 `artifacts/audit/m17/t05-core-red-armed.log`（armed 纵向拖 effects [] ≠ [updateMarquee] 且 state armed ≠ dragging）→ b42b9bb 修复 → Docker **442 tests 0 failures** 多轮复验。
- 红（UI）：T01 CI 红基线 run 43529901394（长按 count=-1≠1、单指 delta=0<200）为新模型用例红实锤；b42b9bb 红派发 run 43555054479 被后续绿候选按 concurrency 取消（备查）。
- 中途红（每步真实 CI，修复链）：run 43555732806 1 败（长按未触发→-1）→ a92b594/248bd6c；run 43558341702 2 败（-1 + 斜向计数 0=让位后橡皮筋回弹 off=-203，失败截图取证）→ 0c949ca；run 43561215730 2 败（-1×2 + autoscroll 停 5）→ f9e6d11（根治）；run 43563993911 1 败（autoscroll 停 5）→ 29751f0 取证 + dy 0.99；run 43565902177 / 43566649597 编译错（DEBUG 横幅 + 链 Swift type-check 超时）→ 5c79472/eb3cb13；run 43567326854（runner 基建抖动 Test runner never began，与代码无关）。
- 绿：run 43569488790 **success**（eb3cb13）——core-linux 442/0；MarqueeSelectionUITests **10/10**（214s）；Performance 4/4；TEST SUCCEEDED。
- 验收 grep：`minimumNumberOfTouches = 2` PhotoDesk/PhotoDeskCore/PhotoDeskUITests 0 处（A05 PASS，audit-m17 重定向后复跑：A04/A05/A06/A14/A15/A16/A17 PASS；A07/A08/A09/A10/A13 为 T01 基线债，T06/T07/T08 范围）。
- 教训：审计脚本引用被重构删除的文件必须同步重指向（A04/A06/A15/A16/A17/A19 已改指新控制器/Core 机器/GridLayout）；PowerShell 5.1 读无 BOM UTF-8 中文 .ps1 解析崩坏（编辑工具回写丢 BOM，需补写）；DEBUG 横幅字符串长 + 链触发 type-check 超时（改插值模板）；XCUI press-then-drag 按压相位不可依赖识别器——事件交付要有确定性兜底且保持机器语义不变。

## T06 — 框选可视反馈与角标动画（DONE，2026-11-14）

### 交付物

- `PhotoGridCell.applySelection(isSelecting:isSelected:animated:)` 单一入口：角标 spring（0.6→1.0 / 0.18s / damping 0.7）、12% 黑压暗（dimView 新增，黑底 alpha 0、userInteraction 关、位于 imageView 上 cloudBadge 下）、2pt tint 边框、复用全复位（layer.removeAllAnimations + 非动画归零）；setSelected/setSelectionVisible 改为转发，AX 语义不回归；DEBUG 下 selected 状态进 AX 标签。
- `MarqueeOverlayView.swift`（新建）：单层 CALayer、cornerRadius 12、borderWidth 1.5；applyColors(deselect:)——select = tint 10% 填充/tint 描边，deselect = danger 8%/danger 描边；`update(rect:)` 每帧只改 frame 不重建（G7 预算）；isUserInteractionEnabled=false、isAccessibilityElement=false、accessibilityElementsHidden=true、identifier="Marquee-Overlay"；traitCollectionDidChange 显式刷新动态色。
- `Colors.swift`：新增 `danger` token（light 0xE53935 / dark 0xFF5252，与 accentDelete 同值）。
- `LibrarySelectionController`：`weak var overlayView` + `overlayFrame(for:)` 内容坐标→view 坐标转换（减 contentOffset 加 collectionView.frame.origin——初版漏加 frame.origin 为本卡唯一实现真 bug）；beginMarquee→setDeselectMode(mode==.deselect)+update、updateMarquee→update、endMarquee/finishSelection→update(nil)；DEBUG hapticCount（impactLight 与 selectionChanged 实发计数）；取证字段 debugArmModeRaw / debugTouchDownBaseCount / debugTouchDownHitID。
- `LibraryViewController`：overlay `insertSubview(aboveSubview: collectionView)`；多选栏新增「选择中/取消选择中」模式提示（Selection-Mode-Hint）；DEBUG 横幅扩展 hap=/ov=/ovm=/arm=/ovc=/ovf=/td=（触觉计数/覆盖层显隐/框选模式/armed 时刻模式/描边色/覆盖层 frame/按下帧基集合与命中 id），updateSelectionCount 强制刷新横幅（拖拽中计数变化即可读实时状态）。
- 测试：PhotoGridCellTests 新增 5 用例（applySelection 四态 + 非动画无 transform + 复用复位）；MarqueeSelectionUITests 新增 2 用例——testMarqueeOverlayVisible（拖拽期间连拍帧内 tint 精确色匹配 ≥25 且蓝压红）、testDeselectModeShowsDangerTint（点选 8/11 后同行对角拖 8→10，条带内 danger 精确色匹配 ≥500）。

### 门禁证据

- 红：7ad3830 CI run 43571885161 **failure**（`has no member 'applySelection'` + `'selectionBadge' is inaccessible due to 'private'`）。
- 中途红（修复链，每步真实 CI）：
  - run 43572750309 2 败（autoscroll count=0 + 取消模式红=0）→ **3282246 观察器免位移失败**：touchDownObserver（minPressDuration=0）allowableMovement 默认 10pt，按压相位微漂移 >10pt 使其 .failed → feedEnd(.cancelled) 复位机器并作废 holdElapsed 定时器，稍后到达的长按因 state≠pressing 被幂等丢弃（观察器身份不应有位移预算；机器自身 8pt 位移闸门语义不变）。此后 autoscroll 稳定。
  - run 43576281877 → 43580586245：横幅取证链（ovm/arm/ovc）证明 App 侧完全正确（arm=1、ovc=229,57,53 danger、ov=1、state=dragging、hap=2）而像素扫描红=0 → **6e53ac7 覆盖层坐标补父系偏移（真 bug）**：overlayFrame 漏加 collectionView.frame.origin，覆盖层整体画高约 250pt；此前 overlay 用例的「通过」实为错位矩形下边缘恰好扫进扫描带的假阳性。
  - 像素取证设计迭代（b1549b0→8c33727）：主通道占优判定对种子图块失效（图块含 danger 色系红块 218k 像素、黄格 r 主导）→ 改**精确描边色匹配**（danger(229,57,53)/tint(0,122,255) 容差 25，底色免疫）；跨行条带兜住拖拽弧线俯冲；两阶段对照因阶段 A 偶发未武装滚动污染 boundBy 索引（off=1157 实证）而拆回单阶段。
  - 拖拽几何迭代（728f460→9057e40）：纵向拖 8→16 的 XCUI 弧线俯冲穿越底缘区 → 意外自动滚动（ticks=106、off=1157）网格滚走 → 同行横向拖 8→7 矩形高度 0 → 定格 **对角拖 8→10**（109×98，弧线俯冲 ~669 < 边缘区 703，矩形覆盖已选 8/11）。
  - run 43609923238 / 43612592851：取消模式用例已绿，仅无条件 Performance 步骤连吃「Test runner never began executing tests」基建抖动（非断言失败）；run 43615476302 Test 步 11/12（testLongPressEntersSelection count=-1 同类合成触控闪变）→ **bd7b53b** 为其加有界重试（重新 launch 复位，断言不放宽，同 T05 先例）。
- 绿：run 43617711164 **success**（bd7b53b）——core-linux 442/0；MarqueeSelectionUITests **12/12**（300s）；Performance 全过；TEST SUCCEEDED。
- 验收：角标 0.2s 内可见（spring 0.18s）；dim alpha 0.12 ∈ [0.1,0.15]；取消模式 overlay 像素判别（danger 精确色 ≥500）；触觉 ≤16 次/秒（DEBUG hapticCount 经横幅 hap= 暴露，autoscroll 用例窗口 delta ≤ 64 断言）；无新增截图回归（既有 snap 快照口径不变）。
- audit-m17：A07 命中 10（MarqueeOverlayView 落地）PASS；剩余 BLOCKING A08/A09/A10 为 T07/T08 范围。

### 教训

- 兄弟视图坐标转换必须带父系偏移：content → view = −contentOffset + collectionView.frame.origin；漏加即整体错位且「假阳性通过」可能长期潜伏（像素扫描带恰好扫过错位框边缘）。
- 观察器身份的 UILongPressGestureRecognizer（minPressDuration=0）位移预算必须放开——其 .failed 会以 cancelled 语义复位机器，把定时器兜底通道一起打死。
- XCUIScreen.screenshot 可后台连拍抓拖拽中途画面，但 pngData() 可返回 nil（隐式强解包即测试进程崩溃）——必须 guard。
- XCUI press-then-drag 路径带弧线且俯冲过冲：纵向拖穿越底缘区会触发意外自动滚动、网格滚走后 boundBy 索引指向别格——像素取证测试必须单阶段一次启动内完成，且拖拽几何避开边缘区。
- 像素判别不能依赖通道占优启发式（种子图块颜色不受控）：以「描边不透明纯色」做精确色匹配，或选底色安全的扫描列。
- 把 App 内部状态（armed 时刻模式/描边色/覆盖层 frame/按下帧命中）经 DEBUG 横幅暴露并在计数变化时强制刷新，是定位「App 正确但测试看不到」类分歧的关键手段。
