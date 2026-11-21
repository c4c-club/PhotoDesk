# T03 — 授权恢复 UI 与导入入口

> 依赖：T02。状态：⬜。预计：1d。
> 只读：00-索引、本卡；可读 PermissionIntroView.swift、DSEmptyState.swift、LibraryContainer.swift、PhotoWriter.swift、AppContainer.swift 与 T02 代码。不要读 T04–T08。

## 1. 目标

把 T02 的授权状态真正接到 UI：denied 能去系统设置；limited 零照片能管理可见照片；authorized 空库能导入照片；从设置/picker 返回自动刷新。

## 2. 生产改动

### 2.1 PermissionIntroView.swift

- 改为显式动作签名（intro / denied / restricted）。
- 按钮与 ID 表：
  - intro：允许访问照片 / Permission-Allow；可选暂不授权 / Permission-Later。
  - denied：去系统设置 / Permission-Open-Settings；重新检查授权 / Permission-Recheck。
  - restricted：重新检查授权 / Permission-Recheck。
- denied 说明文案必须包含「系统不会再次弹出授权框；请到系统设置 → 隐私与安全性 → 照片 开启」。
- 主按钮不能调用 requestAccess 来假装弹窗；主按钮 onOpenSettings。
- recheck 后仍 denied：显示内联提示「仍未授权，请到系统设置开启」。
- 所有按钮加 accessibilityIdentifier；不硬编码颜色/字号；Dynamic Type 不裁切。
- 用 DesignSystem token；不新增目录。

### 2.2 DSEmptyState.swift

- 增加可选 actionTitle / actionAccessibilityID / onAction。
- .empty 由调用方传「导入照片」/ Library-Import。
- .limited 由调用方传「管理可见照片」/ Permission-Manage-Limited。
- action 为 nil 时不显示按钮、不占位。
- 保持 .limited 横幅现有视觉能力；按钮用 DS token。

### 2.3 LibraryContainer.swift

- 六态 switch 完成：
  - .denied → PermissionIntroView(mode: .denied, onOpenSettings: openSettings, onRecheck: { Task { await viewModel.refreshAccessAndReload(force: true) } })
  - .limited → DSEmptyState(kind: .limited, actionTitle: 管理可见照片, actionID: Permission-Manage-Limited, onAction: viewModel.requestManageLimitedPhotos)
  - .empty → DSEmptyState(kind: .empty, actionTitle: 导入照片, actionID: Library-Import, onAction: showImportSheet)
  - .ready → 网格 + isLimitedAccess 时受限横幅（管理入口同 ID）。
- .onChange(of: scenePhase) active：Task { await viewModel.refreshAccessAndReload() }；保留原位置保存。
- openSettings：guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url)。
- PhotoImportSheet 以 sheet 呈现；成功后依赖 PhotoChangeObserver；失败显示中文错误。
- 不重复在 onAppear 里 requestAccess。

### 2.4 PhotoImportSheet.swift（新增）

- SwiftUI View，PhotosPicker(selection:maxSelectionCount:matching: .images)。
- 逐个 loadTransferable(type: Data.self)；写临时文件；调 PhotoWriterProtocol.saveNewImage(fromFile:creationDate:)；删除临时文件。
- 并发不超过 2；失败提示「无法读取所选照片」/「保存到照片库失败」。
- 仅 authorized 空态可达；limited 走管理；denied 不可达。
- 不引入 iOS 17 API。

### 2.5 AppContainer.swift

- 解析 -uiTestingPermissionState notDetermined/denied/restricted/limited/authorized，构造 PhotoLibraryService(initialAccess:)。
- 需要时增加 -uiTestingEmptyLibrary，确保 limited 0 与 authorized 0 可分别断言。
- 生产路径默认真实 PHPhotoLibrary；不要影响正常用户。

## 3. 测试

### 3.1 PermissionRecoveryUITests.swift（新增）

- denied：存在 Permission-Open-Settings；点 Permission-Recheck 后仍 denied 时出现提示文案。
- limited + empty：存在 Permission-Manage-Limited；不存在 Library-Import。
- authorized + empty：存在 Library-Import；点按后出现导入 sheet 标识（不必真的选照片）。
- intro：存在 Permission-Allow。
- 所有测试使用 launchArguments 注入，避免真实系统弹窗不确定。

### 3.2 单元/编译

- app target 编译通过；SwiftUI Preview 不需要。
- 若 PermissionIntroView 的 action 闭包可选，确保不会出现强解包。
- 检查所有新增按钮 ID 唯一。

## 4. 执行步骤

1. 写 UI 测试骨架（先红），确认 denied/limited/authorized 三态当前失败。
2. 改 PermissionIntroView + DSEmptyState；跑编译。
3. 改 LibraryContainer 六态、scenePhase、openSettings。
4. 新增 PhotoImportSheet 与 AppContainer 注入。
5. 跑 CI：PhotoDeskUITests/PermissionRecoveryUITests；记录 run id。
6. 手动验证步骤写入 progress：设置返回、limited picker 返回、导入 1 张。
7. commit：feat(library): 补齐授权恢复与照片导入入口。

## 5. 验收

- denied 主按钮是「去系统设置」，ID 正确；recheck 不假装弹窗。
- limited 0 张显示「管理可见照片」；limited 有照片显示横幅与管理入口。
- authorized 空库显示「导入照片」并能打开 PhotosPicker。
- 从设置/limited picker 返回 App 自动刷新；不要求用户猜按钮。
- Dynamic Type XXXL / iPhone SE 不裁切；VoiceOver 可读。
- 无新增 iOS 17 API、无强制解包。

## 6. BLOCKED 处理

如果 PhotosPicker 在模拟器无法完成真实导入，UI 测试只验证 sheet 出现；真实导入写入失败时记录 BLOCKED 与设备/模拟器原因。不要把「按钮存在」当成「导入成功」。

## 7. 下一卡

T04 — 混合命中 Core 与几何。完成并 commit 后才能读。
