// MARK: - 职责说明：App 入口——两个 Tab：照片库 / 工具（docs/04 §2 信息架构）。
// 照片库 Tab 由 LibraryRootView 驱动：授权引导 → 加载骨架 → 网格（空态/受限横幅随状态切换）。
// docs/09 D06：App 锁覆盖层（冷启动/后台超时重新锁）+ scenePhase 隐私遮罩（防 App Switcher 截屏）。
// 颜色一律取自 DesignSystem token（AGENTS.md §5）。

import SwiftUI

@main
struct PhotoDeskApp: App {
    @StateObject private var container = AppContainer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView {
                    LibraryRootView(viewModel: container.libraryViewModel,
                                    service: container.libraryService,
                                    undoCenter: container.undoCenter)
                        .tabItem { Label("照片库", systemImage: "photo.stack") }

                    ToolsView()
                        .tabItem { Label("工具", systemImage: "wrench.and.screwdriver") }
                }
                // 隐私遮罩：切后台瞬间盖住内容（App 锁开启或保险箱已解锁时）
                if scenePhase != .active,
                   container.appLock.lockEnabled || container.vaultService.isUnlocked {
                    PrivacyShield()
                        .zIndex(1)
                }
                // App 锁（冷启动 / 后台超宽限期重新锁）
                if container.appLock.isLocked {
                    AppLockView(appLock: container.appLock)
                        .zIndex(2)
                }
            }
            .onChange(of: scenePhase) { phase in
                container.appLock.handleScenePhase(phase)
            }
        }
    }
}
