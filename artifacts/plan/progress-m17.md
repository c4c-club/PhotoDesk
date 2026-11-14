# M17 执行进度

> 按 docs/33-任务分段/00-索引.md 顺序执行；每卡先红测试后实现，单独提交（先 test 后 fix，中文摘要+规定前缀）。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T01 | DONE | cfe46dc (test) + 本提交 (docs 归档) | audit 红基线归档；CI run 43529901394 三红用例全部失败实锤 | 镜像 makeLayout 引入 1 条既有弃用警告实例，T04 消除 |
| T02 | TODO | — | — | — |

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
