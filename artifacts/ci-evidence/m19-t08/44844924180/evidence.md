# m19-t08 全量 run 44844924180（round 5 @ffc55f9 fix(selection): 跨月用例逐屏扫描边界并精调定位）

- 结论：completed:failure；5 failures（跨月新因 + 历史冻结 + 环境抖动 3 例）
- 跨月：边界头已找到（逐屏扫描生效），但「边界头精调失败（minY 未落入锚点/终点可行带
  350-435pt）」（134.7s，RowBandSelectUITests.swift:1156）——press(forDuration:thenDragTo:)
  释放自带惯性滚动，预判式单次拖拽落点偏差超出可行带。
- 环境抖动 3 例（非 M19 回归，round 1/2 同代码全绿）：
  1. FlowUITests.testSwipeFavoriteThenUndoRoundTrip（40.7s）「收藏 Toast 未出现」
  2. GestureUITests.testSwipeUpFavoritesShowsToast（30.4s）「收藏 Toast 未出现」
  3. ZoomStabilityUITests.testPinchAfterBackgrounding（22.2s）app state 3≠4 回前台失败
  通过证据：44783255716/full-build.log 与 44805219332/full3-build.log 三条均 passed
  （41.3/25.8/30.8s 与 43.0/23.4/28.2s）——M19 未触碰 收藏滑动/缩放/后台回切 代码路径。
- StabilityUITests.testDynamicTypeTopBarDoesNotClip（18.5s）——历史冻结（同 round 4 定性）。
- 修复：提交 40e618c（低速拖拽 velocity 30 + 释放前保持 0.4s 抑制惯性 + 按 identifier
  闭环迭代测量→拖→复测，可行带 (351,434)）→ round 6。