# M18 全新审查（自动生成，只读扫描）

- generatedAt: 2026-11-16T15:10:40Z
- root: C:/Users/RuiZh/Desktop/photo_manager
- version: 1.6.0 (7)，deploymentTarget: iOS 16.0
- releaseDirs: 1.4.0, 1.5.0
- blocking failures: 1 / 29

| 编号 | 级别 | 检查 | 期望 | 结果 | 命中数 |
|---|---|---|---|---|---|
| B01 | BLOCKING | PhotoDeskCore 零 Apple 依赖：只允许 import Foundation（AGENTS 红线 2） | empty | PASS | 0 |
| B02 | BLOCKING | App 不得出现 iOS 17+ API（iOS 16 基线，禁 @Observable/SwiftData/ContentUnavailableView/scrollTargetBehavior/scrollPosition） | empty | PASS | 0 |
| B03 | BLOCKING | App 不得出现 minimumNumberOfTouches = 2（不用双指规则，docs/38 §1.2 #4） | empty | PASS | 0 |
| B04 | BLOCKING | Feature 层不得直接引用 PHAsset（AGENTS 架构规则 1） | empty | PASS | 0 |
| B05 | BLOCKING | 红线 1 文案：不得出现「彻底删除/永久删除」祈使/陈述句（否定句与疑问句视为合规引用） | empty | PASS | 0 |
| B06 | BLOCKING | App 层不得有活跃框选符号（marquee*/MarqueeOverlayView/Marquee-Overlay/lastMarqueeRect/hitTest(rectInContent:)/HitRect，docs/38 §1.2 #1） | empty | PASS | 0 |
| B07 | BLOCKING | Core 层不得有框选调用点（MarqueeSelectionPolicy.mode/resolved、MarqueeHitResolver.hit、GridHitRegion.hitIDs/mergedSelection 的调用归零） | empty | PASS | 0 |
| B08 | BLOCKING | 状态机 effect 不得再用旧名 beginMarquee/updateMarquee/endMarquee（T04 改名 beginTrail/updateTrail/endTrail） | empty | PASS | 0 |
| B09 | BLOCKING | App 禁止 try! / as!（AGENTS 代码规范） | empty | PASS | 0 |
| B10 | BLOCKING | UI/单测不得再断言框选 overlay/矩形/整行带/双指滚动（冻结用例契约必须迁移） | empty | FAIL | 33 |
| P01 | PRESENT | SelectionGestureMachine 状态机存在（复用状态表） | present | PASS | 1 |
| P02 | PRESENT | SlideSelectTrail.swift 存在（路径事务，T02 产出） | present | PASS | 1 |
| P03 | PRESENT | TrailHitResolver.swift 存在（线段扫掠命中，T03 产出） | present | PASS | 1 |
| P04 | PRESENT | GridCellFrame.swift 存在（CellFrame 从 marquee 命名中抽出，T03 产出） | present | PASS | 1 |
| P05 | PRESENT | App 控制器接线 trailHitProvider（线段命中注入） | present | PASS | 4 |
| P06 | PRESENT | GridHitTester.hitTestLine(from:to:) 存在（真实 attributes 线段扫描） | present | PASS | 1 |
| P07 | PRESENT | App 增量落地 applySelectionDelta 存在 | present | PASS | 5 |
| P08 | PRESENT | Core SelectionState.applyDelta(add:remove:) 存在（事务输出承担者） | present | PASS | 1 |
| P09 | PRESENT | SlideSelectTrailTests 存在（T02 红/绿单测） | present | PASS | 1 |
| P10 | PRESENT | TrailHitResolverTests 存在（T03 红/绿单测） | present | PASS | 1 |
| P11 | PRESENT | SlideSelectTrailUITests.swift 存在（T08 改名重写产物） | present | FAIL | 0 |
| P12 | PRESENT | 状态机新 effect 名 beginTrail/updateTrail/endTrail 就位（T04 产出） | present | PASS | 18 |
| P13 | PRESENT | 方向锁与滚动让位保留（releaseScroll/scrollLocked，单指纵向滚动共存） | present | PASS | 18 |
| I01 | INFO | project.yml 版本号（T10 目标 1.7.0 (8)） | present | PASS | 2 |
| I02 | INFO | 部署目标 IPHONEOS_DEPLOYMENT_TARGET = 16.0 | present | PASS | 1 |
| I03 | INFO | CI 产物名 PhotoDesk-Simulator-app-zip / PhotoDesk-unsigned-ipa | present | PASS | 2 |
| I04 | INFO | CI minos=16.0 校验链（MINOS_VERSION + otool LC_BUILD_VERSION） | present | PASS | 11 |
| I05 | INFO | Release 归档目录 artifacts/release/1.7.0（T10 前允许缺失） | present | FAIL | 0 |
| I06 | INFO | DEBUG 取证字段（debugAutoScrollTicks/debugHapticCount/debugTouchDownHitID） | present | PASS | 7 |

## 命中明细

### B10 - UI/单测不得再断言框选 overlay/矩形/整行带/双指滚动（冻结用例契约必须迁移） [FAIL]
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

### P02 - SlideSelectTrail.swift 存在（路径事务，T02 产出） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/SlideSelectTrail.swift:0 - [文件存在]

### P03 - TrailHitResolver.swift 存在（线段扫掠命中，T03 产出） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/TrailHitResolver.swift:0 - [文件存在]

### P04 - GridCellFrame.swift 存在（CellFrame 从 marquee 命名中抽出，T03 产出） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/GridCellFrame.swift:0 - [文件存在]

### P05 - App 控制器接线 trailHitProvider（线段命中注入） [PASS]
- PhotoDesk/Features/Library/LibrarySelectionController.swift:14 - // updateTrail → trailHitProvider 线段有序命中 + SlideSelectTrail 路径事务净 delta
- PhotoDesk/Features/Library/LibrarySelectionController.swift:31 - var trailHitProvider: (CGPoint, CGPoint) -> [String] = { _, _ in [] }
- PhotoDesk/Features/Library/LibrarySelectionController.swift:374 - let orderedIDs = trailHitProvider(from, to)
- PhotoDesk/Features/Library/LibraryViewController.swift:796 - controller.trailHitProvider = { [weak self] from, to in

### P06 - GridHitTester.hitTestLine(from:to:) 存在（真实 attributes 线段扫描） [PASS]
- PhotoDesk/Features/Library/GridHitTester.swift:149 - func hitTestLine(from: CGPoint, to: CGPoint) -> [IndexPath] {

### P07 - App 增量落地 applySelectionDelta 存在 [PASS]
- PhotoDesk/Features/Library/LibrarySelectionController.swift:18 - // 选中集唯一写入口：applySelectionDelta → VC applySelectionChanges（SelectionState.applyDelta）。
- PhotoDesk/Features/Library/LibrarySelectionController.swift:33 - var applySelectionDelta: (Set<String>, Set<String>) -> Void = { _, _ in }
- PhotoDesk/Features/Library/LibrarySelectionController.swift:291 - applySelectionDelta(delta.add, delta.remove)
- PhotoDesk/Features/Library/LibrarySelectionController.swift:385 - applySelectionDelta(delta.add, delta.remove)
- PhotoDesk/Features/Library/LibraryViewController.swift:788 - controller.applySelectionDelta = { [weak self] add, remove in

### P08 - Core SelectionState.applyDelta(add:remove:) 存在（事务输出承担者） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionPolicy.swift:94 - public mutating func applyDelta(add: Set<String>, remove: Set<String>) {

### P09 - SlideSelectTrailTests 存在（T02 红/绿单测） [PASS]
- PhotoDeskCore/Tests/PhotoDeskCoreTests/SlideSelectTrailTests.swift:10 - final class SlideSelectTrailTests: XCTestCase {

### P10 - TrailHitResolverTests 存在（T03 红/绿单测） [PASS]
- PhotoDeskCore/Tests/PhotoDeskCoreTests/TrailHitResolverTests.swift:11 - final class TrailHitResolverTests: XCTestCase {

### P11 - 文件缺失（显式 FAIL）
- [文件不存在] PhotoDeskUITests/SlideSelectTrailUITests.swift

### P12 - 状态机新 effect 名 beginTrail/updateTrail/endTrail 就位（T04 产出） [PASS]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:12 - //   副作用 [haptic(.impactLight), enterSelection(anchorID:), beginTrail]（表第 2 行，轨迹事务开启）。
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:19 - // - dragging/autoScrolling moved → updateTrail + haptic(.selectionChanged)（受 hapticMinInterval
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:23 - // - ended/cancelled：armed/dragging/autoScrolling 收尾（stopAutoScroll → endTrail → releaseScroll）
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:67 - case beginTrail
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:68 - case updateTrail
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:69 - case endTrail
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:151 - effects.append(.beginTrail)
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:186 - effects.append(.beginTrail)
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:214 - var effects: [SelectionGestureEffect] = [.updateTrail]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:233 - return [.endTrail]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:237 - return [.endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:241 - return [.stopAutoScroll, .endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:295 - return [.endTrail]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:299 - return [.endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:303 - return [.stopAutoScroll, .endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:314 - effects = [.endTrail]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:316 - effects = scrollLocked ? [.endTrail, .releaseScroll] : [.endTrail]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:318 - effects = [.stopAutoScroll, .endTrail, .releaseScroll]

### P13 - 方向锁与滚动让位保留（releaseScroll/scrollLocked，单指纵向滚动共存） [PASS]
- PhotoDesk/Features/Library/LibrarySelectionController.swift:13 - // 成对（docs/32 §2.3「进入 armed 后禁滚动」；releaseScroll 由机器在方向让位/收尾时配对补发）；
- PhotoDesk/Features/Library/LibrarySelectionController.swift:273 - // armed 即禁滚动（docs/32 §2.3）；endTrail/releaseScroll 成对恢复
- PhotoDesk/Features/Library/LibrarySelectionController.swift:304 - case .releaseScroll:
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:15 - //   纵向占优（|dy| ≥ |dx|·horizontalRatio）→ idle + releaseScroll（让位滚动，G2）。
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:23 - // - ended/cancelled：armed/dragging/autoScrolling 收尾（stopAutoScroll → endTrail → releaseScroll）
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:70 - case releaseScroll
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:89 - private var scrollLocked = false
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:135 - scrollLocked = false
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:181 - scrollLocked = true
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:193 - return [.releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:203 - scrollLocked = true
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:237 - return [.endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:241 - return [.stopAutoScroll, .endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:299 - return [.endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:303 - return [.stopAutoScroll, .endTrail, .releaseScroll]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:316 - effects = scrollLocked ? [.endTrail, .releaseScroll] : [.endTrail]
- PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift:318 - effects = [.stopAutoScroll, .endTrail, .releaseScroll]
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
- PhotoDesk/Features/Library/LibrarySelectionController.swift:55 - private(set) var debugTouchDownHitID: String = "-"
- PhotoDesk/Features/Library/LibrarySelectionController.swift:129 - private(set) var debugHapticCount = 0
- PhotoDesk/Features/Library/LibrarySelectionController.swift:131 - private(set) var debugAutoScrollTicks = 0
- PhotoDesk/Features/Library/LibrarySelectionController.swift:160 - debugTouchDownHitID = hitID
- PhotoDesk/Features/Library/LibrarySelectionController.swift:315 - debugHapticCount += 1
- PhotoDesk/Features/Library/LibrarySelectionController.swift:324 - debugHapticCount += 1
- PhotoDesk/Features/Library/LibrarySelectionController.swift:412 - debugAutoScrollTicks += 1
