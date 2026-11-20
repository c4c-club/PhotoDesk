# T07 run F（最终绿）— run 44770333450

- headSha: d80dc43（fix(selection): 第三屏整行用例几何自适应）
- conclusion: success
- 结果：
  - testBottomEdgeHoldBandTrailGrowsAndStopsOnRelease **passed (37.175s)**——底缘按住 2s：屏外 assetID 命中、band=/exp= ≥1、path= ≥ count、触觉节流 ≤64/2s、位移 ≥100pt、松手即停（计数冻结 + drift ≤60pt）
  - testThirdScreenScrollThenBandDragExactRows **passed (60.509s)**——滚两屏后整行计数 = 3×3 精确 + 整行集合独立复算相等
  - Executed 2 tests, with 0 failures (97.7s) — **TEST SUCCEEDED**
  - Performance tests 4/4（303.8s）：Memory Peak 34,932.1 kB（滚动）/ 37,837.6 kB（查看器连滑）
- 修复链：
  - run C 44644633379 @b2bbb61：T07-② 真红 count=0（惯性未静止即按压）
  - run D 44648526747 @ac809c8：静止等待修复后仍红 count=0 → 根因实为锚点半遮格中心落钉住头遮挡区
  - run E 44764473663 @63823ce：锚点避让钉住头后前进到几何余量失败（belowRows=2 < 3）
  - run F @d80dc43：3 行带 = 锚点行 + 下方 2 行（below.count ≥ 2）→ 全绿
- 两轮真红根因均为测试脚手架缺陷（生产行为无缺陷：autoScrollTick/clipTop 审读与 docs/42 §5 一致）
- 附件：f-meta.json、f-build.log
