# m19-t08 全量 run 44827223992（round 4 @4399f19 fix(selection): 跨月用例改 plain 网格枚举月份头）

- 触发：push 自动全量（ios.yml push+workflow_dispatch 双挂，cancel-in-progress）
- 结论：completed:failure；77 tests，2 failures
- 失败：
  1. RowBandSelectUITests.testBandDragAcrossMonthBoundary（76.8s）——视口内无悬停月份头。
     根因：UITestDatedPhotoSeeder 把 167 张集中在当前月（AX 实锤 '2026年11月 · 167 张'，
     ~56 行 ≈ 7600pt），固定 2-5 次 swipeUp 的落点永远在月内，边界头不可见。
  2. StabilityUITests.testDynamicTypeTopBarDoesNotClip（20.3s）——历史冻结（M18 全量
     m18-t08/44173518292 + m18-t10/44367199320 + 44392687921 已红），非 M19 引入。
- 关键 AX 证据（本目录 full-build.log 23:01:52 层级快照）：CollectionView {{0,62},{402,778}}；
  钉住头 '2026年11月 · 167 张'；可见 cell 全部 '2026年11月20日'；行 pitch 136pt（98.7→234.7）。
- 修复：提交 ffc55f9（逐屏 swipeUp+每步扫描+钉住头换月检测+120pt 回拖+预判精调）→ round 5。