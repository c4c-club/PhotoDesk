# m19-t08 全量 run 44858932161（round 6 @40e618c fix(selection): 跨月边界精调改低速闭环迭代）

- 结论：completed:failure；2 failures
- 跨月 testBandDragAcrossMonthBoundary（194.8s）：逐屏扫描 + 低速闭环精调**全部生效**
  （边界头找到并定位进可行带，拖拽真实执行），但计数 7 ≠ 期望 4：多选整 1 行 3 格。
  根因（测试脚手架）：锚点取「最后一个完整可见格」= 残行最右列（2026-11 末行 167%3=2
  格，无第 2 列？实取第 2 列格），而边界下方首行为残行（旧月 2 张 → 无同列格），
  `below.first` 落到下一行 → 拖拽终点多跨一行 → 行带 = 锚行..多跨行 = 7 格；
  期望行集按同列取行，漏掉中间整行 → 4 格。**App 行为正确**（行带精确覆盖所跨行）。
- StabilityUITests.testDynamicTypeTopBarDoesNotClip（19.0s）——历史冻结（同 round 4/5 定性）。
- round 5 的 3 例环境抖动（Flow/Gesture/Zoom）本轮**全部转绿**——抖动定性再次证实。
- 修复：提交 57f58a5（锚点改取头上方第一个完整可见格 = 第 0 列，任何行必有同列格）→ round 7。