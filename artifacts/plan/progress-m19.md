# M19 执行进度

> 按 `docs/43-M19-任务分段/00-索引.md` 顺序执行；**一次只读一张卡**；每卡先红测试后实现，单独提交，更新本表后才读下一卡。
> 进度表被 `.gitignore` 的 `artifacts/` 覆盖：每次提交用 `git add -f artifacts/plan/progress-m19.md`。
> 状态：TODO / DOING / BLOCKED（等 CI、等真机）/ DONE（门禁通过且已提交）。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T01 | DONE | 58ef379 · 9e45894 · 3d589b5 · 本提交 | audit-m19.ps1 红基线：24 检查（8 PASS / 5 BLOCKING / 6 PRESENT），A/B 三输出 SAME×3；Core Docker 483/483；CI 44564827772 success（左列 passed 37.9s + 探针 skipped actual=4 vs bandTarget=9）；docs/45-M19-审查报告 §0–§7 | 右列下滑不整行根因实锤（命中粒度=cell）；T02 红用例 16 条已备（artifacts/audit/m19/t02-red-test-list.md） |
| T02 | DONE | a70241f · d5fad57 · 本提交 | Docker 503/503（+20 用例）；CI core-linux success（run 44573774067 @ d5fad57；build job 取消记实——App 零改动）；audit baseline-t02 pass 11（present-rowbandmap-swift + band-row-major-core 转绿；B3 scope 命中单元属 T03）；perf 实测 5.1–8.1ms（debug/Docker）→ 绝对回归闸 <20ms | RowBandMap 平铺/钳制/吸附/序列/全行展开 + SlideSelectConfig 两常量 |
| T03 | TODO | — | — | Core 行带展开 + 事务组合 |
| T04 | TODO | — | — | App GridHitTester 行带命中 + 真布局单测 |
| T05 | TODO | — | — | Controller/VC 接线 + 文案 + DEBUG |
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
