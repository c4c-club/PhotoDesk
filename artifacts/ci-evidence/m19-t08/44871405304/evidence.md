# m19-t08 全量 run 44871405304（round 7 @57f58a5 fix(selection): 跨月锚点取首个完整可见格防残行错位）

- 结论：completed:failure；2 failures（跨月 179.8s + Stability 历史冻结 20.1s）
- 跨月：仍 7≠4（count=7，expected=4，4 格 ⊂ 7 格，多出整 1 行 3 格）。
  **真正根因（本轮定位）**：期望/终点过滤用 `minY > boundary + headerHeight`，而
  boundary = 头 midY（= minY+24），故阈值 = header.minY+72；头下首行 minY ≈
  header.minY+50 —— 首行**恒被跳过**，`below.first` 落到第二行 → 拖拽终点多跨一行。
  App 行为正确（行带精确覆盖锚行..终点行 3 行 7 格）；期望只数了第 1、3 行（4 格）。
  7 = rowA(2) + rowB(3) + rowB2(2)，4 = rowA(2) + rowB2(2)，完全吻合。
- StabilityUITests.testDynamicTypeTopBarDoesNotClip（20.1s）——历史冻结（同前定性）。
- 修复：提交 6b449a8（阈值改 `boundary + headerHeight / 2` = header.maxY，首行必中）→ round 8。