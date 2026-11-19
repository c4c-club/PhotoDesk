# M19-T01 CI 行为基线证据 · run 44564827772

- run: 44564827772（workflow_dispatch，ref feat/m19-row-band @ 9e45894）
- test_filter: -only-testing:PhotoDeskUITests/SlideSelectTrailUITests/testLeftColumnTrailExcludesRightColumn -only-testing:PhotoDeskUITests/SlideSelectTrailUITests/testProbeRightColumnSlideDownThreeRowsEvidence
- 结论: success（2026-11-19T16:50:41Z）；core-linux success，build success
- 套件汇总: Executed 2 tests, with 1 test skipped and 0 failures (0 unexpected) in 77.472 seconds
- 日志摘录（job build / step Test (simulator)，UTC）:
  - 16:34:13.431 Test Suite 'SlideSelectTrailUITests' started
  - 16:34:13.453 Test Case testLeftColumnTrailExcludesRightColumn started
  - 16:34:51.308 Test Case testLeftColumnTrailExcludesRightColumn passed (37.935 seconds)
  - 16:34:51.315 Test Case testProbeRightColumnSlideDownThreeRowsEvidence started
  - 16:35:30.616 SlideSelectTrailUITests.swift:917: Test skipped - T01 临时探针：证据已采集（actual=4 bandTarget=9）；T06/T08 转正断言 actual == 3×columns
  - 16:35:30.928 Test Case testProbeRightColumnSlideDownThreeRowsEvidence skipped (39.537 seconds)
  - 16:35:30.928 Test Suite 'SlideSelectTrailUITests' passed
- 解读: 左列旧契约自洽（passed）；探针=右列锚点下滑 3 行，bandTarget=9（3 行×3 列）vs actual=4（线段扫过列 cell：锚点+同列下方 3 格）→ docs/41 §3 根因「命中粒度=cell 而非行带」实锤。
- 附件说明: 探针 XCTAttachment 仅入 xcresult（成功 run 不上传该产物），证据以 skip reason 与本摘录为准；截图同因不落盘。
