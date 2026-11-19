# M19 执行进度

> 按 `docs/43-M19-任务分段/00-索引.md` 顺序执行；**一次只读一张卡**；每卡先红测试后实现，单独提交，更新本表后才读下一卡。
> 进度表被 `.gitignore` 的 `artifacts/` 覆盖：每次提交用 `git add -f artifacts/plan/progress-m19.md`。
> 状态：TODO / DOING / BLOCKED（等 CI、等真机）/ DONE（门禁通过且已提交）。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T01 | DONE | 58ef379 · 9e45894 · 3d589b5 · 本提交 | audit-m19.ps1 红基线：24 检查（8 PASS / 5 BLOCKING / 6 PRESENT），A/B 三输出 SAME×3；Core Docker 483/483；CI 44564827772 success（左列 passed 37.9s + 探针 skipped actual=4 vs bandTarget=9）；docs/45-M19-审查报告 §0–§7 | 右列下滑不整行根因实锤（命中粒度=cell）；T02 红用例 16 条已备（artifacts/audit/m19/t02-red-test-list.md） |
| T02 | DONE | a70241f · d5fad57 · 本提交 | Docker 503/503（+20 用例）；CI core-linux success（run 44573774067 @ d5fad57；build job 取消记实——App 零改动）；audit baseline-t02 pass 11（present-rowbandmap-swift + band-row-major-core 转绿；B3 scope 命中单元属 T03）；perf 实测 5.1–8.1ms（debug/Docker）→ 绝对回归闸 <20ms | RowBandMap 平铺/钳制/吸附/序列/全行展开 + SlideSelectConfig 两常量 |
| T03 | DONE | 21341e6 · b9a346e · 本提交 | Docker 518/518（+15 用例）；CI core-linux success（run 44575962511 @ b9a346e；build 取消记实）；audit baseline-t03 pass=12（band-scope-core 转绿）；RowBandTrailTests 15 条：正向 3 行 target=9 / 回滑 target=3 / 恢复 9 / 预选路径外与行内 / deselect 滑 2 行移 6 格回滑恢复 / scope 过滤不入栈 / 单帧跨 2 行带 / 性能留痕 | 卡片 RowBandExpander 按 docs/42 §10.1 不新增（RowBandItem 数值单元 + App itemIdentifier 映射）；SlideSelectTrail 净差契约修正（帧起点状态合成） |
| T04 | DONE | 29bb38e · 0f2ac33 · 6768992 · 2db42eb · 本提交 | CI 定向红→绿：语义红 run 44585381551（no member 'rowBandHitTest' ×10）；绿 run 44601577249 @ 2db42ebc 全绿（LibraryGridGeometryTests 23/23 含新增 10 条，Performance 4/4）；lastQueryCount 热帧 ≤ 60；audit baseline-t04 B1+PRESENT symbol 转绿 | 首轮绿单红实锤测试锚点缺陷（拖点 < clipTop 被钳）→ safeAnchorRow 独立口径；hitTestLine deprecated 推迟至 T05（防新增警告） |
| T05 | DONE | 6154e83 · b4fad93 · 本提交 | CI 定向红→绿：红 run 44608129270 @ 6154e83（VC:796 `no member 'trailHitProvider'`；首跑 build job 因 macOS arm64 runner 未获取失败，rerun 取得真红，log 4388 行存 t05/red-compile-failure.log）；绿 run 44615607748 @ b4fad932（LibraryGridGeometryTests 23/23 + Performance 4/4，零新增警告）；audit baseline-t05 pass=17（B2 判据随改名修订：rowBandHitProvider 接 rowBandHitTest + trailHitProvider 全仓清零；余 B6→T06/T08、band-ui-suite→T08） | beginTrail 零长度 (press,press) 整行 consume（provider 不可用退单锚点自愈）；DEBUG band=/exp=（tester.lastBandCount/lastExpandedCount）保留 path=；文案横幅「整行选择中/整行取消中」+首入提示；hitTestLine 生产调用清零，deprecated 标注推迟至 T07 |
| T06 | TODO | — | — | 回滑/取消/预选/全选/单月/跨月 行为矩阵 |
| T07 | TODO | — | — | 边缘自动滚动/粘性头/性能预算 |
| T08 | TODO | — | — | UI 套件重写 + CI 全量绿 |
| T09 | TODO | — | — | 本地提交检查点 + AltServer 真机 12 条 |
| T10 | TODO | — | — | Release 1.8.0 (9) + IPA 绝对路径 + SHA256 |

## 证据目录约定

- 审查：`artifacts/audit/m19/baseline-A|B/`、`determinism.txt`
- Core 红/绿：`artifacts/audit/m19/t02/`、`t03/`
- CI：`artifacts/ci-evidence/m19-t0x/<run-id>/`
- Release：`artifacts/release/1.8.0/`
- 真机：`docs/46-M19-验收记录.md`（BLOCKED 时列出未执行项）
