// MARK: - SlideSelectTrailTests：原生轨迹滑选路径事务红/绿（M18 T02，docs/38 §2.3、docs/37 §5）——
// 语义锁：consume(orderedIDs) 逐 id「抖动忽略 / 已访问截断回最近出现 / 新 id 入栈」；
// target = select ? base ∪ Set(path) : base − Set(path)；delta = 相对上一帧净差（同帧 A→B→A→B 抵消）；
// consume([]) 幂等；base/mode/scope init 快照不可变；base 先与 scope 取交集。
// 红测试清单：artifacts/audit/m18/t02-red-test-list.md（16+ 条口径）。

import XCTest
@testable import PhotoDeskCore

final class SlideSelectTrailTests: XCTestCase {

    // MARK: - select 正向与幂等

    func testConsumeFirstIDAppendsAndSelects() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        let delta = trail.consume(["a"])
        XCTAssertEqual(delta.add, ["a"])
        XCTAssertTrue(delta.remove.isEmpty)
        XCTAssertEqual(trail.target, ["a"])
        XCTAssertEqual(trail.path, ["a"])
    }

    func testConsumeEmptyIsIdempotent() {
        var trail = SlideSelectTrail(base: ["p"], anchorInitiallySelected: false)
        _ = trail.consume(["a"])
        let before = trail.target
        for _ in 0..<3 {
            let delta = trail.consume([])
            XCTAssertTrue(delta.isEmpty, "consume([]) 必须幂等返回空 delta")
        }
        XCTAssertEqual(trail.target, before, "consume([]) 不得改变 target/path")
    }

    func testConsumeSameAsLastIsIgnored() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["a"])
        _ = trail.consume(["b"])
        let delta = trail.consume(["b"])   // 抖动：id == path.last
        XCTAssertTrue(delta.isEmpty, "抖动 id 必须忽略（docs/38 §2.3 第 1 行）")
        XCTAssertEqual(trail.path, ["a", "b"])
    }

    func testConsumeNewIDsAppendInOrder() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["a"])
        let d2 = trail.consume(["b"])
        XCTAssertEqual(d2.add, ["b"])
        let d3 = trail.consume(["c"])
        XCTAssertEqual(d3.add, ["c"])
        XCTAssertEqual(trail.path, ["a", "b", "c"], "路径栈必须保持访问顺序")
    }

    // MARK: - 回滑截断（滑到哪选到哪、回滑取消）

    func testBackslideTruncatesAndDeselectsNewcomer() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["a"])
        _ = trail.consume(["b"])
        _ = trail.consume(["c"])
        let delta = trail.consume(["b"])   // 回滑到 b：c 出栈回 base 态
        XCTAssertEqual(delta.remove, ["c"], "回滑截断：c 必须从 target 移除")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.path, ["a", "b"])
        XCTAssertEqual(trail.target, ["a", "b"])
    }

    func testBackslideToRootKeepsAnchorInitial() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["a"])
        _ = trail.consume(["b"])
        let delta = trail.consume(["a"])   // A→B→A：A 保持模式初态，B 出栈
        XCTAssertEqual(delta.remove, ["b"])
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.path, ["a"])
        XCTAssertEqual(trail.target, ["a"], "不变量 3：A 保持入选，不是被 toggle")
    }

    func testAlternatingTrailKeepsEarlierIDStable() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["a"])           // path=[a]，a 入选
        let delta = trail.consume(["a", "b", "a", "b"])   // 单帧 A→B→A→B
        XCTAssertEqual(delta.add, ["b"], "同帧 A→B→A→B 净抵消：相对上一帧只多 b")
        XCTAssertTrue(delta.remove.isEmpty, "a 的选中态全程不翻转（不变量 3）")
        XCTAssertEqual(trail.path, ["a", "b"])
    }

    // MARK: - deselect 模式（起手已选 → 滑过取消、回滑恢复）

    func testDeselectModeSubtractsFromBase() {
        var trail = SlideSelectTrail(base: ["a", "b", "x"], anchorInitiallySelected: true)
        let delta = trail.consume(["x"])
        XCTAssertEqual(delta.remove, ["x"], "deselect：滑过已选 cell 即取消")
        XCTAssertTrue(delta.add.isEmpty)
        XCTAssertEqual(trail.target, ["a", "b"])
        XCTAssertEqual(trail.mode, .deselect)
    }

    func testDeselectBackslideRestoresBaseState() {
        var trail = SlideSelectTrail(base: ["a", "b", "x", "y", "z"], anchorInitiallySelected: true)
        _ = trail.consume(["x"])
        _ = trail.consume(["y"])
        _ = trail.consume(["z"])
        let delta = trail.consume(["y"])   // z 出栈 → 回 base 态（已选）
        XCTAssertEqual(delta.add, ["z"], "deselect 回滑：出栈 cell 必须恢复 base 选中态")
        XCTAssertTrue(delta.remove.isEmpty)
        XCTAssertEqual(trail.target, ["a", "b", "x", "y"])
    }

    // MARK: - base 保护与双基线

    func testBaseProtectedFromDelta() {
        var trail = SlideSelectTrail(base: ["p"], anchorInitiallySelected: false)
        _ = trail.consume(["p"])           // base 内 id 入栈：target 不变（p 已在 base）
        let d2 = trail.consume(["q"])
        XCTAssertEqual(d2.add, ["q"])
        let d3 = trail.consume(["p"])      // 回滑截断到 p
        XCTAssertEqual(d3.remove, ["q"])
        XCTAssertTrue(trail.target.contains("p"), "手势前已选 p 全程保持（base 保护）")
        XCTAssertFalse(trail.target.contains("q"))
    }

    func testAnchorInBaseSurvivesTrailForLongPressEntry() {
        // 长按进入：enterSelection 已把锚点写进 selectionState → base 含锚点（docs/38 §2.2）
        var trail = SlideSelectTrail(base: ["anchor"], anchorInitiallySelected: false)
        _ = trail.consume(["anchor"])
        _ = trail.consume(["b"])
        _ = trail.consume(["c"])
        _ = trail.consume(["b"])           // c 出栈
        _ = trail.consume(["anchor"])      // 回滑到锚点：b 出栈
        XCTAssertTrue(trail.target.contains("anchor"), "任意回滑/截断后锚点必须保持选中")
        XCTAssertEqual(trail.target, ["anchor"])
    }

    // MARK: - scope 与防御性输入

    func testScopeOutsidersNeverEnterPath() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false, scope: ["a", "b"])
        let d1 = trail.consume(["out"])
        XCTAssertTrue(d1.isEmpty, "scope 外 id 忽略")
        XCTAssertTrue(trail.path.isEmpty, "scope 外 id 不得进入路径栈")
        let d2 = trail.consume(["out"])
        XCTAssertTrue(d2.isEmpty, "重复 scope 外 id 仍忽略（不残留 occurrences）")
        let d3 = trail.consume(["a"])
        XCTAssertEqual(d3.add, ["a"], "scope 内 id 正常入栈")
    }

    func testEmptyIDIsIgnored() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        let delta = trail.consume([""])
        XCTAssertTrue(delta.isEmpty, "空 id 忽略（防御性）")
        XCTAssertTrue(trail.path.isEmpty)
    }

    func testDuplicateIDsInOneFrameCollapse() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        let delta = trail.consume(["a", "a", "a"])
        XCTAssertEqual(delta.add, ["a"], "同帧重复 id 折叠：等价单次 append")
        XCTAssertEqual(trail.path, ["a"])
    }

    func testNetDeltaAgainstPreviousFrame() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        _ = trail.consume(["a"])                                  // 上一帧：path=[a]
        let delta = trail.consume(["b", "a", "b", "c"])           // 单帧乱序回跳
        XCTAssertEqual(delta.add, ["b", "c"], "净 delta 相对上一帧：只多 b/c")
        XCTAssertTrue(delta.remove.isEmpty, "a 保持，不出现在净差中")
        XCTAssertEqual(trail.path, ["a", "b", "c"])
    }

    // MARK: - 快照不可变与 target/delta 一致性

    func testSnapshotImmutableAfterInit() {
        var baseSet: Set<String> = ["a"]
        var scopeSet: Set<String> = ["a", "b"]
        var trail = SlideSelectTrail(base: baseSet, anchorInitiallySelected: false, scope: scopeSet)
        baseSet.insert("z")
        scopeSet.insert("z")
        _ = trail.consume(["b"])
        XCTAssertFalse(trail.target.contains("z"), "init 后外部修改传入集合不得影响快照（值语义防御）")
        XCTAssertEqual(trail.base, ["a"])
    }

    func testTargetMatchesAccumulatedDeltas() {
        var trail = SlideSelectTrail(base: ["p"], anchorInitiallySelected: false, scope: ["p", "a", "b", "c", "d"])
        var accumulated: Set<String> = trail.target
        let script: [[String]] = [["a"], ["b"], ["c"], ["b"], ["a"], ["d"], ["a"], ["b"]]
        for frame in script {
            let delta = trail.consume(frame)
            accumulated.formUnion(delta.add)
            accumulated.subtract(delta.remove)
            XCTAssertEqual(accumulated, trail.target, "逐帧 delta 累加必须始终等于 target（帧 \(frame)）")
        }
        XCTAssertEqual(trail.target, ["p", "a", "b"], "终态：base ∪ 最终 path")
    }

    // MARK: - 性能（docs/38 §4：10k 步 <5ms，Docker swift:6.0-noble 预算）

    func testTenThousandStepsUnderBudget() {
        var trail = SlideSelectTrail(base: [], anchorInitiallySelected: false)
        let pool = (0..<100).map { "id-\($0)" }
        let start = Date()
        for i in 0..<10_000 {
            _ = trail.consume([pool[i % 100]])
        }
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        XCTAssertLessThan(elapsedMs, 5, "10k 步 consume <5ms（实际 \(elapsedMs)ms，docs/38 §4）")
        XCTAssertLessThanOrEqual(trail.path.count, 100, "路径栈由截断机制自限，不得无界增长")
    }
}
