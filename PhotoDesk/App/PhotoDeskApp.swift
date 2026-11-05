// MARK: - 职责说明：App 入口——R07：无底部分页（TabView 移除），照片库即根视图；
// 工具页由照片库左上「工具」按钮（Library-Tools）点开 sheet（docs/16 M12 §3）。
// LibraryRootView 驱动：授权引导 → 加载骨架 → 网格（空态/受限横幅随状态切换）。
// docs/09 D06：App 锁覆盖层（冷启动/后台超时重新锁）+ scenePhase 隐私遮罩（防 App Switcher 截屏），
// zIndex 保持 1/2 不变。颜色一律取自 DesignSystem token（AGENTS.md §5）。

import SwiftUI

@main
struct PhotoDeskApp: App {
    @StateObject private var container = AppContainer.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 崩溃取证（docs/13 §3.9）：未捕获异常 → last-exception.log（只取证，不拦截）
        AppCrashLogger.install()
        #if DEBUG
        // UI 测试钩子：坐标点击稳定性（不是修复手段，docs/13 Phase 0）
        if UITestHooks.enabled("-uiTestingDisableAnimations") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // R07：直接放 LibraryRootView（无 TabBar；libraryViewModel 常驻不丢）
                LibraryRootView(viewModel: container.libraryViewModel,
                                service: container.libraryService,
                                undoCenter: container.undoCenter)
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
