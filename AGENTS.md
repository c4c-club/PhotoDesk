# AGENTS.md — PhotoDesk 编码规则（写代码前必读）

> 本文件是编码 Agent 的**全局约束**，每次会话开始都应先加载。违反任何一条都会导致 iOS 15 编译失败或架构返工。

---

## 1. 项目事实

- **项目**：PhotoDesk（照片管家），iOS 原生照片管理 App
- **最低部署目标**：**iOS 15.0**（硬性）
- **语言**：Swift 5.9+；UI：SwiftUI 壳 + UIKit 核
- **第三方依赖**：**0 个**。只用系统框架（Photos, PhotosUI, CoreData, Vision, CoreImage, Accelerate, MapKit, LocalAuthentication, UIKit, SwiftUI）
- **网络**：**完全不用**。禁止 `URLSession` 外发、禁止任何分析/广告 SDK
- **Bundle ID**：`com.example.PhotoDesk`（`DEVELOPMENT_TEAM` 从环境变量注入，禁止硬编码进仓库）
- **构建方案已锁定（不要再讨论替代方案）**：**Windows 编辑 → Git 推送 → GitHub Actions `macos-14` 编译 → 手机验证**
- **开发环境（2026-10-24 已探测，见 docs/08）**：Agent 与用户同为 **Windows 10 原生**（Git Bash/MINGW64）。
  - ❌ 无 Xcode / 无本机 iOS 模拟器 → 本机**永远**不能编译、签名、运行 iOS App。
  - ✅ 已装 Docker 29.8.2（daemon 需启动）；WSL2 只有 `docker-desktop`，**不安装 Ubuntu**。
  - 本地跑 `PhotoDeskCore` 的 `swift test`：只用 **Docker 容器** `swift:6.0-noble`，走 `scripts/test-core.ps1`。
  - 编译/测试/出包：GitHub Actions `macos-14`；CI 产出模拟器 `.app` 与**未签名 ipa**。
  - 验证：Windows 上用 **AltServer** 把 ipa 签名装到 iPhone（免费账号 7 天续签；付费账号可 CI 全自动签名）。
  - ❌ **禁止**建议：安装 WSL2 Ubuntu、迁移 Linux、装 ZCode「iOS 模拟器」插件（硬检 `platform === "darwin"`）、
    Hackintosh、macOS 虚拟机、Windows 原生 Swift 工具链、Linux/Windows 交叉编译 iOS。

---

## 1.5 两条红线（违反即打回）

### 红线 1：永不永久删除

- 应用内所有"删除"**只能**是 `PHAssetChangeRequest.deleteAssets` → 移入**系统「最近删除」**（系统保留 30 天后自动清除）。
- **禁止**：实现永久擦除、提供"彻底删除/永久删除"入口、清空「最近删除」、任何绕过系统回收站的路径。
- **UI 文案统一**：说「移到最近删除」，不要出现「彻底删除」「永久删除」。
- 沙盒 `TrashBin` 只是**撤销保险副本**（弥补 iOS 无法程序化恢复「最近删除」），不是备份：上限 2GB、按时间淘汰、设置可关闭。
- 回收语义总结给用户看的两条恢复路径：① 撤销窗口内（5s）App 内一键撤销；② 30 天内在系统相册恢复。

### 红线 2：`PhotoDeskCore` 零 Apple 依赖

- `PhotoDeskCore/` 是独立 SwiftPM 包，必须能在 Linux 上 `swift build && swift test`。
- 只允许 `import Foundation`；**禁止** `import UIKit / SwiftUI / Photos / PhotosUI / Vision / CoreImage / Accelerate`。
- 输入用基础类型（`Double`、`[UInt8]`、`Date`、自定义 struct），不传 `CGSize` / `UIImage` / `PHAsset`。
- `Package.swift` 的 `platforms:` 留空；App 侧用 `.package(path: "../PhotoDeskCore")` 引入并只做类型适配，**不重复实现**。

---

## 2. iOS 15 API 黑名单（**禁止直接使用**）

| 禁用 | 起始版本 | 替代方案 |
|---|---|---|
| `NavigationStack` / `NavigationPath` | 16 | `NavigationView` + `.navigationViewStyle(.stack)`，或自建 `Router` |
| `PhotosPicker`（SwiftUI） | 16 | `PHPickerViewController` + `UIViewControllerRepresentable` |
| `ShareLink` | 16 | `UIActivityViewController` 包装 |
| `Swift Charts` | 16 | 自绘 SwiftUI `Path`/`Shape` |
| `@Observable` / `@Bindable` | 17 | `ObservableObject` + `@StateObject` / `@ObservedObject` |
| `ContentUnavailableView` | 17 | 自写 `DSEmptyState` |
| `.scrollContentBackground` / `.scrollTargetBehavior` / `.scrollPosition` | 16/17 | UIKit 或 `ScrollViewReader` |
| `ImageRenderer` | 16 | `UIGraphicsImageRenderer` |
| `.fontDesign()` | 16 | 手动字体 |
| `.toolbarBackground` | 16 | `UINavigationBar.appearance()` |
| SwiftData | 17 | Core Data |

**允许**：`LazyVGrid`、`async/await`、`.searchable`、`.refreshable`、`Material`、`PencilKit`、`Vision`、`MapKit`、`Core Data`、`UICollectionViewDiffableDataSource`、`UICollectionViewCompositionalLayout`、`PHPhotoLibrary.requestAuthorization(for:)`、`OSLogStore`。

> 若确需新 API，必须写成双实现：
> ```swift
> if #available(iOS 16, *) { /* 新 API */ } else { /* 回退实现 */ }
> ```

---

## 3. 架构规则

1. **单向依赖**：`Features → Domain(ViewModel) → Core(Service) → System`。Feature 层**不得直接引用 `PHAsset`**，统一用 `PhotoItem` 值类型。
2. **Service 全部 protocol 化**（`PhotoLibraryServiceProtocol` 等），ViewModel 通过构造器注入，便于 Mock 测试。
3. **网格与全屏浏览器用 UIKit**（`UICollectionView` + Compositional Layout + Diffable DataSource + `UICollectionViewDataSourcePrefetching`）。**不要用 SwiftUI `LazyVGrid`**（iOS 15 万级滚动性能不达标）。
4. **Async**：统一 `async/await`，不用 Combine（除 `PHPhotoLibraryChangeObserver` 回调桥接）。
5. **线程**：UI `@MainActor`；图片解码串行队列（max 4）；分析计算 `TaskGroup(maxConcurrent: 4)` + `qos: .utility`；Core Data 写走 `performBackgroundTask`。
6. **图片加载**必须走 `ImagePipeline`（内存 NSCache 60MB → 磁盘 LRU 200MB → `PHCachingImageManager`），禁止在 View 里直接 `requestImage`。
7. **核心纯逻辑下沉 `PhotoDeskCore`**（见红线 2）：新增"手势判定 / 日期分组 / 哈希 / 去重分组 / 撤销策略 / 回收站淘汰"类代码时，**先问自己能否放进 `PhotoDeskCore`**，能放就必须放，并同步写 XCTest。

---

## 4. 照片库操作规则（PhotoKit）

1. 所有写操作必须在 `PHPhotoLibrary.shared().performChanges { }` 内，并处理 `completionHandler` 的 error。
2. **隐藏**用 `PHAssetChangeRequest(for:).isHidden = true`（已确认公开 API，iOS 8+）。主网格查询必须设 `PHFetchOptions.includeHiddenAssets = false`。
3. **移到「最近删除」**用 `PHAssetChangeRequest.deleteAssets`（唯一实现）。它必然触发系统确认弹窗，无法绕过 → 不要试图屏蔽。执行前必须先落撤销保险副本（见红线 1）。
4. iOS 无公开 API 从「最近删除」恢复 → 执行删除前必须先用 `requestContentEditingInput` 拿原件写入 App 沙盒 `TrashBin`（`ApplicationSupport/_Trash`）；撤销窗口内用 `PHAssetCreationRequest.fromImage(atFileURL:)` 重建，并恢复 `creationDate` / `location`。iCloud-only 资源未下载时**拒绝执行**。
5. `.limited` 受限授权必须支持：所有功能基于可见 asset，提供 `presentLimitedLibraryPicker` 入口。
6. 必须注册 `PHPhotoLibraryChangeObserver`，用 Diffable DataSource 做**增量**更新，禁止整库 reload。
7. 分批 fetch（每批 500），禁止一次性 `enumerateObjects` 全库。

---

## 5. 代码规范

- 文件组织：按 `docs/03 §3` 的目录，**不要自创目录**。
- 命名：`XxxViewModel`、`XxxService`、`XxxViewController`、`XxxView`；SwiftUI View 内部再拆 `XxxRow` / `XxxOverlay`。
- 每个文件顶部写一行 `// MARK: - 职责说明`。
- 魔法数字必须进 `DesignSystem` 或 `SwipeConfig`，禁止散落。
- 颜色/字体/间距**只用** `UI/DesignSystem` 里的 token，禁止硬编码 `Color(...)`。
- 错误处理：不用 `try!` / `!`（除 IBOutlet 与已确保非空的 `PHFetchResult.object(at:)`）；用 `guard let else { return }` 早退。
- 新增文件**必须加入 Xcode target membership**（XcodeGen 方案下自动包含，注意 `excludes`）。
- 每个 PR 不得让 Xcode 警告数增加。

---

## 6. 每个任务的 Definition of Done

1. 代码在 **iOS 15.0** 编译通过（`-destination 'platform=iOS Simulator,OS=15.5'`）。
2. 若改动波及核心逻辑：`scripts/test-core.ps1`（**Docker `swift:6.0-noble`**）在本机通过 —— 无 Mac 时的本地门禁。
2. 新增核心逻辑有单元测试；新增交互路径有 UI 测试或明确的手动验证步骤。
3. 内存峰值 < 250MB，滚动 ≥ 55 FPS。
4. 中文文案已按 `docs/04 §7` 校对。
5. 更新 `docs/05-开发进程与里程碑.md` 的进度表与变更日志。
6. Commit 信息格式：`feat(viewer): 实现上滑手势状态机`。

---

## 7. 常见陷阱（踩过的坑）

| 陷阱 | 表现 | 规避 |
|---|---|---|
| Deployment Target 被引擎依赖抬高 | 老设备 dyld 崩溃 | 用 `otool -l \| grep LC_BUILD_VERSION` 校验 minos = 15.0 |
| SwiftUI `NavigationView` 双层导航 | iPad 上 split 显示异常 | 加 `.navigationViewStyle(.stack)` |
| 缩放状态下手势冲突 | 放大后上下滑误触发 | `gestureRecognizerShouldBegin` 检查 `zoomScale <= 1.01` |
| 一次性加载全库 | 内存爆、启动慢 | 分批 500 + Diffable 增量 |
| 删除后无法撤销 | 数据丢失 | TrashBin 必做 |
| 免费账号用了 App Groups | 签名失败 | 禁用所有 Capability |
| iOS 15 无 Face ID（模拟器） | 保险箱打不开 | `targetEnvironment(simulator)` 时跳过 |
