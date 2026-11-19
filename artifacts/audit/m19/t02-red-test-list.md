# T02 红测试清单（RowBandMap 行带几何与序列）— T01 产出

> 依据 docs/42 §3.1/§4 + docs/45 §3 可行性结论。T02 开工时先写以下红用例（Docker `swift test` 真实失败），再实现 `RowBandMap.swift`。
> 文件：`PhotoDeskCore/Tests/PhotoDeskCoreTests/RowBandMapTests.swift`；几何输入全 `Double`/`Int`（红线 2）。

| # | 用例名 | 断言要点 |
|---|---|---|
| 1 | testBandIndexAtContentYReturnsRowUnderFinger | `bandIndex(atContentY:)` 命中指尖所在行（行内任意 y，含行底边缘） |
| 2 | testBandIndexClampsToNearestRowInGap | y 落在行间空隙/行底边界时钳到最近行（吸附容差 `rowBandSnapTolerance`，常量取自 SlideSelectConfig） |
| 3 | testBandIndexBeyondBoundsClampsToEndRows | y 越过首行上/末行下 → 钳首/末行带，不返回越界 |
| 4 | testBandIndexRespectsStickyHeaderClip | `clipTop` 以下才可命中；被钉住头完全遮住的行不可命中；钳到头下缘最近的可见行 |
| 5 | testBandIndexReturnsNilWhenAllOccluded | 全部行被遮挡时返回 nil（不产生命中） |
| 6 | testBandSequenceForwardCoversInclusiveRange | `bandSequence(from:to:)` 双端含；正向按平铺序升序 |
| 7 | testBandSequenceReverseMirrorsOrder | 反向（from>to）= 正向序列精确镜像（回滑出栈依赖单调性） |
| 8 | testBandSequenceSameBandReturnsSingle | from == to → 单元素序列（零长度线段 = 指尖所在整行） |
| 9 | testBandSequenceClampsOutOfBounds | to 越过末行 → 钳末行；from 越界 → 钳首行；序列不越界 |
| 10 | testBandSequenceCrossesSectionsInFlatOrder | 跨 section：平铺序 = section 升序 → row 升序；空段（itemCount==0）跳过 |
| 11 | testBandItemsExpandFullRowColumns | `items(forBandIndices:)` 行带 → `row*cols ..< min((row+1)*cols, itemCount)` 全列展开 |
| 12 | testBandItemsPartialLastRowExpandsRealItemsOnly | 末行不满只展开真实 item（如 itemCount=13, cols=4 → 末行 1 个） |
| 13 | testBandItemsColumnAscendingAndDeduped | 行内列升序；重复 band 下标去重；保持输入顺序 |
| 14 | testBandItemsAcrossBandsSectionAscending | 多行带展开按输入 band 顺序串联，section 升序不变 |
| 15 | testSingleColumnGridExpandsSingleItemBand | columns=1 行带 = 单格行 |
| 16 | testSlideSelectConfigRowBandConstantsExist | `rowBandSnapTolerance`/`rowBandMaxExpandPerFrame` 进 `SlideSelectConfig`（默认 0 = 不限，docs/42 §10.2），禁散落魔法数字 |

**T03 组合红用例预告**（同卡内追加 `RowBandTrailTests`）：行带序列喂 `SlideSelectTrail.consume` 的正向累加/回滑整行撤销/预选保持/取消模式恢复/净 delta——T02 不实现，T03 红测试先行。
**性能口径**（T07 实测）：2 万 item 平铺 + 全序列展开 < 5ms（docs/42 §5）。
