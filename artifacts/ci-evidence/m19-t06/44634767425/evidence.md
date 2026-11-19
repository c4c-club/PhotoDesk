# T06 行为矩阵 CI 证据 — run 44634767425

- headSha: 482d914（test(selection): 行带整行计数红用例）
- conclusion: success
- test_filter（定向 3 条 M19 用例）:
  - `-only-testing:PhotoDeskUITests/SlideSelectTrailUITests/testRightColumnBandDragSelectsThreeFullRows`
  - `-only-testing:PhotoDeskUITests/SlideSelectTrailUITests/testRowBandBackslideTwoRowsReturnsToOneRow`
  - `-only-testing:PhotoDeskUITests/SlideSelectTrailUITests/testSelectedAnchorBandDeselectTwoRowsAndRestore`
- Test (simulator) 结果（ui-build.log :5654-6672）:
  - testRightColumnBandDragSelectsThreeFullRows **passed (51.374s)**
  - testRowBandBackslideTwoRowsReturnsToOneRow **passed (46.033s)**
  - testSelectedAnchorBandDeselectTwoRowsAndRestore **passed (60.398s)**
  - Test Suite 'SlideSelectTrailUITests' passed — Executed 3 tests, with 0 failures (157.8s)
- Performance tests (5,000+ photos): Executed 4 tests, 0 failures (286.7s)
- 警告: PhotoWriter:294 / ScanCoordinator:196-197 既有告警重复计数，零新增
- core-linux: PASS（Core 未改动；本地 Docker 详见 ../../audit/m19/t06/core-run.log：524/524，+6 边界用例）
- 如实记录: 6 条 Core 边界 + 3 条 UI 矩阵用例**首跑即绿**——卡片括注「当前实现必然失败：只选右列」写于 T05 接线之前，已过时；
  真实红基线由 T02/T03（Core 语义 cannot find 'RowBandMap'/'RowBandItem'）与 T04/T05（App 接线 no member 'rowBandHitTest'/'trailHitProvider'）提交链承担，本卡用例为行为矩阵语义锁定。
- 附件: ui-meta.json、ui-build.log
