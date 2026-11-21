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
| T06 | DONE | 513f294 · 482d914 · 本提交 | Core Docker 524/524（+6 边界用例；daemon 冷启动后复跑 exit=0）；CI run 44634767425 @482d914 success：定向 3 条 M19 UI 用例 passed（51.4/46.0/60.4s，Executed 3 tests 0 failures）+ Performance 4/4；旧 5 条冲突用例（②③④⑤⑥）不在定向范围，仍属 B6 留 T08 重写 | 行为矩阵 6+3 用例首跑即绿：卡片括注「当前实现必然失败」写于 T05 接线前已过时，红基线由 T02/T03/T04/T05 真红承担，本卡为语义锁定；fix(selection) 节点无失败未触发 |
| T07 | DONE | 2077cce · b2bbb61 · ac809c8 · 63823ce · d80dc43 · 本提交 | CI：run C 44644633379（geometry 23/23 + Performance 4/4 + T07-② 真红 count=0）→ run D 44648526747 / run E 44764473663 修复链（静止等待 / 锚点避让钉住头）→ run F 44770333450 @d80dc43 **全绿**（T07 UI 2/2 + Performance 4/4）；Docker 525/525（RowBandPerfTests：parse+expand p50=0.016/p95=0.026ms，applyDelta p50=2.103/p95=3.208ms，低于 §5 预算 2ms/4ms）；perf.txt 归档 audit/m19/t07；audit baseline-t07 pass=17（B6+band-ui-suite 留 T08） | 真红两轮根因均为测试脚手架（①惯性未静止 ②锚点半遮格中心落钉住头遮挡区），生产行为无缺陷（autoScrollTick 同窗换算/clampedOffset/离开边缘停 link、clipTop 钳首可见行——审读已合规未改）；GridHitTester 单帧耗时环形采样 512 帧 + VC DEBUG perf= 字段（真机 T09 采集）；FPS/内存模拟器口径注明 |
| T08 | DONE | e50e624 · 1557b31 · 9d469ab · 4399f19 · ffc55f9 · 40e618c · 57f58a5 · 6b449a8 · 5664c4f · 本提交 | 全量八轮修复链：44783255716（3F）→44805219332（2F）→44827223992（2F）→44844924180（5F，3 例 runner 抖动）→44858932161（2F，跨月 7≠4 跳行）→44871405304（2F，头下首行阈值根因）→44882259960（2F，精调不收敛）→**44894248346（77 tests 1 failure + Performance 4/4）**；RowBandSelectUITests 19/19 全绿（跨月 46.4s）；audit baseline-t08 pass=19 failBlocking=0 failPresent=0；验收 grep 清零 | 唯一失败=StabilityUITests.testDynamicTypeTopBarDoesNotClip **历史冻结**（M18 三轮全量已红，M19 未触碰顶栏/该用例，非 M19 引入，按卡列名+定性）；跨月定位最终形态=月份跳转钩子直达 2024-05 顶部（种子 2020–2026 每月 2 张，钉住头下即当月行+下月头行，零扫描零精调） |
| T09 | BLOCKED | 本提交（检查点）· 验收结果提交 | 本地检查点完成：git log T01–T08 提交链入本文件末尾；Core 终测 Docker **525/525**（t09/core-final-run.log exit=0）；audit-m19 **-Strict exit=0**（0 blocking，t09/audit-strict-run.txt）；T08 绿轮 IPA 校验 run **44894248346** `PhotoDesk-unsigned.ipa` SHA256=e8cfc485…f9c88a1c（1285904B，与 sidecar 一致）**MinimumOSVersion=16.0** ✓、1.7.0 (8)（t09-check/minos.py）；**真机 12 条 BLOCKED**：AltServer 未安装（标准路径无、无进程）+ 真机未接入（无设备枚举通道）+ 交互实测需人工（免费账号 7 天签名亦需人工） | docs/46-M19-验收记录.md 初稿成稿（12 条逐项 BLOCKED + 原因 + 解除条件）；T10 Release 不依赖真机 |
| T10 | TODO | — | — | Release 1.8.0 (9) + IPA 绝对路径 + SHA256 |

## 证据目录约定

- 审查：`artifacts/audit/m19/baseline-A|B/`、`determinism.txt`
- Core 红/绿：`artifacts/audit/m19/t02/`、`t03/`
- CI：`artifacts/ci-evidence/m19-t0x/<run-id>/`
- Release：`artifacts/release/1.8.0/`
- 真机：`docs/46-M19-验收记录.md`（BLOCKED 时列出未执行项）
- T09 检查点：`artifacts/audit/m19/t09/`（core-final-run.log、audit-strict-run.txt）、`artifacts/release/t09-check/`

## T09 本地提交检查点（T01–T08 提交链，git log --oneline）

```text
07f7bd9 docs(m19): T08 进度与 CI 证据
5664c4f fix(selection): 跨月用例改月份跳转直达次旧月顶部
6b449a8 fix(selection): 跨月头下首行判定改用 header.maxY
57f58a5 fix(selection): 跨月锚点取首个完整可见格防残行错位
40e618c fix(selection): 跨月边界精调改低速闭环迭代
ffc55f9 fix(selection): 跨月用例逐屏扫描边界并精调定位
4399f19 fix(selection): 跨月用例改 plain 网格枚举月份头
9d469ab fix(selection): 长按整行语义与跨月几何放宽
1557b31 test(selection): 行带 UI 套件审计口径同步
e50e624 test(selection): 行带 UI 红用例与套件改名
f47de14 docs(m19): T07 进度与性能证据
d80dc43 fix(selection): 第三屏整行用例几何自适应
63823ce fix(selection): 第三屏用例锚点避让钉住头
ac809c8 fix(selection): 第三屏整行用例滚动静止等待
b2bbb61 fix(selection): 自动滚动行带推进与粘性头裁剪
2077cce test(selection): 自动滚动整行红用例
c558468 docs(m19): T06 进度与证据
482d914 test(selection): 行带整行计数红用例
513f294 test(core): 行带边界红用例
3c968f0 docs(m19): T05 进度与证据
b4fad93 feat(selection): 行带命中接线与整行选择
6154e83 test(selection): 行带接线红用例
ca8bc3d docs(m19): T04 进度与 CI 证据
2db42eb fix(selection): 行带红用例锚点改为视口内行（避开粘性头钳制与末行越界）
```

（更早提交：6768992 行带锚点与审计口径 → 0f2ac33 红用例语法修复 → 29bb38e test(selection): 行带命中红用例 → d8102f7 T02 进度 → d5fad57 feat(core): RowBandMap 行带几何与序列 → a70241f test(core): RowBandMap 红用例 → f6fcb43 T03 进度 → b9a346e feat(core): RowBandItem 行带展开 → 21341e6 test(core): 行带展开红用例 → c29cbf3 T01 进度 → 3d589b5 docs(m19): 审查报告 → 9e45894 test(selection): 右列下滑探针红用例 → 58ef379 docs(m19): 修订 41/42 → 6fb2ec0 docs(m19): 分段任务卡）
