# m19-t08 全量 run 44882259960（round 8 @6b449a8 fix(selection): 跨月头下首行判定改用 header.maxY）

- 结论：completed:failure；2 failures（跨月 220.8s + Stability 历史冻结 19.1s）
- 跨月：本轮在更早的精调守卫失败：「边界头精调失败（MonthHeader-Menu-2026-10 minY
  未落入锚点/终点可行带 351-434pt）」（RowBandSelectUITests.swift:1161）——低速闭环
  迭代 5 轮未收敛（velocity 30 拖拽耗时长、手指路径受内容视图干扰，定位不可靠）。
  注：round 7 的阈值修复方向正确但依赖的「精调定位」环节本身不稳定。
- StabilityUITests.testDynamicTypeTopBarDoesNotClip（19.1s）——历史冻结（同前定性）。
- 决策：放弃「逐屏扫描+闭环精调」整条路线，改用 M11/M13 月份跳转启动钩子
  （-uiTestingOpenMonthJump 复位 → -uiTestingMonthJump 2024-05，PositionRestoreUITests
  同款两段式）直达 2024-05（当月 2 张 = 1 行）顶部——钉住头下即当月行、再下即
  2024-04 头 + 行，边界天然悬停视窗中部，零扫描零精调（提交 5664c4f）→ round 9。