// MARK: - 职责说明：SelectionGestureMachine 状态机全迁移单测（M17 T02，docs/32 §2.2）——
// 覆盖状态表每一行 + 卡内附加 5 条（短长按/纵向让位/反向收缩/边缘往返/非有限安全）。
// 事件枚举在 docs/32 §2.2 六个事件之外补 edgeEntered(direction:)/edgeExited：
// 状态表第 7/8 行「指尖进/离边缘」必须有事件载体才能全覆盖单测（机器只判定，App 层检测边缘）。
// 效果序列契约：
//   holdElapsed → [haptic(.impactLight), enterSelection(anchorID), beginMarquee]（表第 2 行副作用顺序）
//   pressing 横向锁定 → dragging + [enterSelection(未在多选时)/无, beginMarquee]（表第 3 行「必要时先进入多选」）
//   dragging moved → [updateMarquee] + 受 hapticMinInterval 节流的 haptic(.selectionChanged)
//   ended/cancelled 收尾（表第 9 行）：armed [endMarquee]；dragging [endMarquee, releaseScroll]；
//   autoScrolling [stopAutoScroll, endMarquee, releaseScroll]；收尾后状态 .ending，下一事件先复位 idle。
// 异常输入（非有限 dx/dy/now/触点）不走 ending，直接安全复位 idle（卡内附加要求）。

import XCTest
@testable import PhotoDeskCore

final class SelectionGestureMachineTests: XCTestCase {

    // MARK: - helpers

    private var defaultConfig: SelectionGestureConfig { SelectionGestureConfig() }

    private func press(_ machine: inout SelectionGestureMachine,
                       id: String = "a",
                       x: Double = 100, y: Double = 200,
                       at now: TimeInterval = 0) -> [SelectionGestureEffect] {
        machine.handle(.touchDown(point: CGPoint(x: x, y: y), hitID: id), now: now)
    }

    private func arm(_ machine: inout SelectionGestureMachine,
                     id: String = "a",
                     holdAt: TimeInterval = 0.28) -> [SelectionGestureEffect] {
        press(&machine, id: id, at: 0)
        return machine.handle(.holdElapsed, now: holdAt)
    }

    // MARK: - 状态表第 1 行：idle + touchDown → pressing

    func testRow1IdleTouchDownEntersPressingAndRecordsPressPoint() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        let effects = press(&machine, id: "a", x: 37, y: 53, at: 0)
        XCTAssertTrue(effects.isEmpty, "按下本身不应产生副作用")
        XCTAssertEqual(machine.state, .pressing)
        XCTAssertEqual(machine.pressPoint, CGPoint(x: 37, y: 53), "G3：锚点必须是真实按下点")
    }

    func testTouchDownOnGapIsIgnored() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        let effects = machine.handle(.touchDown(point: CGPoint(x: 1, y: 1), hitID: nil), now: 0)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(machine.state, .idle, "空白处按下不进入 pressing（与现网 indexPathForItem 门槛一致）")
        XCTAssertNil(machine.pressPoint)
    }

    // MARK: - 状态表第 2 行：pressing + holdElapsed → armed

    func testRow2HoldElapsedArmsWithHapticEnterAndZeroSizeMarquee() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        let effects = arm(&machine, id: "a", holdAt: 0.28)
        XCTAssertEqual(effects, [.haptic(.impactLight),
                                 .enterSelection(anchorID: "a"),
                                 .beginMarquee])
        XCTAssertEqual(machine.state, .armed)
    }

    func testHoldElapsedTooEarlyIsIgnored() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        let effects = machine.handle(.holdElapsed, now: 0.1)
        XCTAssertTrue(effects.isEmpty, "0.1s < longPressDuration 不得进入 armed")
        XCTAssertEqual(machine.state, .pressing)
    }

    func testHoldElapsedAfterMovementBeyondAllowableIsIgnored() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        // 累计 (7,6)：距离 9.22 > allowableMovement=8 → 长按失效；方向未决（7≯7.2 且 6≯8.4）→ 仍 pressing
        _ = machine.handle(.moved(dx: 7, dy: 6), now: 0.1)
        XCTAssertEqual(machine.state, .pressing)
        let effects = machine.handle(.holdElapsed, now: 0.5)
        XCTAssertTrue(effects.isEmpty, "移动超出 8pt 后长按死亡，holdElapsed 不得再进入 armed")
        XCTAssertEqual(machine.state, .pressing)
    }

    func testDiagonalUndecidedStaysPressing() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        let effects = machine.handle(.moved(dx: 4, dy: 4), now: 0.1)
        XCTAssertTrue(effects.isEmpty, "对角未决且距离 <8pt：保持 pressing，长按仍有效")
        XCTAssertEqual(machine.state, .pressing)
    }

    // MARK: - 状态表第 3 行：pressing + moved 横向占优 ≥8pt → dragging（必要时先进入多选）

    func testRow3HorizontalLockDuringPressingEntersSelectionWhenNotInMode() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        machine.isSelectionModeActive = false
        press(&machine, at: 0)
        let effects = machine.handle(.moved(dx: 9, dy: 0), now: 0.1)
        XCTAssertEqual(effects, [.enterSelection(anchorID: "a"), .beginMarquee])
        XCTAssertEqual(machine.state, .dragging)
    }

    func testRow3HorizontalLockSkipsEnterSelectionWhenAlreadyInMode() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        machine.isSelectionModeActive = true
        press(&machine, at: 0)
        let effects = machine.handle(.moved(dx: 9, dy: 0), now: 0.1)
        XCTAssertEqual(effects, [.beginMarquee], "已在多选模式不得重复 enterSelection")
        XCTAssertEqual(machine.state, .dragging)
    }

    // MARK: - 状态表第 4 行：pressing + moved 纵向占优 → idle（失败）+ 交还滚动

    func testRow4VerticalDragDuringPressingFailsToIdleAndReleasesScroll() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        let effects = machine.handle(.moved(dx: 0, dy: 9), now: 0.1)
        XCTAssertEqual(effects, [.releaseScroll], "纵向让位滚动（G2 方向锁）")
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - 状态表第 5 行：pressing + ended < 0.28s → idle（交给 tap）

    func testRow5ShortPressEndedHandsOffToTap() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        let effects = machine.handle(.ended, now: 0.27)
        XCTAssertTrue(effects.isEmpty, "短按不得进入多选（交给 tap 打开查看器）")
        XCTAssertEqual(machine.state, .idle)
    }

    /// 卡内附加 1：长按 0.27s 抬手 → 不进入多选（交给 tap）
    func testLongPress027sThenReleaseDoesNotEnterSelection() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        // holdElapsed 尚未发出（0.27 < 0.28），直接抬手
        let effects = machine.handle(.ended, now: 0.27)
        XCTAssertFalse(effects.contains(.enterSelection(anchorID: "a")))
        XCTAssertTrue(effects.filter { if case .haptic = $0 { return true } else { return false } }.isEmpty)
        XCTAssertEqual(machine.state, .idle)
    }

    /// 0.28s 内抬起但已超时长按阈值边界（ended 恰在 0.28 之前一刻）以外：≥0.28 抬手按长按进入
    func testPressingEndedAfterLongPressThresholdEntersSelectionOnRelease() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        // holdElapsed 因计时器延迟未到，0.4s 抬手：原生语义仍应进入多选并选中锚点
        let effects = machine.handle(.ended, now: 0.4)
        XCTAssertEqual(effects, [.haptic(.impactLight), .enterSelection(anchorID: "a")])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - 状态表第 6 行：armed + moved（横向占优 ≥ activationDistance）→ dragging

    func testRow6ArmedHorizontalDragBeginsMarquee() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        let effects = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        XCTAssertEqual(effects, [.updateMarquee], "框选开始：首帧 updateMarquee（0.29-0.28 < 0.06 无触觉）")
        XCTAssertEqual(machine.state, .dragging)
    }

    func testArmedBelowActivationDistanceStaysArmed() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        let effects = machine.handle(.moved(dx: 5, dy: 0), now: 0.29)
        XCTAssertTrue(effects.isEmpty, "累计 5pt < activationDistance=6 不得开始拖框")
        XCTAssertEqual(machine.state, .armed)
    }

    /// 卡内附加 2：长按后纵向拖 → 仍 armed 不拖框，收到 scrollStarted 后回 idle
    func testArmedVerticalDragStaysArmedUntilScrollStarted() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        let effects = machine.handle(.moved(dx: 0, dy: 20), now: 0.35)
        XCTAssertTrue(effects.isEmpty, "armed 纵向拖不得拖框（让位滚动）")
        XCTAssertEqual(machine.state, .armed)
        let scroll = machine.handle(.scrollStarted, now: 0.4)
        XCTAssertEqual(scroll, [.endMarquee], "滚动接管：隐藏 0 尺寸选框（选中集保留，App 侧语义）")
        XCTAssertEqual(machine.state, .idle)
        // 复位后可立即服务下一次手势
        let again = press(&machine, id: "b", at: 1.0)
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(machine.state, .pressing)
        XCTAssertEqual(machine.pressPoint?.x ?? -1, 100)
    }

    // MARK: - 状态表第 7 行：dragging + moved → dragging（重算命中）

    func testRow7DraggingMovedEmitsUpdateMarquee() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        let effects = machine.handle(.moved(dx: 4, dy: 2), now: 0.30)
        XCTAssertEqual(effects, [.updateMarquee], "0.30-0.28=0.02 < 0.06 无触觉")
        XCTAssertEqual(machine.state, .dragging)
    }

    // MARK: - 状态表第 8 行：dragging + 指尖进边缘区 → autoScrolling

    func testRow8DraggingEdgeEnteredStartsAutoScroll() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        let effects = machine.handle(.edgeEntered(direction: 1), now: 0.30)
        XCTAssertEqual(effects, [.startAutoScroll(direction: 1)])
        XCTAssertEqual(machine.state, .autoScrolling)
    }

    func testEdgeEnteredWithoutActiveMarqueeIsIgnored() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        let effects = machine.handle(.edgeEntered(direction: 1), now: 0.30)
        XCTAssertTrue(effects.isEmpty, "未拖框不得自动滚动")
        XCTAssertEqual(machine.state, .armed)
    }

    func testSameDirectionEdgeEnteredWhileAutoScrollingDoesNotRestart() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        _ = machine.handle(.edgeEntered(direction: 1), now: 0.30)
        let effects = machine.handle(.edgeEntered(direction: 1), now: 0.31)
        XCTAssertTrue(effects.isEmpty, "同方向重复进边缘不得重复 startAutoScroll")
        XCTAssertEqual(machine.state, .autoScrolling)
    }

    func testOppositeEdgeEnteredWhileAutoScrollingRestarts() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        _ = machine.handle(.edgeEntered(direction: 1), now: 0.30)
        let effects = machine.handle(.edgeEntered(direction: -1), now: 0.31)
        XCTAssertEqual(effects, [.startAutoScroll(direction: -1)], "反向进边缘：换向重启")
        XCTAssertEqual(machine.state, .autoScrolling)
    }

    // MARK: - 状态表第 9 行：autoScrolling + 指尖离边缘 → dragging

    func testRow9AutoScrollingEdgeExitedStopsAutoScroll() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        _ = machine.handle(.edgeEntered(direction: 1), now: 0.30)
        let effects = machine.handle(.edgeExited, now: 0.31)
        XCTAssertEqual(effects, [.stopAutoScroll])
        XCTAssertEqual(machine.state, .dragging)
    }

    /// 卡内附加 4：自动滚动进出边缘 3 次 → start/stop 配对，无泄漏
    func testAutoScrollEdgeCyclesStartStopPairedNoLeak() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        var all: [SelectionGestureEffect] = []
        for _ in 0..<3 {
            all += machine.handle(.edgeEntered(direction: 1), now: 0.30)
            all += machine.handle(.edgeExited, now: 0.31)
        }
        let starts = all.filter { if case .startAutoScroll = $0 { return true } else { return false } }
        let stops = all.filter { if case .stopAutoScroll = $0 { return true } else { return false } }
        XCTAssertEqual(starts.count, 3)
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(machine.state, .dragging)
        let finish = machine.handle(.ended, now: 0.4)
        XCTAssertEqual(finish, [.endMarquee, .releaseScroll],
                       "边缘已退出：收尾不得再发 stopAutoScroll（无泄漏）")
    }

    // MARK: - 状态表第 10 行：任意 ended/cancelled → ending → idle（收尾）

    func testRow10DraggingEndedFinishesMarqueeAndReleasesScroll() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        let effects = machine.handle(.ended, now: 0.5)
        XCTAssertEqual(effects, [.endMarquee, .releaseScroll])
        XCTAssertEqual(machine.state, .ending)
    }

    func testRow10AutoScrollingEndedStopsAutoScrollFirst() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        _ = machine.handle(.edgeEntered(direction: -1), now: 0.30)
        let effects = machine.handle(.ended, now: 0.5)
        XCTAssertEqual(effects, [.stopAutoScroll, .endMarquee, .releaseScroll])
        XCTAssertEqual(machine.state, .ending)
    }

    func testRow10ArmedEndedHidesZeroSizeMarquee() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        let effects = machine.handle(.ended, now: 0.5)
        XCTAssertEqual(effects, [.endMarquee], "armed 收尾：隐藏 0 尺寸选框（多选与锚点选中保留）")
        XCTAssertEqual(machine.state, .ending)
    }

    func testCancelledFromDraggingAlsoFinishes() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        let effects = machine.handle(.cancelled, now: 0.5)
        XCTAssertEqual(effects, [.endMarquee, .releaseScroll], "cancelled 与 ended 同收尾语义")
        XCTAssertEqual(machine.state, .ending)
    }

    /// 表第 9 行 ending → idle：.ending 收到下一事件先复位再正常处理
    func testEndingResetsToIdleOnNextEvent() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.ended, now: 0.5)
        XCTAssertEqual(machine.state, .ending)
        _ = machine.handle(.touchDown(point: CGPoint(x: 10, y: 10), hitID: "b"), now: 1.0)
        XCTAssertEqual(machine.state, .pressing, "ending 状态下新按下：先复位 idle 再进入 pressing")
        XCTAssertEqual(machine.pressPoint, CGPoint(x: 10, y: 10), "上一次手势的按下点不得泄漏")
    }

    func testIdleEndedIsNoOp() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        let effects = machine.handle(.ended, now: 0.5)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(machine.state, .idle, "无活动资源时 ended 不进入 ending 两段态")
    }

    // MARK: - 卡内附加 3：横向锁定后反向拖回起点 → 仍 dragging，效果只报状态

    func testHorizontalLockThenReverseBackShrinksViaCaller() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        machine.isSelectionModeActive = true
        press(&machine, at: 0)
        _ = machine.handle(.moved(dx: 10, dy: 0), now: 0.1)
        XCTAssertEqual(machine.state, .dragging)
        let reverse = machine.handle(.moved(dx: -10, dy: 0), now: 0.2)
        XCTAssertTrue(reverse.contains(.updateMarquee), "反向拖仍逐帧上报，命中集合收缩由调用方计算")
        XCTAssertEqual(machine.state, .dragging, "方向锁后反向不得退出 dragging")
    }

    // MARK: - 卡内附加 5：非有限 dt/dx/dy → 安全回 idle

    func testNonFiniteMovedSafelyResetsToIdle() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        let effects = machine.handle(.moved(dx: .nan, dy: 0), now: 0.30)
        XCTAssertEqual(effects, [.endMarquee, .releaseScroll], "NaN 输入按收尾处理，绝不污染 contentOffset/状态")
        XCTAssertEqual(machine.state, .idle, "安全路径直接回 idle（不走 ending 两段）")
    }

    func testNonFiniteNowSafelyResetsToIdle() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29)
        let effects = machine.handle(.moved(dx: 1, dy: 0), now: .infinity)
        XCTAssertEqual(effects, [.endMarquee, .releaseScroll])
        XCTAssertEqual(machine.state, .idle)
    }

    func testNonFiniteTouchDownPointIsRejected() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        let effects = machine.handle(.touchDown(point: CGPoint(x: .nan, y: 0), hitID: "a"), now: 0)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(machine.state, .idle, "非有限触点不得进入 pressing")
        XCTAssertNil(machine.pressPoint)
    }

    func testNonFiniteMovedInIdleIsNoOp() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        let effects = machine.handle(.moved(dx: .nan, dy: 0), now: 0.1)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - scrollStarted 其余状态

    func testScrollStartedDuringPressingAbandonsPress() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        press(&machine, at: 0)
        let effects = machine.handle(.scrollStarted, now: 0.1)
        XCTAssertTrue(effects.isEmpty, "pressing 无资源可收尾")
        XCTAssertEqual(machine.state, .idle)
    }

    func testScrollStartedDuringDraggingFinishesMarquee() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        machine.isSelectionModeActive = true
        press(&machine, at: 0)
        _ = machine.handle(.moved(dx: 9, dy: 0), now: 0.1)
        let effects = machine.handle(.scrollStarted, now: 0.2)
        XCTAssertEqual(effects, [.endMarquee, .releaseScroll])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - 触觉节流（hapticMinInterval）

    func testHapticThrottledByMinInterval() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine)                                   // haptic@0.28（impactLight）
        _ = machine.handle(.moved(dx: 6, dy: 0), now: 0.29) // 距上一次 0.01 → 无触觉
        let m1 = machine.handle(.moved(dx: 2, dy: 0), now: 0.35)  // 0.07 ≥ 0.06 → 触觉
        XCTAssertEqual(m1, [.updateMarquee, .haptic(.selectionChanged)])
        let m2 = machine.handle(.moved(dx: 2, dy: 0), now: 0.38)  // 0.03 < 0.06 → 无触觉
        XCTAssertEqual(m2, [.updateMarquee])
        let m3 = machine.handle(.moved(dx: 2, dy: 0), now: 0.45)  // 0.10 ≥ 0.06 → 触觉
        XCTAssertEqual(m3, [.updateMarquee, .haptic(.selectionChanged)])
    }

    // MARK: - 配置默认值锁定（docs/32 §2.2）

    func testConfigDefaultsMatchSpec() {
        let config = SelectionGestureConfig()
        XCTAssertEqual(config.longPressDuration, 0.28)
        XCTAssertEqual(config.allowableMovement, 8)
        XCTAssertEqual(config.directionLockDistance, 8)
        XCTAssertEqual(config.horizontalRatio, 1.2)
        XCTAssertEqual(config.activationDistance, 6)
        XCTAssertEqual(config.hapticMinInterval, 0.06)
    }

    // MARK: - 跨手势状态隔离

    func testNewGestureStartsCleanAfterFinish() {
        var machine = SelectionGestureMachine(config: defaultConfig)
        _ = arm(&machine, id: "a")
        _ = machine.handle(.moved(dx: 50, dy: 0), now: 0.4)
        _ = machine.handle(.ended, now: 0.5)
        // 新手势：立刻纵向拖必须按新累计判定（旧 (50,0) 若泄漏会判成横向）
        _ = machine.handle(.touchDown(point: CGPoint(x: 5, y: 5), hitID: "b"), now: 1.0)
        let effects = machine.handle(.moved(dx: 0, dy: 9), now: 1.1)
        XCTAssertEqual(effects, [.releaseScroll], "旧手势累计位移不得污染新手势方向判定")
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - 自定义配置可注入（阈值只从 config 取）

    func testCustomConfigThresholdsAreHonored() {
        var config = SelectionGestureConfig()
        config.longPressDuration = 0.5
        config.directionLockDistance = 20
        var machine = SelectionGestureMachine(config: config)
        press(&machine, at: 0)
        _ = machine.handle(.moved(dx: 12, dy: 0), now: 0.1)
        XCTAssertEqual(machine.state, .pressing, "12pt < 自定义 directionLockDistance=20 不得锁定")
        _ = machine.handle(.holdElapsed, now: 0.49)
        XCTAssertEqual(machine.state, .pressing, "0.49 < 自定义 longPressDuration=0.5 不得 armed")
        let armed = machine.handle(.holdElapsed, now: 0.5)
        XCTAssertEqual(armed, [.haptic(.impactLight), .enterSelection(anchorID: "a"), .beginMarquee])
        XCTAssertEqual(machine.state, .armed)
    }
}
