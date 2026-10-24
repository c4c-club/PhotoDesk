# 07 · Agent 提示词包（可直接复制执行）

---

## 0. 使用说明

1. **每个编码会话开始时**，先发「§1 全局开场提示词」。
1.5 **环境探测已完成**（2026-10-24，结果见 [08 · 环境探测报告](08-环境探测报告.md)）：
    本机 = Windows 10 原生，无 Xcode / 无 iOS 模拟器 / WSL2 无 Ubuntu / Docker 已装未运行。
    构建路径已锁定 06 §7.4 方案 A。**现在第一件事是发「§2.5 P-1 环境准备」**，不要跳过。
2. 之后**严格按顺序**投递 §3 → §11（P0 → P9）。每个阶段完成后，跑验收命令，通过再进下一阶段。
3. 每个提示词都已自包含（含上下文、参考文档章节、产出路径、验收标准），**不需要 Agent 再回头猜**。
4. §12 是按需取用的补充提示词（改 Bug / 性能优化 / 补测试 / 重构）。
5. `{}` 包裹的内容（如 `{TEAM_ID}`）需要你替换后再发送。

---

## 1. 全局开场提示词（每次会话先发这条）

```
你是 iOS 原生开发专家，负责实现「PhotoDesk（照片管家）」——一个纯本地的 iOS 照片管理 App。

【必读】
请先完整阅读以下文件，它们定义了本项目的全部约束与设计，之后所有代码都必须遵守：
1. /AGENTS.md            —— 编码规则（iOS 15 API 黑名单、架构、PhotoKit 规则）
2. /docs/03-技术设计文档.md —— 架构分层、模块划分、数据模型、关键技术方案
3. /docs/04-UIUX设计文档.md —— 页面布局、交互规格、视觉规范、文案

【项目核心】
- 最低部署 iOS 15.0（硬性），Xcode 15.x，Swift 5.9+
- 核心卖点：全屏浏览照片时，**上滑 / 下滑** 触发 收藏 / 移到最近删除 / 隐藏，动作可在设置中自定义
- 纯本地、零上传、零第三方 SDK
- 先交付自签名测试版
- **构建方案已锁定**（docs/06 §7，不要再讨论替代方案）：
  **Windows 编辑 → Git 推送 → GitHub Actions `macos-14` 编译 → 手机（iPhone）验证**
- 本机是 **Windows 10 原生**（已探测，docs/08）：无 Xcode / 无 iOS 模拟器 → 编译 100% 在 CI 完成
- **不安装 Ubuntu、不引入 Linux 系统**：本地跑 `PhotoDeskCore` 的 `swift test` 只用
  **Docker 容器**（`swift:6.0-noble`），一条 `scripts/test-core.ps1`
- 手机验证：CI 产出**未签名 ipa** → Windows 用 **AltServer** 签名安装到 iPhone（7 天续签）
- iOS 模拟器只能"运行"不能"编译"；云端模拟器（Appetize）仅作可选补充，不是验收标准

【两条红线，任何代码都不得违反】
1. **永不永久删除**：应用内所有"删除"只能是 `PHAssetChangeRequest.deleteAssets`（移入系统「最近删除」，
   系统保留 30 天后自动清除）。**不得**实现永久擦除、**不得**清除「最近删除」、
   **不得**把"删除"实现成任何绕过系统回收站的路径。UI 文案统一说「移到最近删除」，不要说「彻底删除」。
2. **`PhotoDeskCore` 零 Apple 依赖**：手势判定、日期分组、dHash/pHash、去重分组、撤销策略、回收站淘汰策略
   必须实现在 `PhotoDeskCore/` 包里，**禁止 import UIKit / SwiftUI / Photos / Vision / CoreImage**，
   保证 Linux 上 `swift build && swift test` 可跑。App 侧只做类型适配，不重复实现。

【工作方式】
- 写代码前先说明要实现哪几个文件、各自职责；再逐个创建/修改
- 每完成一个模块，说明它如何被上层调用
- 遇到与文档冲突或文档未覆盖的设计问题，**先提问再动手**，不要自行发明架构
- 任何时候都不要为了让编译通过而使用 iOS 16+ API；必须写 #available 双实现
- 完成后给出「本轮变更文件清单 + 验收方式 + 下一步建议」

现在请等待我发送具体阶段的提示词。
```

---

## 2. 阶段索引

| 提示词 | 对应里程碑 | 目标 |
|---|---|---|
| **P-1** | **M-P** | ★先做：环境准备（Docker 跑 swift test + GitHub/Actions + AltServer 手机通道） |
| P0 | M0 | 工程骨架 + CI 跑通 |
| P1 | M1 | 授权 + 网格 + 图片管线 |
| P2 | M2 ★ | 全屏浏览器 + 上下滑手势引擎 |
| P3 | M3 | 收藏/隐藏/**移到最近删除**/撤销 + 批量 + 相簿 |
| P4 | M4 | 智能清理 |
| P5 | M5 | 搜索 / 元数据 / 统计 |
| P6 | M6 | 编辑 + 导出 / 分享 |
| P7 | M7 | 设置 / 隐私 / 无障碍 |
| P8 | M8 | 测试 + 自签名打包 |
| P9 | M9 | 打磨 + 发布候选 |

---

## 2.5 P-1 · 环境准备（★ 阻断性前置，第一个发这个）

```
【阶段】P-1 / M-P —— 环境准备
【前置】无
【背景】构建方案已锁定（docs/06 §7）：**Windows 编辑 → Git 推送 → Actions 编译 → 手机验证**。
  环境已探测（docs/08）：Windows 10 原生，无 Xcode / 无模拟器，Docker 29.8.2 已装（未启动）。
【用户明确决策】**不安装 Ubuntu / 不引入 Linux 系统** —— 本地跑 swift test 只用 Docker 容器（用完即弃）。
【目标】在写任何业务代码之前，打通「本地秒级反馈」「CI 编译通道」「手机验证通道」三条路。

【任务】
A. 打通本地 swift test —— **只用 Docker**
   - 启动 Docker Desktop（应用没开则 daemon 起不来），确认 `docker version` 的 Server 部分有输出
   - 验证：docker run --rm -v "${PWD}/PhotoDeskCore:/workspace" -w /workspace swift:6.0-noble swift test
     （Git Bash 下用 -v "/$(pwd)/PhotoDeskCore:/workspace"）
   - 产出 `scripts/test-core.ps1`：一条命令跑完 PhotoDeskCore 的 swift test，失败非 0 退出；
     先检查 docker daemon 可用性，不可用则给出明确提示而不是静默失败
B. 建 GitHub 仓库并配置 .github/workflows/ios.yml（按 docs/06 §5 + §7.4），产物要齐：
   - job `core-linux`：ubuntu-latest + container swift:6.0-noble + swift test --package-path PhotoDeskCore
   - job `build`（macos-14 + setup-xcode 15.4 + brew install xcodegen，needs: core-linux）：
       xcodegen generate → xcodebuild build/test（模拟器，iOS 15.5）→ 上传 PhotoDesk-Simulator.app.zip
       → **再产出未签名 ipa**（CODE_SIGNING_ALLOWED=NO + Payload 打包，见 §7.4）→ 上传 PhotoDesk-unsigned.ipa
   - push 一次，确认两个 job 都能跑起来（可以红，但必须是"我们的代码问题"而非"环境问题"）
C. 手机验证通道准备（输出步骤清单给我人工执行）：
   - Windows 装 AltServer、iPhone 装 AltStore、用免费 Apple ID 登录
   - 说明 7 天续签机制；将来买付费账号可切 CI 全自动签名（docs/06 §7.3 路径 B）

【禁止】
- **不要建议安装 WSL2 Ubuntu、迁移到 Linux、装 Windows 原生 Swift 工具链**
- 不要试图在本机安装 Xcode / iOS 模拟器
- 不要安装或使用 ZCode「iOS 模拟器」插件
- 不要建议 Hackintosh / macOS 虚拟机

【验收】
- 本机执行 scripts/test-core.ps1 → swift test 通过（哪怕现在只有空测试）
- GitHub Actions 两个 job 都能启动并给出明确日志
- 报告写清：docker 版本、test-core.ps1 用法、CI workflow 链接、AltServer 安装步骤

【产出报告】本机测试通路 + CI 链接 + 手机验证准备清单
```

---

## 3. P0 · 工程骨架与构建管线

```
【阶段】P0 / M0 —— 工程骨架与构建管线
【目标】生成一个能在 iOS 15.5 模拟器上编译、安装、启动的最小工程（空壳 Tab 界面），
       并能在模拟器照片库中导入测试照片。
【前置】P-1 已完成（本机 swift test 通路 + Actions workflow 已就位）

【参考】docs/02 §3、docs/02 §5、docs/03 §3、docs/06 全文、docs/08（环境事实）

【任务】
1. 在仓库根目录创建 `project.yml`（XcodeGen 配置），内容参照 docs/06 §2.1：
   - deploymentTarget iOS 15.0
   - Bundle ID: com.example.PhotoDesk
   - DEVELOPMENT_TEAM 从环境变量注入（不要硬编码）
   - Info.plist 三项权限文案：
     NSPhotoLibraryUsageDescription / NSPhotoLibraryAddUsageDescription / NSFaceIDUsageDescription
   - 三个 target：PhotoDesk / PhotoDeskTests / PhotoDeskUITests
2. 创建 `PhotoDeskCore/` SwiftPM 包骨架（**无 Mac 时这是唯一能本地验证的代码**）：
   - `Package.swift`：`platforms:` **留空**（不声明 .iOS），products = PhotoDeskCore，
     targets = PhotoDeskCore + PhotoDeskCoreTests
   - `Sources/PhotoDeskCore/` 放 7 个文件的接口占位（带文档注释、`TODO(P1/P4)`）：
     `SwipeResolver.swift` `GestureConfig.swift` `UndoPolicy.swift` `DateSectionizer.swift`
     `Hash/DHash.swift` `Hash/Phash.swift` `DuplicateGrouper.swift` `TrashPolicy.swift`
   - `Tests/PhotoDeskCoreTests/` 放一个 `SmokeTests.swift`（断言包能被导入）
   - **禁止 import 任何 Apple 框架**（UIKit / SwiftUI / Photos / Vision / CoreImage）
   - App 工程通过 `.package(path: "../PhotoDeskCore")` 本地依赖引入（写进 project.yml 的 dependencies）
3. 若环境没有 xcodegen，改用 Xcode 手工创建工程，但**目录结构必须与 docs/03 §3 一致**。
4. 按 docs/03 §3 的目录树创建所有目录与占位文件：
   - App/PhotoDeskApp.swift（SwiftUI 入口，TabView 两个 Tab：照片库 / 工具，各放一个占位 Text）
   - App/AppContainer.swift（DI 容器占位，带注释）
   - Core/{Photos,Imaging,Analysis,Persistence,Vault,Trash,Support,Routing} 各放一个空文件 + 职责注释
   - Features/{Library,Viewer,Albums,Search,Cleanup,Editor,Metadata,Vault,Export,Settings,Onboarding} 同上
   - UI/DesignSystem/{Colors,Typography,Spacing}.swift（token 定义按 docs/04 §5）
   - UI/Bridges/ 空占位
   - Resources/Assets.xcassets（含 AppIcon.appiconset 占位 JSON）+ Info.plist
5. 创建脚本：
   - scripts/build-sim.sh（按 docs/06 §3）
   - scripts/sim-photos.sh（按 docs/06 §3.1，生成 300 张测试图并 simctl addmedia）
   - scripts/test-core.ps1（P-1 已建则跳过）
6. 创建 .github/workflows/ios.yml（按 docs/06 §5，**必须包含 `core-linux` job**：
   ubuntu-latest + `container: swift:6.0-noble` + `swift test --package-path PhotoDeskCore`；
   `build` job runs-on macos-14 且 `needs: core-linux`）。

【禁止】
- 不要引入任何第三方依赖
- 不要使用任何 iOS 16+ API
- 不要在这个阶段写业务逻辑
- `PhotoDeskCore` 内**禁止** import UIKit / SwiftUI / Photos / Vision / CoreImage

【验收（分两条路径，无 Mac 时只跑第一条）】
A. 本地（Windows，无需 Mac，P-1 打通后）：
  powershell -ExecutionPolicy Bypass -File scripts/test-core.ps1
  # 等价裸命令（Docker 路线）：
  #   docker run --rm -v "${PWD}/PhotoDeskCore:/workspace" -w /workspace swift:6.0-noble swift test
  必须：零错误，测试通过。若报"找不到 swift / docker daemon 未运行"，先回去补做 P-1。
B. macOS（本机或 GitHub Actions macos-14 runner）：
  xcodegen generate
  xcodebuild -scheme PhotoDesk -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 13,OS=15.5' build
  bash scripts/sim-photos.sh
  xcrun simctl install booted <产物 .app>
  xcrun simctl launch booted com.example.PhotoDesk
  必须：编译零错误、模拟器启动成功、能看到两个 Tab、模拟器照片 App 内有 300 张测试图。
  用 `otool -l <app>/PhotoDesk | grep -A3 LC_BUILD_VERSION` 确认 minos = 15.0。
  若当前无 macOS，把 B 交给 GitHub Actions：push 后看 Actions 日志与 artifact。

【产出报告】文件清单 + `swift test` 输出（或 Actions 构建日志关键行）+ 截图
```

---

## 4. P1 · 授权 + 照片网格 + 图片管线

```
【阶段】P1 / M1 —— 授权、照片网格、图片加载管线
【前置】P0 已完成，模拟器内有 ≥300 张照片（建议再生成到 5,000 张用于性能验证）
【参考】docs/01 §A、docs/03 §3/§4.1/§5.2/§5.3/§5.6、docs/04 §3.1、docs/05 §3

【任务】
1. Core/Photos/PhotoLibraryService.swift
   - `enum LibraryAccess { notDetermined, denied, restricted, limited, authorized }`
   - `func requestAccess() async -> LibraryAccess`（用 `PHPhotoLibrary.requestAuthorization(for: .readWrite)`）
   - `.limited` 时提供 `presentLimitedLibraryPicker(from:)` 入口
   - 发布 `@Published var access: LibraryAccess`
2. Core/Photos/AssetRepository.swift
   - `protocol AssetRepositoryProtocol`：`func fetch(scope: PhotoScope, offset: Int, limit: Int) async -> [PhotoItem]`
   - 分批 500；`PHFetchOptions`：`includeHiddenAssets = false`、`includeAllBurstAssets = false`、
     `sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]`
   - 映射为 `PhotoItem`（docs/03 §4.1）
3. Core/Imaging/*
   - `ImagePipeline`（protocol + 实现）：三级缓存
     内存 NSCache（totalCostLimit 60MB, countLimit 500）→ 磁盘 LRU（Library/Caches/ThumbCache，200MB 上限）
     → `PHCachingImageManager`（`allowsCachingHighQualityImages = false`）
   - `func thumbnail(for:size:scale:) async -> UIImage?`、`prefetch(ids:size:)`、`cancel(id:)`
   - 同一 id+size 在途请求合并
4. Features/Library/
   - `LibraryViewController.swift`（UIKit）：`UICollectionViewCompositionalLayout` + `UICollectionViewDiffableDataSource`
     （Section = 月份，Item = PhotoItem），列数 2/3/4/5 由 `gridColumns` 控制
   - 实现 `UICollectionViewDataSourcePrefetching`（用 ImagePipeline.prefetch）
   - cell 离屏 `cancelImageRequest`
   - 粘性分组头（Compositional Layout 的 `boundarySupplementaryItem` + `pinToVisibleBounds: true`）
   - `LibraryContainer.swift`（`UIViewControllerRepresentable`）接入 SwiftUI 壳
   - `LibraryViewModel.swift`：`ObservableObject`，`@Published var sections: [MonthSection]`，分页加载
5. Core/Support/DateSectionizer.swift：按日/月/年分组（用 `Calendar.current`，尊重时区）
6. Core/Photos/PhotoChangeObserver.swift：`PHPhotoLibraryChangeObserver` → 计算 insert/remove/change →
   通知 ViewModel 做 Diffable 增量更新（**不要整库 reload**）
7. UI/DesignSystem/DSEmptyState.swift：空 / 加载骨架屏 / 无权限 / 受限授权 四态
8. Features/Onboarding/PermissionIntroView.swift：授权引导页（文案见 docs/04 §7）
9. 右侧月份快速索引条（自定义 UIControl，拖动跳转）

【验收】
- 授权弹窗出现；拒绝/受限各有引导
- 5,000 张照片滚动：Instruments FPS ≥ 55，内存峰值 < 250MB
- 在系统相册删除 3 张 → 切回 App，3 秒内自动消失（增量 diff，非 reload）
- 冷启动到首屏 < 2.0s
- 列数切换 2/3/4/5 正常且记忆
- 新增 `PhotoDeskTests/DateSectionizerTests.swift`，通过

【产出报告】文件清单 + 性能实测数据 + 滚动截图
```

---

## 5. P2 · 全屏浏览器 + 上下滑手势引擎 ★核心

```
【阶段】P2 / M2 —— 全屏浏览器与上下滑手势引擎（本项目最核心功能）
【前置】P1 已完成
【参考】docs/01 §3（手势详细规格）、docs/03 §5.1、docs/04 §3.2、docs/05 §4

【任务】
A. Features/Viewer/ViewerViewController.swift（UIKit）
   - `UICollectionView` + `isPagingEnabled = true`，cell 尺寸 = 屏幕尺寸，横向分页
   - 复用 `ImagePipeline.fullImage(for:progress:)` 加载大图；离屏取消
   - 顶部栏（关闭 / 收藏 / 信息 / 更多）+ 底部胶片条，3 秒无操作自动淡出，点击切换
   - 通过 `UIViewControllerRepresentable` 以 `.fullScreenCover` 呈现，带 zoom 转场（若复杂则先淡入）
B. Features/Viewer/ZoomableImageCell.swift
   - `UIScrollView` 嵌套 `UIImageView`，支持双击（1× ↔ 2.5×）与双指捏合（1×–5×）
   - 暴露 `var zoomScale: CGFloat` 给外部
C. Features/Viewer/SwipeGestureEngine.swift ★
   - `SwipeConfig { distanceThreshold(80/120/180), velocityThreshold(500/700/900), minDistanceForVelocity: 40 }`
   - 纯函数 `SwipeResolver`：
       `direction(of translation:) -> SwipeDirection?`（要求 |dy| > |dx| × 1.5）
       `progress(translation:) -> CGFloat`（0...1）
       `isLocked(translation:velocity:) -> Bool`
   - **这部分必须是纯 Swift、可单测，不引用 UIKit 视图**
D. ViewerViewController 中挂载 `UIPanGestureRecognizer`：
   - `delegate.gestureRecognizerShouldBegin` 返回 `currentZoomScale <= 1.01 && !isTwoFingerZooming`
   - `shouldRecognizeSimultaneouslyWith` 返回 true（与 paging 共存，靠方向锁裁决）
   - 垂直方向锁定时 `collectionView.isScrollEnabled = false`，松手恢复
E. Features/Viewer/ActionOverlayView.swift
   - 圆形 96pt + SF Symbol 36pt + 文案 15pt
   - 上滑 → 屏幕上方 1/4；下滑 → 屏幕下方 1/4
   - 透明度 `0.35 + 0.65 × progress`，缩放 `0.85 + 0.30 × progress`，位移 `dy × 0.6`
   - 锁定态：实心背景 + scale 1.15 + 2pt 描边 + `UIImpactFeedbackGenerator(.medium)`
   - 颜色 token：收藏 #FFB300 / 隐藏 #5C6BC0 / 移到最近删除 #E53935 / 加入相簿 #26A69A / 分享 #42A5F5 / 信息 #78909C
F. 动作执行管线（ViewerViewModel）
   - `SwipeAction` 枚举：favorite / unfavorite / toggleFavorite / hide / unhide / moveToRecentlyDeleted /
     addToAlbum / share / showInfo / rotate / dismiss / none
   - **红线**：`moveToRecentlyDeleted` 的实现**只能是** `PHAssetChangeRequest.deleteAssets`
     （移入系统「最近删除」，系统保留 30 天后清除）。
     **不要**实现永久删除、**不要**清除「最近删除」。UI 文案统一说「移到最近删除」，禁用「彻底删除」字样。
   - 默认：上滑 = .favorite，下滑 = .hide（写入 @AppStorage）
   - 执行流程：锁定并松手 → 若破坏性且 `confirmDestructive` 打开则 `UIAlertController` 确认
     → 飞出动画（Reduce Motion 时改淡出）→ 执行 → 入撤销栈 → `autoAdvance` 时前进下一张 → Toast
G. Core/Support/UndoCenter.swift + UI/DesignSystem/DSToast.swift
   - Toast：底部胶囊，Material 玻璃，左图标 + 文案，右「撤销」+ 环形倒计时（默认 5 秒）
   - 本阶段先支持 收藏 / 隐藏 的撤销
H. Features/Viewer/VideoCell.swift：静音循环自动播放，300ms 内起播
I. iCloud 资源：占位 + 云图标 + 下载按钮 + 环形进度（`isNetworkAccessAllowed` 由设置控制）
J. Features/Viewer/FilmStripView.swift：底部缩略图胶片条，当前页居中高亮，可隐藏
K. Features/Onboarding/GestureTutorialView.swift：循环手势演示动画（纯代码，不用素材），
   文案「上滑 = 收藏 / 下滑 = 隐藏 / 在设置里可以随时调换」，底部「去设置」按钮（暂置灰）
L. 测试
   - `PhotoDeskTests/SwipeResolverTests.swift`：方向边界（1.5×）、阈值、速度触发、progress
   - `PhotoDeskUITests/GestureUITests.swift`：
       `press(forDuration: 0.05, thenDragTo:)` 模拟慢速垂直拖拽，断言 Toast「已收藏」出现

【关键细节，务必实现】
- 放大状态（zoomScale > 1.01）**禁用**上下滑手势
- 拖拽时图片本体不动，只有浮层动
- 方向锁：同一时刻只认一个方向；水平交还分页器
- 尊重 `UIAccessibility.isReduceMotionEnabled`

【验收】
- 左右翻页精准无白帧；5,000 张库来回翻不崩
- 上滑 → 收藏（系统相册同步）；下滑 → 隐藏（主网格消失）
- 放大后上下滑不触发动作
- 浮层随手指实时变化；过阈值有触觉 + 锁定态
- Toast 撤销 100% 生效
- 开启「减弱动态效果」后动画降级为淡出
- UI 测试通过

【产出报告】文件清单 + 手势状态机说明 + 模拟器录屏（或关键帧截图）
```

---

## 6. P3 · 收藏/隐藏/移到最近删除/撤销 + 批量 + 相簿

```
【阶段】P3 / M3 —— 破坏性操作、撤销体系、批量与相簿
【前置】P2 已完成
【参考】docs/01 §C（含"永不永久删除"强约束）、docs/03 §5.1、docs/03 §4.2、docs/05 §5

【★ 红线，先读三遍】
应用内"删除"= 移入系统「最近删除」，且**只能**是 `PHAssetChangeRequest.deleteAssets`。
不实现永久删除、不提供"彻底删除"入口、不清空「最近删除」。
UI 文案一律用「移到最近删除」。

【任务】
1. Core/Photos/PhotoWriter.swift
   - `toggleFavorite(_:)`, `setHidden(_:hidden:)`, **`moveToRecentlyDeleted(_:)`**,
     `createAlbum(title:)`, `renameAlbum`, `deleteAlbum`, `add(assets:to:)`, `remove(assets:from:)`
   - `moveToRecentlyDeleted` 内部只有一句 `PHAssetChangeRequest.deleteAssets(assets as NSArray)`；
     方法文档注释写明"移入系统最近删除，30 天后由系统自动清除，本方法不执行永久擦除"
   - 全部走 `PHPhotoLibrary.shared().performChanges`，带 completion 错误处理
2. Core/Trash/TrashBin.swift ★（撤销保险副本，**不是备份**）
   - 执行 `moveToRecentlyDeleted` **之前**：`asset.requestContentEditingInput(with: nil)` 拿 `fullSizeImageURL`
     （视频用 `AVAssetExportSession` 导出）→ 拷到 `ApplicationSupport/_Trash/<uuid>.<ext>`
   - Core Data `TrashItem` 记录：originLocalID / 路径 / mediaType / byteSize / metaJSON(creationDate, location, UTType, 像素尺寸)
   - **若原件获取失败（iCloud 未下载）→ 拒绝执行并返回 `.needsDownload` 错误**（提示"请先下载原件"）
   - 撤销：`PHAssetCreationRequest.fromImage(atFileURL:)` / `fromVideo(atFileURL:)` 重建，
     再写回 `creationDate` 与 `location`
   - 容量上限（默认 2048MB，设置可调），按 `createdAt` 淘汰最老；设置里可整体关闭（关闭后撤销窗口内不提供恢复）
3. Features/Vault/VaultService.swift + Core/Vault/BiometricGate.swift
   - 隐藏：`PHAssetChangeRequest(for:).isHidden = true`（已确认公开 API）
   - 主网格 `includeHiddenAssets = false`
   - 「已隐藏」入口需 Face ID：`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`，
     成功后 5 分钟内免重复验证
   - **模拟器（`targetEnvironment(simulator)`）跳过生物识别，直接放行**
4. Core/Support/UndoCenter.swift 补全
   - 支持 收藏 / 隐藏 / 移到最近删除 / 加相册 四类撤销
   - Core Data `ActionLog` 持久化（`prevState` JSON），App 重启后 10 秒内仍提示可撤销
   - 注入 `Clock` 协议以便单测撤销窗口（纯策略部分放 `PhotoDeskCore/UndoPolicy.swift`）
5. 多选模式：点选 / 滑动框选（在网格上加 `UIPanGestureRecognizer` 框选）/ 全选 / 反选
   + 底部批量操作栏（收藏 / 隐藏 / **移到最近删除** / 加相簿 / 移出 / 导出）
6. Features/Albums/：系统相簿列表（用户相簿 / 智能相簿分组）+ 新建 / 重命名 / 删除
7. 「最近删除」页：只读浏览（系统 `smartAlbumRecentlyDeleted`）
   + 顶部说明「照片保留 30 天后由系统自动清除」+ 底部「去系统相册恢复」按钮（跳转 `photos-redirect://`）
   + **本页不提供任何删除/清空操作**

【验收】
- 收藏/隐藏与系统相册双向同步（系统相册里加收藏 → App 内可见）
- **移到最近删除 → 照片确实出现在系统相册「最近删除」中，App 内无任何"永久删除"入口**
- 撤销 → 从沙盒副本重建 → 照片回到系统相册，creationDate 与 GPS 保留
- iCloud-only 照片执行时提示「请先下载原件」，不执行
- 已隐藏入口需 Face ID；5 分钟内免重复
- 批量 500 张加入相簿 < 3s
- 杀掉 App 重启 → 10 秒内顶部提示「上次有 N 个操作可撤销」
- 新增 `TrashBinTests` / `UndoCenterTests` / `PhotoDeskCore` 的 `UndoPolicyTests`，通过

【产出报告】文件清单 + 撤销流程说明 + 测试结果
```

---

## 7. P4 · 智能清理

```
【阶段】P4 / M4 —— 重复/相似/截图/大文件/模糊 检测与清理
【前置】P1、P3 已完成
【参考】docs/01 §F、docs/03 §4.2/§5.4/§5.5、docs/04 §3.3、docs/05 §6

【任务】
1. Core/Analysis/FingerprintService.swift
   - 256px 缩略图 → 灰度 → dHash(64bit) + pHash(DCT 8×8, 64bit)，存 2×Int64
   - Accelerate/vImage 加速，单张 < 8ms
   - **算法内核放 `PhotoDeskCore/Hash/DHash.swift` 与 `Phash.swift`（纯 Swift，输入像素数组）**，
     App 侧只负责取图 → 转像素 → 调包 → 落库
2. Core/Persistence：实体 `Fingerprint`、`DuplicateGroup`、`ScanSession`（字段见 docs/03 §4.2）
3. Core/Analysis/ScanCoordinator.swift
   - 分批（500）+ `TaskGroup(maxConcurrent: 4)` + `qos: .utility`
   - 跳过已计算且 `algoVersion` 匹配的 asset
   - 每 200 条批量 save；更新 `ScanSession.cursor` 支持中断恢复
   - 每步检查 `Task.isCancelled`；发布进度（`@Published` 或 AsyncStream）
4. 分组算法
   - 粗筛桶：像素宽高比近似（±0.02）+ 创建时间 |Δt| ≤ 2s
   - 桶内两两汉明距离：≤ 4 高置信重复，≤ 8 疑似重复（阈值设置可调）
   - 推荐保留：原图优先 > 像素最大 > 有编辑 > 最新修改
   - 可选：Vision `VNGenerateImageFeaturePrintRequest` 做"相似"检测（独立开关，默认关）
5. 专项：截图（`mediaSubtypes.contains(.photoScreenshot)`）、
   大文件（视频 > 100MB / 照片 > 10MB，按大小排序）、
   模糊（vImage 3×3 拉普拉斯卷积 + 方差 < 60，阈值可调）【P2 功能，可视进度取舍】
6. 「待清理清单」：候选先入清单 → 用户勾选 → 二次确认 → 批量执行
   （**只走 `moveToRecentlyDeleted`，且必须先落撤销保险副本**）
7. Features/Cleanup/ UI：环形进度 + 取消；五类结果卡片（图标/数量/可省空间）；
   重复组并排对比 + 「★推荐」角标 + 一键「保留推荐项」

【验收】
- 12,000 张全量扫描 < 90s，扫描期间 UI 不卡、内存 < 250MB
- 中途杀 App → 重启从断点继续（cursor 生效）
- 人工抽样 20 组，推荐准确率 ≥ 95%
- 清理执行后照片进系统「最近删除」+ 沙盒副本，可撤销
- 新增 `FingerprintServiceTests`（同图距离 0、旋转 90°、压缩后距离）与
  `DuplicateGrouperTests`（分桶 + 推荐 + 阈值边界），通过

【产出报告】文件清单 + 扫描耗时实测 + 分组效果截图
```

---

## 8. P5 · 搜索 / 筛选 / 元数据 / 存储统计

```
【阶段】P5 / M5 —— 搜索、多维筛选、EXIF 元数据、存储统计
【前置】P1 已完成
【参考】docs/01 §E/§H、docs/04 §3、docs/05 §7

【任务】
1. 日期三级下钻（年 → 月 → 日）+ 媒体类型多选（照片/视频/Live/截图/人像/全景/慢动作/延时/RAW）
   + 状态筛选（已收藏/已隐藏/未整理）——统一抽象为 `SearchPredicate`
2. 关键词搜索：Vision `VNRecognizeTextRequest` 后台建 OCR 索引（`OCRText` 实体），支持中英文【P2】
3. 图片分类标签：`VNClassifyImageRequest`（人物/动物/食物/风景/文档…）【P2】
4. 地图视图：MapKit + 聚合大头针，点开看该地点照片【P2】
5. Features/Metadata/：信息面板
   - 尺寸、字节数、格式（从 `PHAssetResource.originalFilename` 后缀 + uniformTypeIdentifier 推断）
   - EXIF：`requestContentEditingInput` → `CGImageSourceCopyPropertiesAtIndex` 取
     设备型号 / 镜头 / 光圈 / 快门 / ISO / 焦距 / 闪光灯
   - GPS + 小地图（`MKMapView` 单针）
6. Features/Export/… 中的存储统计页：
   - 总占用、按类型占比（自绘环形 `Shape`）、按年份分布（自绘柱状 `Path`）
   - **禁止使用 Swift Charts（iOS 16+）**，必须自绘
7. 搜索历史 + 常用筛选保存为「智能视图」【P2】

【验收】
- 组合筛选在 10,000 张库响应 < 500ms
- EXIF 面板字段完整（含 GPS）
- 图表在浅色/深色下都可读，且 VoiceOver 有数值标签
- 新增 `SearchPredicateTests` 与 `MetadataParserTests`，通过

【产出报告】文件清单 + 关键截图（EXIF 面板、统计页）
```

---

## 9. P6 · 编辑 + 导出 / 分享

```
【阶段】P6 / M6 —— 图片编辑、导出与分享
【前置】P2 已完成
【参考】docs/01 §G/§I、docs/04 §3、docs/05 §8

【任务】
1. Features/Editor/
   - 裁剪：自由 + 原比例 + 1:1 + 4:3 + 16:9 + 3:4 + 9:16；旋转 90°；水平翻转
   - 调整（Core Image 实时预览）：亮度 / 对比度 / 饱和度 / 色温 / 锐度
   - 【P2】8 款滤镜预设（CIFilter 组合）；涂鸦标注（PencilKit）+ 文字
   - 保存：`PHContentEditingOutput` 覆盖原件（保留可还原）**或**另存为新照片（默认另存）
   - 还原：`revertAssetContentToOriginal()`
2. UI/Bridges/ActivityViewWrapper.swift：`UIActivityViewController` 包装（**不用 ShareLink**）
3. Features/Export/
   - 格式：原图 / JPEG / PNG / HEIC；尺寸：长边 1080 / 2048 / 4096 / 原始；质量滑杆
   - 「去除位置信息」开关（导出前抹掉 GPS，默认询问）
   - 批量导出到「文件」：`UIDocumentPickerViewController`【P2】
   - 导入：`PHPickerViewController`（**不用 SwiftUI PhotosPicker**）【P2】
4. 导出/分享前若资源是 iCloud-only，先下载（进度提示）

【验收】
- 编辑后另存不破坏原图；覆盖后可「还原到原始状态」
- 导出 JPEG 长边 2048 / 质量 0.8，尺寸与预期一致
- 勾选「去除位置信息」后导出文件 EXIF 无 GPS
- 分享面板在 iOS 15 与最新版均正常弹出
- 新增 `ExportOptionsTests` / `EditorTransformTests`，通过

【产出报告】文件清单 + 前后对比截图
```

---

## 10. P7 · 设置 / 隐私 / Face ID / 无障碍 / 性能

```
【阶段】P7 / M7 —— 设置中心、隐私、无障碍与性能达标
【前置】P2–P6 已完成
【参考】docs/01 §J/§K/§L、docs/03 §5.6/§5.7/§7、docs/04 §3.4/§6、docs/05 §9

【任务】
1. Features/Settings/GestureSettingsView.swift ★
   - 上滑动作 / 下滑动作：进入 `ActionPickerView`（图标 + 名称 + 说明 + 打勾）
   - 灵敏度三档（舒适 80 / 标准 120 / 保守 180）
   - 触觉反馈开关、破坏性操作确认开关、撤销窗口（3/5/10 秒）、执行后自动前进开关、
     遵循「减弱动态效果」开关
   - 底部说明（原文照抄，别改口径）：
     「移到最近删除」只会把照片放进系统「最近删除」，保留 30 天后由系统清除，本 App 不会永久删除。
     iOS 会弹出一次确认框且无法关闭；若想更快，建议把下滑设为「隐藏」。
   - 「撤销保险副本」开关（默认开）+ 容量上限（2GB）：关闭后撤销窗口内不再提供恢复，
     Toast 改为引导用户去系统相册恢复
   - 「重新观看手势教学」按钮
   - 所有改动立即生效（@AppStorage 驱动）
2. 外观（跟随系统/浅色/深色）、网格列数与默认排序、iCloud 自动下载原件
3. Face ID 设置 + 「隐私声明」页（明确零上传 / 零分析 / 零第三方 SDK）
4. 缓存管理：显示内存/磁盘/Trash 占用 + 一键清理
5. 无障碍：
   - 缩略图 `accessibilityLabel = "照片，2026年10月3日，已收藏"`；traits = [.image, .button]
   - 设置中「关闭手势」开关 + 浏览页底部常驻 3 按钮（收藏 / 隐藏 / 移到最近删除）作为替代路径
   - 动态字体全覆盖（浏览页浮层上限 20pt）
   - 减弱动效 → 飞出改淡出；减弱透明度 → 玻璃降级实色
6. 性能专项：Instruments 跑内存/帧率/启动，不达标则优化（缓存参数、批处理、解码并发数）
7. 诊断日志导出（`OSLogStore`，iOS 15 可用）

【验收】
- 手势设置改完回到浏览页立即生效
- VoiceOver 全量走查无未标记元素
- docs/03 §7 性能预算表全部达标
- 隐私声明页可达
- 关闭手势后，App 仍可完成全部核心操作（替代按钮路径）

【产出报告】文件清单 + 性能实测表 + 无障碍走查结果
```

---

## 11. P8 · 测试体系 + 自签名打包

```
【阶段】P8 / M8 —— 测试补齐与自签名真机包
【前置】P7 已完成
【参考】docs/05 §10、docs/06 §4/§6/§7

【任务】
1. 单元测试补齐，核心逻辑覆盖率 ≥ 70%。**优先把可纯逻辑化的部分放 `PhotoDeskCore` 并写 XCTest**：
   SwipeResolver / UndoPolicy / DateSectionizer / DHash / Phash / DuplicateGrouper / TrashPolicy；
   App 侧保留：UndoCenter / TrashBin / AssetRepository(Mock)
2. UI 测试：授权中断处理（`addUIInterruptionMonitor`）、上滑/下滑手势、撤销、批量选择、
   清理确认流程
3. 性能 XCTest：`XCTApplicationLaunchMetric`、`XCTMemoryMetric`、`XCTOSSignpostMetric`（滚动）
4. **CI 增加 Linux job**：`.github/workflows/ios.yml` 里 `core-linux`（ubuntu-latest +
   `container: swift:6.0-noble` + `swift test --package-path PhotoDeskCore`），
   `build` job 加 `needs: core-linux`。确认 push 后 Linux job 绿。
5. scripts/sign-device.sh（按 docs/06 §4.3），把 `{TEAM_ID}` 换成你的 Team ID
6. 写「安装说明.md」：AltStore 安装步骤 + 7 天续签提醒 + 常见失败排查（0xe8008015 等）
7. 写「测试清单.md」（按 docs/06 §6.4 的手动测试矩阵）
8. **手机验证**（Windows 上执行，agent 出步骤清单）：
   下载 CI 的 `PhotoDesk-unsigned.ipa` → AltServer(Windows) "Install IPA" → iPhone
   → 真机验证：上滑收藏、下滑隐藏、浮层跟手、Toast 撤销、Face ID 保险箱、清理流程
   → 记录：机型 + iOS 版本 + 每张截图 + 发现的问题
9. 真机冒烟：授权 → 网格 → 上下滑 → 撤销 → **移到最近删除后能在系统相册「最近删除」里看到**
   → 已隐藏 Face ID → 清理

【验收】
- `cd PhotoDeskCore && swift test`（Windows WSL2 或 Linux）全绿 —— 无 Mac 也能验证核心逻辑
- `xcodebuild test` 全绿
- 真机（iOS 最新）自签名安装成功、启动正常
- 冒烟路径无 P0/P1 缺陷
- 全局检查：代码中不存在"彻底删除/永久删除/清空最近删除"的实现或文案

【产出报告】测试覆盖率数字 + ipa 路径 + 真机截图 + 已知问题列表
```

---

## 12. P9 · 打磨 + 发布候选

```
【阶段】P9 / M9 —— 发布候选打磨
【前置】P8 已完成

【任务】
1. 中文文案全量校对（对照 docs/04 §7）
2. 动效微调（转场、Toast、飞出的时长与曲线统一为 0.25s easeOut / 0.35s spring）
3. App Icon 正式版（1024×1024，照片 + 上下箭头）
4. `PrivacyInfo.xcprivacy`：`NSPrivacyTracking = false`、`NSPrivacyCollectedDataTypes = []`、
   `NSPrivacyAccessedAPITypes` 只声明照片库（`NSPrivacyAccessedAPICategoryPhotoLibrary`）
5. 版本号 1.0.0 (1)，归档 build
6. 产出「发布说明.md」与「已知问题.md」

【验收】
- 冷启动 / 滚动 / 内存 三项性能复测达标
- 全 App 无 TODO/FIXME 残留（或已登记进已知问题）
- 交付物齐全：ipa + 安装说明 + 发布说明 + 已知问题
```

---

## 13. 补充提示词（按需取用）

### 13.1 修 Bug

```
【修 Bug】
现象：<描述复现步骤、期望、实际>
相关文件：<文件路径列表>
要求：
1. 先定位根因并一句话说明，再改代码
2. 修复后补一个能复现该 Bug 的单元测试或 UI 测试
3. 检查同类代码是否有相同问题（同样的模式扫一遍）
4. 说明为何之前没被发现（测试缺口在哪）
```

### 13.2 性能优化

```
【性能优化】
目标：把 <场景，如「5,000 张网格滚动」> 的 <指标> 从 <当前值> 降到 <目标值>
要求：
1. 先用 Instruments（Time Profiler / Allocations / Core Animation）定位瓶颈，给出证据
2. 只做有数据支撑的优化，禁止盲目改动
3. 优化后重新测量并对比前后数据
4. 若涉及缓存参数，改为可调常量并加注释说明取舍
```

### 13.3 补测试

```
【补测试】
为 <模块> 补齐测试，要求：
1. 覆盖：正常路径、边界值、错误路径、并发/取消
2. 使用 Mock（协议已存在），不依赖真实照片库
3. 测试命名：`test_<方法>_<条件>_<预期>`
4. 每个测试只断言一件事
5. 报告覆盖率变化
```

### 13.4 重构

```
【重构】
把 <现有实现> 重构为 <目标结构>，要求：
1. 先说明重构动机（可读性 / 可测试性 / 性能），不要为了重构而重构
2. 保持对外 API 不变，或明确列出破坏性变更
3. 小步提交，每步都能编译并跑通测试
4. 重构前后行为一致，用现有测试保证
```

### 13.5 新增一个小功能

```
【新功能】<功能名>
需求：<一句话>
参考：docs/01 的 <编号>、docs/04 的 <章节>
要求：
1. 先给出设计方案（改哪些文件、新增哪些、对现有架构的影响），我确认后再写
2. 遵守 AGENTS.md 全部规则，尤其是 iOS 15 API 黑名单
3. 中文文案对照 docs/04 §7 风格
4. 补测试 + 更新 docs/05 进度表
```

### 13.6 让 Agent 自查 iOS 15 兼容性

```
【兼容性自查】
请扫描 <目录或文件列表>，逐项检查：
1. 是否有 iOS 16/17+ 专有 API 未做 #available 保护（对照 AGENTS.md §2 黑名单）
2. 是否有隐式抬高 deployment target 的依赖或 build setting
3. 是否使用 SwiftData / @Observable / Charts / NavigationStack / PhotosPicker / ShareLink
4. 是否用了需要付费账号 Capability 的能力（iCloud / App Groups / Push / Keychain Sharing）
5. 所有 SwiftUI View 在 iOS 15 上的行为差异（NavigationView 双层、safeArea、Material）
输出：问题清单（文件:行号 + 问题 + 修复建议），无问题则明确说明「已检查，无问题」。
```

### 13.7 在 Windows 主机上验证代码（Docker 容器专用）

```
【环境】我的主机是 Windows，没有 macOS，也不打算换系统。请你按下面的方式配合我：

1. 任何属于「纯逻辑」的代码（手势阈值判定、日期分组、哈希算法、去重分组、撤销窗口策略、
   回收站淘汰策略）一律写进 `PhotoDeskCore/`，满足：
   - 只 import Foundation，禁止 import UIKit / SwiftUI / Photos / Vision / CoreImage
   - 输入用基础类型（Double / [UInt8] / Date / struct），不要传 CGSize / UIImage / PHAsset
   - 需要"当前时间"的地方注入 `Clock` 协议
2. 我在 Windows 上用 **Docker 容器**（`swift:6.0-noble` 官方镜像）跑测试——**不安装 Ubuntu、不引入 Linux 系统**。
   请给我能直接粘贴的命令：
     powershell -ExecutionPolicy Bypass -File scripts/test-core.ps1
     # 或裸命令：docker run --rm -v "${PWD}/PhotoDeskCore:/workspace" -w /workspace swift:6.0-noble swift test
   并在产出报告里明确区分「已本地验证（Docker）」与「待 CI 验证（macOS）」两部分。
3. 任何依赖 Apple 框架的代码，请标注 `// ⚠️ macOS-only`，并说明它需要 GitHub Actions
   macos-14 runner 才能编译验证。
4. 不要建议我：安装 WSL2 Ubuntu、迁移到 Linux、装 Hackintosh、macOS 虚拟机、
   Linux/Windows 交叉编译 iOS —— 都不做。
   也不要建议我在 Windows 上装"iOS 模拟器"：CoreSimulator 是 macOS 专有组件，Windows 上没有真的。
   验证走真机：CI 出未签名 ipa → AltServer 装到 iPhone。
5. 如果报错来自 GitHub Actions，请先区分「编译错误 / 签名错误 / 测试失败 / runner 环境问题」再给方案。
```

### 13.9 环境探测（✅ 已于 2026-10-24 完成，结果见 08）

> **不要再发这条了。** 结论已归档在 [docs/08-环境探测报告.md](08-环境探测报告.md)：
> 本机 = Windows 10 原生（MINGW64），无 Xcode / 无模拟器 / WSL2 无 Ubuntu / Docker 已装未运行；
> ZCode「iOS 模拟器」插件是 macOS 本地包装，不可用。
>
> 下面这段**只在换到新环境时（云 Mac、新 agent 主机）才重新发**：

```
【环境探测】先别写任何代码，执行下面三条命令并把原始输出原样贴给我：

  uname -a
  xcode-select -p
  xcrun simctl list devices

然后根据输出回答我三个问题：
1. 你的操作系统是什么？（Darwin = macOS / Linux / 其它）
2. 你这台机器上有没有装 Xcode？版本号是多少？
3. 你之前说"有 iOS 模拟器"——它是本机 Xcode Simulator，还是某个云端服务（如 Appetize.io）？
   如果是云端服务，请说明是哪个。

我会根据你的回答决定后续用哪条构建路径：
- 你是 macOS → 直接用你本机编译调试，我的 Windows 只当编辑器
- 你是 Linux/容器 → 你只能帮我跑 PhotoDeskCore 的 swift test，编译走 GitHub Actions
- 你只有云端模拟器 → 它能"运行 App"不能"编译"，我需要先由 CI 产出 .app 再上传
```

### 13.8 检查"永不永久删除"红线

```
【红线自查】
扫描 <目录>，逐项确认：
1. 所有删除路径是否都只调用 `PHAssetChangeRequest.deleteAssets`（移入系统「最近删除」）
2. 是否存在绕过「最近删除」的永久擦除代码（如直接删沙盒文件后不写回、删除后再清一次）
3. 是否存在"彻底删除 / 永久删除 / 清空最近删除"的 UI 文案或入口
4. `TrashBin` 的沙盒副本是否只在撤销窗口内使用，且容量受限、可关闭
5. iCloud-only 未下载资源是否被拦截（拒绝执行）
输出：逐项 ✓/✗ + 文件:行号证据。
```

---

## 14. 提示词使用小贴士

| 场景 | 做法 |
|---|---|
| 一次想跑多个阶段 | **不要**。一次一个阶段，验收通过再下一个，否则错误会累积 |
| Agent 产出与文档不符 | 发 §13.6 兼容性自查 + 「请重新对照 docs/03 §5.1 实现」 |
| Agent 想偷懒用 iOS 16 API | 重发 AGENTS.md §2 并强调「必须 #available 双实现」 |
| 想改默认手势 | 改 `docs/03 §4.3` 的 `@AppStorage` 默认值，再让 Agent 同步 |
| 上下文太长 | 每个阶段开新会话，重新发 §1 开场词 + 该阶段提示词 + 上阶段的「产出报告」摘要 |
