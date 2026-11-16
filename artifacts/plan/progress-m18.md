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
| T06 | DONE | 6910751（退役+红基线）/ 本卡 docs 提交 | 红基线 t06-red（B06=17）；绿审查 t06-green（验收 grep=0；B06=1 deprecated 声明=卡允许；B10=39 T08 冻结）；Docker 483/483 不变；CI run 43764101857：build ✓ + 单测 275/275 绿 + UI 9 败全旧契约（同 T05 轮集合） | hitTest(rectInContent:) 剩 1 deprecated 声明 + 测试旧调用 **4 处**（T07 归零）；deprecated 警告 = 旧测调用点（Core resolved×12/mergedSelection×4/selectRange×5/applyRange×1），T08 迁移后归零；文案校对入 docs/39 |
| T07 | DONE | 20d99d5（红基准）/ e368ddc（迁移+物理删除）/ 432ff1c（本卡 docs） | Docker **483/483**；CI run 43776095915：**单测 282/282 全绿**（红轮即绿：16 组合独立暴力基准全一致，实现自 T05 起正确，红轮结论如实记录）；迁移轮 run 43893471130：**单测 280/280 全绿**、geometry 弃用警告清零；audit -Strict t07：**B06=0**、B10=33（全 UI 冻结契约，T08 收口）；验收 grep `hitTest(rectInContent|MarqueeOverlayView|Marquee-Overlay|lastMarqueeRect` = 0 | 真布局线段 16 组合基准一致；DSSpacing 仅用于粘性头高（docs/38 §3 口径）；性能 4/4 过 |
| T08 | DOING | ee25099（红+清理）/ 33d4874·07d8bf3（编译修）/ 2de3cd0（月份scope）/ faea30f（边缘区）/ 941484a（CI 重试） | 定向轮 run 43936713988：**14 条用例首实跑 9 过 5 败**（+1 格边缘滚动根因 ×4、月份头未进视口 ×1，修复见 faea30f）；macos-15 runner 启动挂死间歇故障（6 轮中 4 挂，9 分钟零输出判死）→ ios.yml 增加挂死特征自动擦洗重试（941484a） | 迭代中 |
| T09 | TODO | — | — | 本地 git 检查点、AltServer 真机 12 条 |
| T10 | TODO | — | — | 1.7.0 (8) Release、IPA 绝对路径 + SHA256 |

## 证据目录约定

- 审查：`artifacts/audit/m18/baseline-*`
- Core 红/绿：`artifacts/audit/m18/t02/*`、`t03/*`
- CI：`artifacts/ci-evidence/m18-t*/<run-id>/*`
- Release：`artifacts/release/1.7.0/*`
- 真机：`docs/39-M18验收记录.md`；未接入写 BLOCKED + 未执行项清单
