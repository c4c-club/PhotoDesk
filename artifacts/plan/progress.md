# M16 执行进度

> 每完成一个任务更新本文件；不要用旧 docs/27 的数字代替本轮结果。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T00 基线审查与脚本重写 | DONE | 0c9935c + 453daf0 | audit-m16.ps1 两连跑一致（除时间戳）；红线命中 6 · 违规 0；Core 338/338（Docker 实测）；设备探测 BLOCKED（原样记录） | artifacts/audit/2026-11-12/（audit.md / audit.json / root-cause.md / test-gap.md / core-baseline-20261112.log / device-probe.txt） |
| T01 查看器缩放事务 | DONE | 9d8270b + b254d58 + a42eb3f | Core 366/366（Docker）；CI 定向 run 43279827299 ✅（单测）/ 43268212545 UI 套件 12/12 ✅（含 500 轮捏合）；红线违规 0 | 首轮 run 43268212545 抓出宽限窗口真缺陷（a42eb3f 修复后单测重跑绿）；真机 BLOCKED |
| T02 网格捏合事务 | TODO | — | — | — |
| T03 位置记忆 v6 | TODO | — | — | — |
| T04 滑动多选 | TODO | — | — | — |
| T05 页面 1–2 | TODO | — | — | — |
| T06 页面 3–5 | TODO | — | — | — |
| T07 页面 6–7 | TODO | — | — | — |
| T08 页面 9–12 | TODO | — | — | — |
| T09 页面 13–17 | TODO | — | — | — |
| T10 页面 8、18–20 | TODO | — | — | — |
| T11 页面 21–24 | TODO | — | — | — |
| T11A 扩展缺陷收口 X01–X16 | TODO | — | — | 见 docs/28 §7A |
| T12 全量回归与发布 | TODO | — | — | 需 T11A DONE |

## 当前阻塞

- 真机：待 T00/T12 二次探测；未接入则写 BLOCKED，不得伪造。
