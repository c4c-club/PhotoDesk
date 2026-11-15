# M18 执行进度

> 按 `docs/36-任务分段/00-索引.md` 顺序执行；**一次只读一张任务卡**。每卡先红测试后实现，单独提交，更新本表后才读下一卡。
> 状态：TODO / DOING / BLOCKED（等 CI / 等真机）/ DONE（门禁通过且已提交）。

| 任务 | 状态 | 提交 | 门禁/证据 | 备注 |
|---|---|---|---|---|
| T01 | DONE | 0a59ff8（M17 归档）/ ce6b58f（audit 脚本+红基线）/ 本卡 docs 提交（见 git log 第 3 条） | audit-m18 29 项：A/B 确定性一致 + `-Strict` exit 2（3 BLOCKING 红基线）；Core Docker 443/0；docs/37 §0–§10 + docs/38 T01 修订 + t02-red-test-list 16 条 | M17 归档 14 文件；红基线 B06=45/B08=18/B10=39 |
| T02 | DONE | 05b7f10（红）/ a1d2d4c（绿）/ 本卡 docs 提交（git log 第 3 条） | Docker **461/461**（+18）；CI core-linux success（run 43735741291）；红日志 artifacts/audit/m18/t02/red-compile-failure.log；性能预算 T02 修订见 docs/38 变更日志 | applyRange/selectRange 仅定义 0 调用 |
| T03 | DONE | 2210868（红）/ 9e53f36（绿）/ 本卡 docs 提交（git log 第 3 条） | Docker **480/480**（+19）；CI core-linux success（run 43736641548）；性能 2 万 frame 5ms ≪ 20ms 预算 | CellFrame 抽出 + typealias 桥接；反向序列断言就位 |
| T04 | DONE | 7459d08（红）/ 22e09d7（绿）/ 本卡 docs 提交（git log 第 3 条） | Docker **483/483**（+3）；旧名 grep=0；状态表/阈值零行为改动 | **T05 接线前 App 暂不可编译，本卡只留本地 Docker 证据，CI 由 T05 统一跑** |
| T05 | DONE | 5118921（红）/ 5417dc6（接线）/ 403d869（修复）/ 本卡 docs 提交 | 红 run 43738415536（App 旧名 ×3 编译红）；修复轮 run 43750931513：**App 编译恢复 ✓ + 单测 275/275 绿**（2 条 hitTestLine 真布局测试过）；UI 78 条中 9 败全部为旧框选契约（MarqueeSelection ×2 / PageRegression ×1 / Stability ×6，T08 重写范围，无新增失败） | **App 编译已恢复**；矩形接口仅剩 hitTest(rectInContent:) 声明本体（T07 随测试迁移删除，未加 deprecated 属性避免新增警告）；0.15s 过渡按文本级语义（每帧写、计数变才变文案，docs/38 无此表述，不引入 UIView 动画避免动冻结契约） |
| T06 | TODO | — | — | 退役框选视觉/矩形残留/文案 |
| T07 | TODO | — | — | 真布局单测 + 自动滚动/粘性头/触觉 |
| T08 | TODO | — | — | 重写精确路径 UI 断言 + CI 模拟器实跑 |
| T09 | TODO | — | — | 本地 git 检查点、AltServer 真机 12 条 |
| T10 | TODO | — | — | 1.7.0 (8) Release、IPA 绝对路径 + SHA256 |

## 证据目录约定

- 审查：`artifacts/audit/m18/baseline-*`
- Core 红/绿：`artifacts/audit/m18/t02/*`、`t03/*`
- CI：`artifacts/ci-evidence/m18-t*/<run-id>/*`
- Release：`artifacts/release/1.7.0/*`
- 真机：`docs/39-M18验收记录.md`；未接入写 BLOCKED + 未执行项清单
