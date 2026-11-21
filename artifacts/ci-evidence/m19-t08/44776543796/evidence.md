# T08 红跑：旧逐格契约在 M19 实现上的真实失败 — run 44776543796

- headSha: f47de14（T07 末，迁移前）
- conclusion: failure（预期红；Performance 4/4 通过）
- 旧契约 7 条定向（旧类名 SlideSelectTrailUITests）：**Executed 7 tests, with 6 failures**

| 旧用例 | 结果 | 耗时 |
|---|---|---|
| testDiagonalTrailDoesNotFillRectangle | **failed** | 42.7s |
| testHorizontalPressDragTrailSelectsExactRow | passed | 34.5s |
| testLeftColumnTrailExcludesRightColumn | **failed** | 67.0s |
| testLongPressTrailSelectsExactIDSequence | **failed** | 67.1s |
| testPreSelectedCellSurvivesTrail | **failed** | 33.2s |
| testSelectAllTrailDeselectExactAndExitResets | **failed** | 36.2s |
| testTrailReverseCancelsThenRestores | **failed** | 72.5s |

- 定性：6 条逐格语义用例在行带实现下失败（计数口径 = 行数×列数 ≠ 逐格数），为 B6 的运行时证实；
  testHorizontalPressDragTrailSelectsExactRow 通过属几何巧合（同行横拖的逐格期望 == 整行期望），
  不代表旧语义成立——已按 T08 卡重写为整行断言。
- 迁移：e50e624（test(selection): 行带 UI 红用例与套件改名）— 5 条冲突用例重写 + ② 改左列整行 +
  ⑤ 改同行往返幂等 + ⑬ 整行化 + ⑭ band=/exp= 字段 + 跨月新用例 + 探针退役；套件改名 RowBandSelectUITests。
- 附件：red-meta.json、red-build.log
