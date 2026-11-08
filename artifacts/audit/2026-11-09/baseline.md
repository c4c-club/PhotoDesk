# M15 基线取证（2026-11-09）

## Git
- branch: fix/m15-20261109
- HEAD: 430cc59 (430cc59b7c0840c31003e1a2c134aebbf5e74c41)
- status: 2 个未跟踪项
?? "docs/25-\351\241\265\351\235\242\345\212\237\350\203\275\350\241\245\351\275\220\344\270\216\345\233\233\351\241\271P0\347\273\223\346\236\204\346\200\247\351\207\215\345\201\232\350\247\204\345\210\222.md"
?? "docs/26-\344\270\200\346\254\241\346\200\247\346\211\247\350\241\214\346\217\220\347\244\272\350\257\215.txt"

## project.yml 版本与部署目标
16:    IPHONEOS_DEPLOYMENT_TARGET: "16.0"
17:    MARKETING_VERSION: "1.4.0"
18:    CURRENT_PROJECT_VERSION: "5"

## gh run list
completed	success	Build & Test	Build & Test	fix/p0-20261108	workflow_dispatch	42453291463	1h1m37s	2026-11-08T06:05:14Z
completed	cancelled	Build & Test	Build & Test	fix/p0-20261108	workflow_dispatch	42452281618	15m44s	2026-11-08T05:49:48Z
completed	cancelled	test(ui): 旋转与滑选收尾改用可见 cell 语义	Build & Test	fix/p0-20261108	push	42452271569	13s	2026-11-08T05:49:38Z
completed	failure	Build & Test	Build & Test	fix/p0-20261108	workflow_dispatch	42448406407	56m37s	2026-11-08T04:50:28Z
completed	cancelled	Build & Test	Build & Test	fix/p0-20261108	workflow_dispatch	42447278630	19m29s	2026-11-08T04:33:13Z

## 代码规模
- PhotoDesk swift files: 108
- PhotoDesk swift lines: 17885
- PhotoDeskCore swift files: 57
- Tests files: 34
