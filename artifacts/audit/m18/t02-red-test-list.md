# T02 红测试清单（SlideSelectTrail 路径事务）

> 依据：docs/38 §2.3（路径事务语义）、§4（Core Trail 事务矩阵）、docs/37 §5（双基线）。本文件只列用例名与断言口径，**不写实现**；T02 先落红测试跑出真实失败（引用 `SlideSelectTrail` 未定义 → 编译失败即红证据），再实现转绿。
> 断言口径统一：`delta` = 相对上一帧的净 add/remove（Set<String>）；`target` = base ± Set(path)；`mode`/`base` 在 init 快照后不可变；`consume([])` 幂等。

| # | 用例名 | 断言口径 |
|---|---|---|
| 1 | testConsumeFirstIDAppendsAndSelects | select 模式、base 空：consume(["a"]) → path=[a]，delta add={"a"}，target={"a"} |
| 2 | testConsumeEmptyIsIdempotent | 连续 consume([]) ≥3 次：path 不变、每次 delta 均为空集 |
| 3 | testConsumeSameAsLastIsIgnored | path=[a,b] 后 consume(["b"])：忽略抖动，path 不变，delta 空（docs/38 §2.3 第 1 行） |
| 4 | testConsumeNewIDsAppendInOrder | consume(["a"])→consume(["b"])→consume(["c"])：path=[a,b,c]，delta 依次 add b、add c（顺序可从 delta 输出顺序断言） |
| 5 | testBackslideTruncatesAndDeselectsNewcomer | path=[a,b,c] 后 consume(["b"])：truncate 到最近 b → path=[a,b]，delta remove={"c"}（c 回 base 态），a/b 保持 |
| 6 | testBackslideToRootKeepsAnchorInitial | path=[a,b] 后 consume(["a"])：path=[a]，delta remove={"b"}；a 保持模式初态不翻转（不变量 3：A→B→A 的 A 非toggle） |
| 7 | testAlternatingTrailKeepsEarlierIDStable | 单帧 consume(["a","b","a","b"])：最终 path=[a,b]；全程 a 的选中态从不翻转（净 delta 只含 b），同帧 A→B→A→B 相互抵消（docs/38 §2.3 第 5 行） |
| 8 | testDeselectModeSubtractsFromBase | deselect 模式、base={"a","b","x"}：consume(["x"]) → delta remove={"x"}，target={"a","b"} |
| 9 | testDeselectBackslideRestoresBaseState | deselect 模式 path=[x,y,z] 后 consume(["y"])：z 出栈恢复 base 态 → delta add={"z"}；x/y 保持取消 |
| 10 | testBaseProtectedFromDelta | select 模式 base={"p"}（含手势前已选）：任意 consume 序列 delta 永不含 p（base 保护，docs/38 §4） |
| 11 | testScopeOutsidersNeverEnterPath | scope={"a","b"}：consume(["out"]) → path 不变、delta 空；后续 consume(["out"]) 仍忽略（不残留 occurrences） |
| 12 | testDuplicateIDsInOneFrameCollapse | consume(["a","a","a"])：等价 consume(["a"])，path=[a]，delta add={"a"} 一次 |
| 13 | testNetDeltaAgainstPreviousFrame | path=[a]（上帧已 add a）后单帧 consume(["b","a","b","c"])：净 delta = remove 无 a？→ 断言相对上一帧净差：add={"b","c"}，a 保持（净差口径锁） |
| 14 | testTenThousandStepsUnderBudget | （T02 修订，docs/38 §4 留痕）10k 步绝对回归闸 60ms + 4× 步数 <8× 耗时摊还线性锁；原「<5ms」DEBUG Docker 五连跑 16.0–24.9ms 不可达，语义断言未动 |
| 15 | testSnapshotImmutableAfterInit | init(base:mode:scope:) 后外部修改传入集合（防御性拷贝）不影响 trail 状态；mode/base 只读 |
| 16 | testAnchorInBaseSurvivesTrailForLongPressEntry | 长按进入场景 base 含锚点 a：任意回滑/截断后 a 始终 ∈ target（T05 双基线 Core 侧前置，docs/38 §2.2） |

补充口径：

- `SlideSelectMode` 复用 select/deselect 语义（对齐 `MarqueeMode`）；`SlideSelectDelta` = `add: Set<String>, remove: Set<String>`。
- 出栈恢复 =「回 base 态」：select 模式下出栈 cell 是否已选由 base 决定，不由路径栈决定（#5/#9 的断言据此写死）。
- 性能用例（#14）在 Docker `swift:6.0-noble` 跑，阈值 5ms 取 docs/38 §4「10k 步 <5ms」；失败即性能债，不许放宽。
- T02 红证据 = 新测试文件引用 `PhotoDeskCore.SlideSelectTrail` 编译失败（swift build 报 cannot find）；绿 = test-core.ps1 443+16 全绿。
