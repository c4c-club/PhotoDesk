# M18 全新审查（自动生成，只读扫描）

- generatedAt: 2026-11-15T16:08:52Z
- root: C:/Users/RuiZh/Desktop/photo_manager
- version: 1.6.0 (7)，deploymentTarget: iOS 16.0
- releaseDirs: 1.4.0, 1.5.0
- blocking failures: 3 / 29

| 编号 | 级别 | 检查 | 期望 | 结果 | 命中数 |
|---|---|---|---|---|---|
| B01 | BLOCKING | PhotoDeskCore 零 Apple 依赖：只允许 import Foundation（AGENTS 红线 2） | empty | PASS | 0 |
| B02 | BLOCKING | App 不得出现 iOS 17+ API（iOS 16 基线，禁 @Observable/SwiftData/ContentUnavailableView/scrollTargetBehavior/scrollPosition） | empty | PASS | 0 |
| B03 | BLOCKING | App 不得出现 minimumNumberOfTouches = 2（不用双指规则，docs/38 §1.2 #4） | empty | PASS | 0 |
| B04 | BLOCKING | Feature 层不得直接引用 PHAsset（AGENTS 架构规则 1） | empty | PASS | 0 |
| B05 | BLOCKING | 红线 1 文案：不得出现「彻底删除/永久删除」祈使/陈述句（否定句与疑问句视为合规引用） | empty | PASS | 0 |
| B06 | BLOCKING | App 层不得有活跃框选符号（marquee*/MarqueeOverlayView/Marquee-Overlay/lastMarqueeRect/hitTest(rectInContent:)/HitRect，docs/38 §1.2 #1） | empty | FAIL | 45 |
| B07 | BLOCKING | Core 层不得有框选调用点（MarqueeSelectionPolicy.mode/resolved、MarqueeHitResolver.hit、GridHitRegion.hitIDs/mergedSelection 的调用归零） | empty | PASS | 0 |
| B08 | BLOCKING | 状态机 effect 不得再用旧名 beginMarquee/updateMarquee/endMarquee（T04 改名 beginTrail/updateTrail/endTrail） | empty | FAIL | 18 |
| B09 | BLOCKING | App 禁止 try! / as!（AGENTS 代码规范） | empty | PASS | 0 |
| B10 | BLOCKING | UI/单测不得再断言框选 overlay/矩形/整行带/双指滚动（冻结用例契约必须迁移） | empty | FAIL | 39 |
| P01 | PRESENT | SelectionGestureMachine 状态机存在（复用状态表） | present | PASS | 1 |
| P02 | PRESENT | SlideSelectTrail.swift 存在（路径事务，T02 产出） | present | FAIL | 0 |
| P03 | PRESENT | TrailHitResolver.swift 存在（线段扫掠命中，T03 产出） | present | FAIL | 0 |
| P04 | PRESENT | GridCellFrame.swift 存在（CellFrame 从 marquee 命名中抽出，T03 产出） | present | FAIL | 0 |
| P05 | PRESENT | App 控制器接线 trailHitProvider（线段命中注入） | present | FAIL | 0 |
| P06 | PRESENT | GridHitTester.hitTestLine(from:to:) 存在（真实 attributes 线段扫描） | present | FAIL | 0 |
| P07 | PRESENT | App 增量落地 applySelectionDelta 存在 | present | FAIL | 0 |
| P08 | PRESENT | Core SelectionState.applyDelta(add:remove:) 存在（事务输出承担者） | present | PASS | 1 |
| P09 | PRESENT | SlideSelectTrailTests 存在（T02 红/绿单测） | present | FAIL | 0 |
| P10 | PRESENT | TrailHitResolverTests 存在（T03 红/绿单测） | present | FAIL | 0 |
| P11 | PRESENT | SlideSelectTrailUITests.swift 存在（T08 改名重写产物） | present | FAIL | 0 |
| P12 | PRESENT | 状态机新 effect 名 beginTrail/updateTrail/endTrail 就位（T04 产出） | present | FAIL | 0 |
| P13 | PRESENT | 方向锁与滚动让位保留（releaseScroll/scrollLocked，单指纵向滚动共存） | present | PASS | 18 |
| I01 | INFO | project.yml 版本号（T10 目标 1.7.0 (8)） | present | PASS | 2 |
| I02 | INFO | 部署目标 IPHONEOS_DEPLOYMENT_TARGET = 16.0 | present | PASS | 1 |
| I03 | INFO | CI 产物名 PhotoDesk-Simulator-app-zip / PhotoDesk-unsigned-ipa | present | PASS | 2 |
| I04 | INFO | CI minos=16.0 校验链（MINOS_VERSION + otool LC_BUILD_VERSION） | present | PASS | 11 |
| I05 | INFO | Release 归档目录 artifacts/release/1.7.0（T10 前允许缺失） | present | FAIL | 0 |
| I06 | INFO | DEBUG 取证字段（debugAutoScrollTicks/debugHapticCount/debugTouchDownHitID） | present | PASS | 7 |

## 命中明细

### B06 - App 层不得有活跃框选符号（marquee*/MarqueeOverlayView/Marquee-Overlay/lastMarqueeRect/hitTest(rectInContent:)/HitRect，docs/38 §1.2 #1） [FAIL]
- PhotoDesk/App/PhotoDeskApp.swift:23 - // 且按字母序先于按 3 列几何校准的选择类套件（Marquee/PageRegression/Stability）执行，
- PhotoDesk/Core/Photos/UITestDatedPhotoSeeder.swift:11 - // Marquee 套件 10/14 崩。基础种子与深种子同形 40/批分批；抛错按占位符回查已落库日期去重。
- PhotoDesk/Features/Library/GridHitTester.swift:44 - func hitTest(rectInContent rawRect: CGRect) -> Set<IndexPath> {
- PhotoDesk/Features/Library/LibrarySelectionController.swift:8 - //   marqueePan（单指）→ moved(dx:dy:) / ended / cancelled；edgeEntered/edgeExited 由
- PhotoDesk/Features/Library/LibrarySelectionController.swift:11 - // 效果执行：enterSelection → VC 进多选并选锚点；beginMarquee / endMarquee 与 isScrollEnabled
- PhotoDesk/Features/Library/LibrarySelectionController.swift:13 - // updateMarquee → 重算命中（命中集合变化才是 G6 触觉闸门）；startAutoScroll / stopAutoScroll →
- PhotoDesk/Features/Library/LibrarySelectionController.swift:23 - static var lastMarqueeRect: CGRect?
- PhotoDesk/Features/Library/LibrarySelectionController.swift:43 - weak var overlayView: MarqueeOverlayView?
- PhotoDesk/Features/Library/LibrarySelectionController.swift:45 - var onMarqueeRectChanged: ((CGRect?) -> Void) = { _ in }
- PhotoDesk/Features/Library/LibrarySelectionController.swift:52 - private(set) var mode: MarqueeMode = .select
- PhotoDesk/Features/Library/LibrarySelectionController.swift:53 - /// 最近一次 beginMarquee 时刻的模式快照（UI 测试取证：横幅刷新滞后时仍可读到按下帧真值）。
- PhotoDesk/Features/Library/LibrarySelectionController.swift:65 - /// G6 闸门：updateMarquee 帧命中集合确有变化时才放行机器的 selectionChanged 触觉。
- PhotoDesk/Features/Library/LibrarySelectionController.swift:114 - let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMarqueePan(_:)))
- PhotoDesk/Features/Library/LibrarySelectionController.swift:123 - marqueePan = pan
- PhotoDesk/Features/Library/LibrarySelectionController.swift:130 - private(set) var marqueePan: UIPanGestureRecognizer!
- PhotoDesk/Features/Library/LibrarySelectionController.swift:158 - mode = MarqueeSelectionPolicy.mode(baseIDs: baseIDs, anchorID: hitID)
- PhotoDesk/Features/Library/LibrarySelectionController.swift:187 - @objc private func handleMarqueePan(_ gesture: UIPanGestureRecognizer) {
- PhotoDesk/Features/Library/LibrarySelectionController.swift:220 - onMarqueeRectChanged(nil)
- PhotoDesk/Features/Library/LibrarySelectionController.swift:272 - case .beginMarquee:
- PhotoDesk/Features/Library/LibrarySelectionController.swift:274 - // armed 即禁滚动（docs/32 §2.3）；endMarquee/releaseScroll 成对恢复
- PhotoDesk/Features/Library/LibrarySelectionController.swift:280 - let beginRect = currentMarqueeRect()
- PhotoDesk/Features/Library/LibrarySelectionController.swift:282 - onMarqueeRectChanged(beginRect)
- PhotoDesk/Features/Library/LibrarySelectionController.swift:283 - case .updateMarquee:
- PhotoDesk/Features/Library/LibrarySelectionController.swift:285 - let rect = currentMarqueeRect()
- PhotoDesk/Features/Library/LibrarySelectionController.swift:287 - onMarqueeRectChanged(rect)
- PhotoDesk/Features/Library/LibrarySelectionController.swift:288 - case .endMarquee:
- PhotoDesk/Features/Library/LibrarySelectionController.swift:291 - onMarqueeRectChanged(nil)
- PhotoDesk/Features/Library/LibrarySelectionController.swift:295 - if marqueePan.state == .changed || marqueePan.state == .began {
- PhotoDesk/Features/Library/LibrarySelectionController.swift:296 - marqueePan.state = .failed
- PhotoDesk/Features/Library/LibrarySelectionController.swift:373 - ViewerTrace.log("marquee.apply-window skip=\(applyWindowSkips) hold-last-target")
- PhotoDesk/Features/Library/LibrarySelectionController.swift:376 - ViewerTrace.log("marquee.apply-window timeout → release with empty hit")
- PhotoDesk/Features/Library/LibrarySelectionController.swift:379 - let target = MarqueeSelectionPolicy.resolved(base: baseIDs,
- PhotoDesk/Features/Library/LibrarySelectionController.swift:391 - private func currentMarqueeRect() -> CGRect? {
- PhotoDesk/Features/Library/LibraryViewController.swift:798 - for path in tester.hitTest(rectInContent: rect) {
- PhotoDesk/Features/Library/LibraryViewController.swift:807 - let marqueeOverlay = MarqueeOverlayView()
- PhotoDesk/Features/Library/LibraryViewController.swift:808 - view.insertSubview(marqueeOverlay, aboveSubview: collectionView)
- PhotoDesk/Features/Library/LibraryViewController.swift:809 - controller.overlayView = marqueeOverlay
- PhotoDesk/Features/Library/LibraryViewController.swift:810 - controller.onMarqueeRectChanged = { [weak self] rect in
- PhotoDesk/Features/Library/LibraryViewController.swift:813 - LibrarySelectionDebugState.lastMarqueeRect = rect
- PhotoDesk/Features/Library/LibraryViewController.swift:1969 - || gestureRecognizer === selectionController.marqueePan else { return true }
- PhotoDesk/Features/Library/LibraryViewController.swift:1973 - if gestureRecognizer === selectionController.marqueePan,
- PhotoDesk/Features/Library/LibraryViewController.swift:1985 - || gestureRecognizer === $0.marqueePan
- PhotoDesk/Features/Library/LibraryViewController.swift:1988 - || other === $0.marqueePan
- PhotoDesk/Features/Library/MarqueeOverlayView.swift:7 - final class MarqueeOverlayView: UIView {
- PhotoDesk/Features/Library/MarqueeOverlayView.swift:19 - accessibilityIdentifier = "Marquee-Overlay"

### B08 - 状态机 effect 不得再用旧名 beginMarquee/updateMarquee/endMarquee（T04 改名 beginTrail/updateTrail/endTrail） [FAIL]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:12 - //   副作用 [haptic(.impactLight), enterSelection(anchorID:), beginMarquee]（表第 2 行，0 尺寸选框）。
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:19 - // - dragging/autoScrolling moved → updateMarquee + haptic(.selectionChanged)（受 hapticMinInterval
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:23 - // - ended/cancelled：armed/dragging/autoScrolling 收尾（stopAutoScroll → endMarquee → releaseScroll）
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:67 - case beginMarquee
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:68 - case updateMarquee
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:69 - case endMarquee
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:151 - effects.append(.beginMarquee)
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:186 - effects.append(.beginMarquee)
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:214 - var effects: [SelectionGestureEffect] = [.updateMarquee]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:233 - return [.endMarquee]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:237 - return [.endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:241 - return [.stopAutoScroll, .endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:295 - return [.endMarquee]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:299 - return [.endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:303 - return [.stopAutoScroll, .endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:314 - effects = [.endMarquee]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:316 - effects = scrollLocked ? [.endMarquee, .releaseScroll] : [.endMarquee]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:318 - effects = [.stopAutoScroll, .endMarquee, .releaseScroll]

### B10 - UI/单测不得再断言框选 overlay/矩形/整行带/双指滚动（冻结用例契约必须迁移） [FAIL]
- PhotoDeskTests/LibraryGridGeometryTests.swift:178 - let hit = tester.hitTest(rectInContent: rawRect)
- PhotoDeskTests/LibraryGridGeometryTests.swift:221 - func testMarqueeHitSelectsA3_7NotA3_6() throws {
- PhotoDeskTests/LibraryGridGeometryTests.swift:231 - let ids = Set(tester.hitTest(rectInContent: rect).map { "a\($0.section)-\($0.item)" })
- PhotoDeskTests/LibraryGridGeometryTests.swift:237 - /// docs/32 §2.4 第 8 步：缓存已热后，同一帧深位置框选 ≤ 60 次 layoutAttributesForItem 查询
- PhotoDeskTests/LibraryGridGeometryTests.swift:247 - _ = tester.hitTest(rectInContent: rect)
- PhotoDeskTests/LibraryGridGeometryTests.swift:248 - _ = tester.hitTest(rectInContent: rect)
- PhotoDeskUITests/MarqueeSelectionUITests.swift:1 - // MARK: - MarqueeSelectionUITests：多选交互验收（M17 T05 重写，docs/32 §4.3，docs/31 §2.1/§2.3）——
- PhotoDeskUITests/MarqueeSelectionUITests.swift:2 - // 新交互模型：长按 0.4s 进入多选并选中锚点；长按后任意方向拖 = 框选（含纵向到第 5 行 / 底缘
- PhotoDeskUITests/MarqueeSelectionUITests.swift:3 - // 自动滚动）；无长按的横向按压拖 = 框选（pressing 横向占优，表第 3 行）；纵向单指拖 = 滚动让位
- PhotoDeskUITests/MarqueeSelectionUITests.swift:10 - final class MarqueeSelectionUITests: XCTestCase {
- PhotoDeskUITests/MarqueeSelectionUITests.swift:211 - // MARK: - 长按后拖动继续框选（docs/32 §4.3）
- PhotoDeskUITests/MarqueeSelectionUITests.swift:228 - XCTFail("长按后拖到第 5 行：两次尝试均未进入框选（count=\(count)，长按未触发）")
- PhotoDeskUITests/MarqueeSelectionUITests.swift:249 - ///（纵向让位，不得被框选/双指规则劫持）。
- PhotoDeskUITests/MarqueeSelectionUITests.swift:270 - "单指滚动是滚动不是框选：计数必须不变（before=\(countBefore)）")
- PhotoDeskUITests/MarqueeSelectionUITests.swift:312 - /// 普通网格横向按压拖过行 1：横向占优 ≥8pt → 先进多选再框选整行（3 格精确）。
- PhotoDeskUITests/MarqueeSelectionUITests.swift:313 - func testHorizontalDragFromPressSelectsRow() throws {
- PhotoDeskUITests/MarqueeSelectionUITests.swift:323 - "横向按压拖必须框选行 1 的 3 格（未在多选时先进入多选）")
- PhotoDeskUITests/MarqueeSelectionUITests.swift:342 - "锚点已选 → 取消模式：矩形命中的 3 格全部取消（armed 帧 0 尺寸选框先取消锚点）")
- PhotoDeskUITests/MarqueeSelectionUITests.swift:363 - func testDiagonalMarqueeSelectsRectangle() throws {
- PhotoDeskUITests/MarqueeSelectionUITests.swift:389 - // MARK: - 全选后框选取消（docs/25 §6.5 ⑦）
- PhotoDeskUITests/MarqueeSelectionUITests.swift:391 - func testSelectAllThenMarqueeDeselects() throws {
- PhotoDeskUITests/MarqueeSelectionUITests.swift:402 - "全选后长按框选必须恰好取消 col-0 行 0-2 三格（total=\(total)）")
- PhotoDeskUITests/MarqueeSelectionUITests.swift:403 - assertAlive(app, "全选+框选取消后")
- PhotoDeskUITests/MarqueeSelectionUITests.swift:454 - // MARK: - 框选覆盖层取证（M17 T06，docs/32 §2.5）
- PhotoDeskUITests/MarqueeSelectionUITests.swift:539 - /// 框选拖动期间覆盖层必须可见：连拍帧内检测 tint 描边像素（无覆盖层 → 0 像素 → 断言红）。
- PhotoDeskUITests/MarqueeSelectionUITests.swift:542 - func testMarqueeOverlayVisible() throws {
- PhotoDeskUITests/MarqueeSelectionUITests.swift:597 - // （8→16 曾触及底缘区触发 ticks=106 自动滚动，网格滚走后框选内容错位）
- PhotoDeskUITests/MarqueeSelectionUITests.swift:607 - XCTAssertEqual(postCount, 0, "取消模式框选必须清掉锚选（count=\(postCount) banner=\(bannerAfter)）")
- PhotoDeskUITests/PageRegressionUITests.swift:234 - func testSelectionModeUsesSlidePanAndTwoFingerScrollConfig() throws {
- PhotoDeskUITests/StabilityUITests.swift:605 - // MARK: - M15 P0-3/4：矩形框选（整行带/快照恢复旧用例已删，验收在 MarqueeSelectionUITests）
- PhotoDeskUITests/StabilityUITests.swift:608 - // -uiTestingClearPosition：框选/轻点族断言依赖确定的首屏几何（首格可点、两行满格），
- PhotoDeskUITests/StabilityUITests.swift:643 - "框选应继续加选")
- PhotoDeskUITests/StabilityUITests.swift:645 - "框选矩形未覆盖首格，首格必须保持选中")
- PhotoDeskUITests/StabilityUITests.swift:648 - /// P0-4：选择模式双指滚动配置（单指已由框选 pan 独占，collectionView pan 至少 2 指）。
- PhotoDeskUITests/StabilityUITests.swift:649 - func testTwoFingerScrollInSelectionMode() throws {
- PhotoDeskUITests/StabilityUITests.swift:711 - // 选择模式下的复用驱动器是框选自动滚动本身（MonthIndexBar 在多选态 isHidden，
- PhotoDeskUITests/StabilityUITests.swift:712 - // 单指 swipe 是框选手势）：第一段拖动选中的是行 1–2 × 3 列（6 格），第二段从
- PhotoDeskUITests/StabilityUITests.swift:832 - // MARK: - S07 多选单指滑选连续选中（M13：整条替换长按框选）
- PhotoDeskUITests/ZoomStabilityUITests.swift:368 - // coordinate.tap，坐标通路已被框选 press/drag 证明可达 app）。任一通路让

### P01 - SelectionGestureMachine 状态机存在（复用状态表） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:76 - public struct SelectionGestureMachine: Sendable {

### P02 - 文件缺失（显式 FAIL）
- [文件不存在] PhotoDeskCore/Sources/PhotoDeskCore/SlideSelectTrail.swift

### P03 - 文件缺失（显式 FAIL）
- [文件不存在] PhotoDeskCore/Sources/PhotoDeskCore/TrailHitResolver.swift

### P04 - 文件缺失（显式 FAIL）
- [文件不存在] PhotoDeskCore/Sources/PhotoDeskCore/GridCellFrame.swift

### P08 - Core SelectionState.applyDelta(add:remove:) 存在（事务输出承担者） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionPolicy.swift:92 - public mutating func applyDelta(add: Set<String>, remove: Set<String>) {

### P11 - 文件缺失（显式 FAIL）
- [文件不存在] PhotoDeskUITests/SlideSelectTrailUITests.swift

### P13 - 方向锁与滚动让位保留（releaseScroll/scrollLocked，单指纵向滚动共存） [PASS]
- PhotoDesk/Features/Library/LibrarySelectionController.swift:12 - // 成对（docs/32 §2.3「进入 armed 后禁滚动」；releaseScroll 由机器在方向让位/收尾时配对补发）；
- PhotoDesk/Features/Library/LibrarySelectionController.swift:274 - // armed 即禁滚动（docs/32 §2.3）；endMarquee/releaseScroll 成对恢复
- PhotoDesk/Features/Library/LibrarySelectionController.swift:292 - case .releaseScroll:
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:15 - //   纵向占优（|dy| ≥ |dx|·horizontalRatio）→ idle + releaseScroll（让位滚动，G2）。
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:23 - // - ended/cancelled：armed/dragging/autoScrolling 收尾（stopAutoScroll → endMarquee → releaseScroll）
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:70 - case releaseScroll
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:89 - private var scrollLocked = false
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:135 - scrollLocked = false
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:181 - scrollLocked = true
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:193 - return [.releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:203 - scrollLocked = true
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:237 - return [.endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:241 - return [.stopAutoScroll, .endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:299 - return [.endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:303 - return [.stopAutoScroll, .endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:316 - effects = scrollLocked ? [.endMarquee, .releaseScroll] : [.endMarquee]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:318 - effects = [.stopAutoScroll, .endMarquee, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:334 - scrollLocked = false

### I01 - project.yml 版本号（T10 目标 1.7.0 (8)） [PASS]
- project.yml:17 - MARKETING_VERSION: "1.6.0"
- project.yml:18 - CURRENT_PROJECT_VERSION: "7"

### I02 - 部署目标 IPHONEOS_DEPLOYMENT_TARGET = 16.0 [PASS]
- project.yml:16 - IPHONEOS_DEPLOYMENT_TARGET: "16.0"

### I03 - CI 产物名 PhotoDesk-Simulator-app-zip / PhotoDesk-unsigned-ipa [PASS]
- .github/workflows/ios.yml:231 - name: PhotoDesk-Simulator-app-zip
- .github/workflows/ios.yml:237 - name: PhotoDesk-unsigned-ipa

### I04 - CI minos=16.0 校验链（MINOS_VERSION + otool LC_BUILD_VERSION） [PASS]
- .github/workflows/ios.yml:33 - MINOS_VERSION: '16.0'
- .github/workflows/ios.yml:100 - -showBuildSettings | grep "IPHONEOS_DEPLOYMENT_TARGET = $MINOS_VERSION"
- .github/workflows/ios.yml:188 - otool -l "$APP/PhotoDesk" | grep -A3 LC_BUILD_VERSION
- .github/workflows/ios.yml:189 - otool -l "$APP/PhotoDesk" | grep -A3 LC_BUILD_VERSION | grep -q "minos $MINOS_VERSION" || {
- .github/workflows/ios.yml:190 - echo "::error::LC_BUILD_VERSION minos != $MINOS_VERSION"; exit 1; }
- .github/workflows/ios.yml:217 - test "$PLIST_MINOS" = "$MINOS_VERSION" || {
- .github/workflows/ios.yml:218 - echo "::error::MinimumOSVersion != $MINOS_VERSION"; exit 1; }
- .github/workflows/ios.yml:220 - otool -l ipa-check/Payload/PhotoDesk.app/PhotoDesk | grep -A3 LC_BUILD_VERSION
- .github/workflows/ios.yml:221 - otool -l ipa-check/Payload/PhotoDesk.app/PhotoDesk | grep -A3 LC_BUILD_VERSION | grep -q "minos $MINOS_VERSION" || {
- .github/workflows/ios.yml:222 - echo "::error::ipa minos != $MINOS_VERSION"; exit 1; }
- .github/workflows/ios.yml:226 - echo "[OK] 未签名 IPA 校验通过（Payload / MinimumOSVersion=$MINOS_VERSION / minos=$MINOS_VERSION / 未签名）"

### I05 - 文件缺失（显式 FAIL）
- [文件不存在] artifacts/release/1.7.0

### I06 - DEBUG 取证字段（debugAutoScrollTicks/debugHapticCount/debugTouchDownHitID） [PASS]
- PhotoDesk/Features/Library/LibrarySelectionController.swift:57 - private(set) var debugTouchDownHitID: String = "-"
- PhotoDesk/Features/Library/LibrarySelectionController.swift:134 - private(set) var debugHapticCount = 0
- PhotoDesk/Features/Library/LibrarySelectionController.swift:136 - private(set) var debugAutoScrollTicks = 0
- PhotoDesk/Features/Library/LibrarySelectionController.swift:162 - debugTouchDownHitID = hitID
- PhotoDesk/Features/Library/LibrarySelectionController.swift:303 - debugHapticCount += 1
- PhotoDesk/Features/Library/LibrarySelectionController.swift:312 - debugHapticCount += 1
- PhotoDesk/Features/Library/LibrarySelectionController.swift:430 - debugAutoScrollTicks += 1
