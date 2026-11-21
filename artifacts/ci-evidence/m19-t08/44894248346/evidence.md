# m19-t08 全量 run 44894248346（round 9 @5664c4f fix(selection): 跨月用例改月份跳转直达次旧月顶部）

- 结论：completed:failure —— **77 tests / 1 failure**（6630.7s）+ Performance 4/4（290.3s）
- 唯一失败 = StabilityUITests.testDynamicTypeTopBarDoesNotClip（19.6s）——**历史冻结用例**：
  M18 全量 m18-t08/44173518292-full.log、m18-t10/44367199320-full.log、44392687921-full.log
  均已红（XXXL 下 Library-Category 不可点，last fix 8ac21fe）；M19 未触碰顶栏与该用例，
  非 M19 引入。按 T08 卡「历史冻结用例红：列名 + 定性，不得写全绿」如实记录。
- **RowBandSelectUITests 19/19 全绿**（含 testBandDragAcrossMonthBoundary 通过）：
  月份跳转策略（launchMonthJumpGrid：-uiTestingOpenMonthJump 复位 → -uiTestingMonthJump
  2024-05）落地成功——2020–2026 每月 2 张，跳转后钉住头下即当月 1 行、再下即 2024-04 头
  + 1 行，边界天然悬停视窗中部；锚点取头上方最后完整第 0 列格、头下首行用 boundary.maxY
  阈值，计数 = 4 精确（2 行 × 2 张/月残行）。
- Flow/Gesture/Zoom 三套件本轮全绿（round 5 抖动定性再证实）。
- 全量历程：run 44783255716（3F）→ 44805219332（2F）→ 44827223992（2F）→ 44844924180（5F，
  3 例环境抖动）→ 44858932161（2F，7≠4 跳行）→ 44871405304（2F，阈值根因定位）→
  44882259960（2F，精调不收敛）→ **44894248346（1F = 历史冻结，M19 相关全绿）**。