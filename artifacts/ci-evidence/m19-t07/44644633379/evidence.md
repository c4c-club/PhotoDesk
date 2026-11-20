# T07 run C（合并：geometry 回归 + 2 条 T07 UI 用例 + Performance 套件）— run 44644633379

- headSha: b2bbb61（fix(selection): 自动滚动行带推进与粘性头裁剪）
- conclusion: failure（T07-② 真红；其余全绿）
- 结果：
  - LibraryGridGeometryTests **23/23 passed**（0.359s）——行带实现回归绿
  - testBottomEdgeHoldBandTrailGrowsAndStopsOnRelease **passed (25.155s)**（T07-① 底缘按住 2s：屏外命中/band=exp= 就位/path≥count/节流/松手即停）
  - testThirdScreenScrollThenBandDragExactRows **FAILED (84.148s)**：`:1185: failed - 第 3 屏下滑 3 行计数必须 = 3×3（count=0，实际选中=[]）`
    - 根因：swipeUp×2 惯性衰减慢于固定 0.8s settle，内容移动中按压点漂移超 allowableMovement → 长按识别失败（**测试脚手架缺陷**，非生产行为缺陷；M18 ⑨ 同场景因断言方向相反未暴露）
    - 修复：ac809c8 改 off= 连续两次采样静止等待（fix(selection): 第三屏整行用例滚动静止等待）
  - Performance tests 4/4 passed（251.4s）：Memory Peak 34,309.5 kB（滚动）/ 37,722.9 kB（查看器连滑）
- 附件：c-meta.json、c-build.log
