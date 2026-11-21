# T04 — 混合命中 Core 与几何

> 依赖：T03。状态：⬜。预计：1d。
> 只读：00-索引、本卡；可读 GridHitTester.swift、RowBandMap.swift、SlideSelectPolicy.swift、SlideSelectConfig.swift、LibraryGridGeometryTests.swift。不要读 T05–T08。

## 1. 目标

在不改手势接线的前提下，先把「同一线段何时按 cell、何时按整行」做成可单测的纯逻辑与几何命中。T04 结束时 trailHitTest 已存在且测试通过，但生产手势仍走旧 provider，行为不变。

## 2. Core 改动

### 2.1 SlideSelectConfig.swift

- 增加 public static let rowBandVerticalRatio: Double = 1.2。
- 不把 1.2 散落在 App/Core；测试可注入 ratio。

### 2.2 SlideSelectPolicy.swift

- 增加 public enum SlideSelectHitMode: Equatable, Sendable { case cells; case rows }。
- 增加 static func hitMode(dx:dy:fromBand:toBand:verticalDominanceRatio:) -> SlideSelectHitMode。
- 规则：
  - fromBand == toBand → .cells；
  - abs(dy) >= abs(dx) * ratio → .rows；
  - 其他 → .cells；
  - 非有限输入 → .cells。
- 只 import Foundation；不引 UIKit/Photos。

### 2.3 新增 PhotoDeskCoreTests/SlideSelectHitModeTests.swift

- 同带水平 → cells。
- 同带零长度 → cells。
- 跨带纵向 → rows。
- 跨带水平 → cells。
- 恰好 1.2 边界 → rows（>= 语义）。
- 1.19 → cells。
- NaN/∞ → cells，不崩溃。

## 3. App 几何改动

### 3.1 GridHitTester.swift

新增 App 层值类型：

    struct GridTrailHit {
        let mode: SlideSelectHitMode
        let indexPaths: [IndexPath]
        let rewindIndexPath: IndexPath?
    }

新增：

    func trailHitTest(from: CGPoint, to: CGPoint, clipTop: CGFloat) -> GridTrailHit

行为：

1. 用 RowBandMap.bandIndex 取 fromBand/toBand；任一 nil → 调 hitTestLine 返回 .cells；不得回退整行。
2. 调 SlideSelectPolicy.hitMode。
3. .cells → hitTestLine(from:to:)；零长度返回该点 cell（若有）；rewind nil。
4. .rows 且 toBand > fromBand（向下）：
   - indexPaths = RowBandMap.items(forBandIndices: bandSequence(from:to:)) 映射 IndexPath；
   - rewind nil；
   - 行主序、列升序；不在此层过滤 trail.path（控制器负责）。
5. .rows 且 toBand < fromBand（向上）：
   - rewindIndexPath = toBand 行的最后一个 item IndexPath；
   - indexPaths = hitTestLine(from:to:) 作为 fallback；
   - 不返回整行。
6. 不修改 hitTestLine 的排序语义；不重新实现 RowBandMap。

关键：trailHitTest 本身不做「长按起手」；起手仍只由 T05 的 beginTrail 消费 anchor。

### 3.2 LibraryGridGeometryTests.swift

新增/重写新语义测试（旧 rowBandHitTest 测试可暂时保留到 T06 删除）：

- 4 列 3 行 fixture：
  - 起手点零长度 → 1 个 cell。
  - (1,1)→(1,4) → 4 个，顺序 1..4。
  - (1,4)→(2,4) → 8 个，行主序。
  - (2,4)→(3,4) → 12 个（从第 1 行起算的 fixture 需包含第 1 行；按实际 fixture 调整期望）。
  - (3,4)→(3,2) → 倒序 3,4、3,3、3,2。
- 对角线横向占优 → .cells。
- 跨 section：bandSequence 正确、不假设每段 4 列。
- 期望集合由真实 frame 独立暴力计算，不调用 trailHitTest 自证。

## 4. 执行步骤

1. 写 Core hitMode 测试（先红）。
2. 加 config 常量 + SlideSelectPolicy.hitMode；跑 scripts/test-core.ps1 绿。
3. 写 GridHitTester.trailHitTest 与几何测试（先红）。
4. 跑 app 单元测试（CI 或本地不可则 CI）；记录 run id。
5. 确认生产 LibraryViewController 仍使用旧 rowBandHitProvider，行为未变；T04 不接线。
6. 更新 progress；commit：feat(selection): 增加混合命中模式与轨迹几何。

## 5. 验收

- hitMode 单测全绿，边界精确。
- trailHitTest 在 4 列 fixture 上返回精确 IndexPath 数与顺序。
- 零长度不再返回整行。
- 横向线段不再返回整行。
- 跨行纵向返回整行，且不依赖每行固定 4 列。
- 旧生产路径未改，现有 UI 测试不受影响（旧横向整行测试仍绿是预期，T06 再重写）。

## 6. BLOCKED 处理

如果 RowBandMap 的 clipTop/多 section 缓存无法在单元测试中稳定构造，先补一个纯几何 fixture builder；不得把 App 层 UIKit 类型塞进 Core。若 CI 无法跑 app 单元测试，记录 BLOCKED，不能把 Core 测试绿当成几何绿。

## 7. 下一卡

T05 — 手势锚点与选择接线。完成并 commit 后才能读。
