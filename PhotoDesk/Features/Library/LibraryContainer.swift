// MARK: - 职责说明：照片库 SwiftUI 桥接与根视图（docs/05 M1；docs/16 M12 R05/R06/R07 重构 v2）——
// R05：顶部无 App 标题（无 .navigationTitle；Info.plist 的 CFBundleDisplayName 是系统桌面名，不动）；
// R06：五段 ScopePicker 整行移除 → 顶部栏「分类」菜单按钮（LibraryCategoryMenuBuilder，紧邻筛选，
//      分类与筛选是两个独立控件，绝不合并）；
// R07：TabView 移除 → 左上「工具」小按钮点开 ToolsView sheet。
// v2 关键（docs/16 §3.2「薄 UINavigationController host」路线）：SwiftUI NavigationView 内嵌
// UIViewControllerRepresentable 的 navigationItem 不会显示（导航栈宿主是 SwiftUI 的 hosting VC）——
// LibraryContainer 直接返回 UINavigationController(rootViewController:)，顶部栏按钮全部由 UIKit
// navigationItem 承载（iOS 15.5 下 SwiftUI Toolbar/Menu 对 XCUITest 合成点击不可靠，docs/15 §3.2）。
// 保留：授权四态、筛选空态、Vault fullScreenCover（Face ID）、查看器 ViewerContext、会话徽标、
//       恢复横幅、隐私遮罩/App 锁（在 PhotoDeskApp）、UI 测试钩子。

import SwiftUI
import UIKit

struct LibraryRootView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @ObservedObject var service: PhotoLibraryService
    @ObservedObject var undoCenter: UndoCenter
    @State private var viewerContext: ViewerContext?
    @State private var showSearch = false
    @State private var showFilterSheet = false
    @State private var showMonthJump = false
    @State private var showVault = false
    /// R07：左上「工具」按钮 → ToolsView sheet
    @State private var showTools = false
    @State private var showSessionReview = false
    /// 排序接线（docs/09 D10）：外观设置页 @AppStorage("grid.sortAsc") 变化 → 查询重载
    @AppStorage("grid.sortAsc") private var sortAscending = false
    /// 「多选」按钮 → UIKit 控制器桥
    @StateObject private var selectionBridge = SelectionModeBridge()
    /// 重启恢复横幅（docs/05 M3 验收：重启后 10 秒内提示「上次有 N 个操作可撤销」）
    @State private var recoveryCount = 0
    @State private var showRecovery = false
    @State private var hadActiveEntry = false
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    /// UI 测试钩子：-uiTestingViewerStartIndex 启动即打开第 n 张查看器（只触发一次）
    @State private var hookViewerOpened = false
    /// UI 测试钩子：网格就绪后自动打开筛选/月份面板（docs/13 M11）
    @State private var hookSheetOpened = false
    #endif

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .notDetermined:
                PermissionIntroView(mode: .intro) {
                    Task { await viewModel.requestAccess() }
                }
            case .denied:
                PermissionIntroView(mode: .denied) {
                    Task { await viewModel.requestAccess() }
                }
            case .restricted:
                PermissionIntroView(mode: .restricted, action: nil)
            case .loading:
                DSEmptyState(kind: .loading)
            case .empty:
                DSEmptyState(kind: .empty)
            case .ready:
                // docs/16 M12：只剩网格（五段 ScopePicker 整行已移除 → 顶部栏分类菜单）；
                // 顶部栏由 LibraryContainer 的 UINavigationController 承载（无 App 标题）
                ZStack {
                    LibraryContainer(viewModel: viewModel,
                                     onOpenViewer: { item in
                                         viewerContext = ViewerContext(
                                             items: viewModel.filteredItems,
                                             startItemID: item.id,
                                             queryKey: viewModel.query.key)
                                     },
                                     selectionBridge: selectionBridge,
                                     onOpenFilter: {
                                         showFilterSheet = true
                                     },
                                     onOpenSearch: {
                                         showSearch = true
                                     },
                                     onOpenMonthJump: {
                                         showMonthJump = true
                                     },
                                     onOpenTools: {
                                         showTools = true
                                     },
                                     onShowVault: {
                                         showVault = true
                                     })
                    if viewModel.filteredItems.isEmpty && viewModel.query.filter.isActive && viewModel.isIndexComplete {
                        filterEmptyState
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(items: viewModel.itemsSnapshot) { predicate in
                // 「应用筛选到主库」（docs/09 D15）
                viewModel.setFilter(predicate)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            LibraryFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showMonthJump) {
            // docs/13 S09/S10：月份面板（跳转 / 单月全选 / 回到顶部）
            MonthJumpSheet(sections: viewModel.sections,
                           onSelect: { sectionIndex in
                               selectionBridge.controller?.scrollToSection(sectionIndex)
                           },
                           onSelectAll: { sectionIndex in
                               selectionBridge.controller?.enterMonthSelection(sectionIndex: sectionIndex)
                           },
                           onScrollToTop: {
                               selectionBridge.controller?.scrollToTop()
                           })
        }
        .sheet(isPresented: $showTools) {
            // R07：工具页改左上入口 sheet（保留 NavigationView(.stack) 支撑子页推入）
            ToolsView()
        }
        .sheet(isPresented: $showSessionReview) {
            SessionReviewView(session: AppContainer.shared.reviewSession,
                              pipeline: AppContainer.shared.imagePipeline,
                              settings: AppContainer.shared.settings) {
                showSessionReview = false
            }
        }
        .fullScreenCover(isPresented: $showVault) {
            NavigationView {
                VaultView(viewModel: AppContainer.shared.makeVaultViewModel(),
                          onClose: { showVault = false })
            }
            .navigationViewStyle(.stack)
        }
        .overlay(alignment: .top) {
            if showRecovery, recoveryCount > 0 {
                HStack(spacing: 12) {
                    Text("上次有 \(recoveryCount) 个操作可撤销")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Spacer()
                    Button {
                        Task {
                            await viewModel.undoLatest()
                            recoveryCount = 0
                        }
                    } label: {
                        Text("撤销")
                            .font(.subheadline)
                            .foregroundColor(Color(ds: DSColor.tint))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(ds: DSColor.bgSecondary))
                .cornerRadius(DSSpacing.cardCornerRadius)
                .padding(.horizontal, DSSpacing.screenPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fullScreenCover(item: $viewerContext) { context in
            // 拆小表达式（docs/13 轮 6：复杂泛型链会拖垮类型检查——独立 View 承载）
            ViewerCover(context: context, viewerContext: $viewerContext)
        }
        .onAppear {
            Task { await viewModel.start() }
            // 重启恢复：读取未过期 ActionLog（即刻提示，保持至撤销或窗口过期）
            recoveryCount = undoCenter.recoverableCount()
            undoCenter.restoreLatestIfNeeded()
            showRecovery = recoveryCount > 0
        #if DEBUG
            runHooksIfNeeded()
        #endif
        }
        .onChange(of: viewModel.viewState) { _ in
            #if DEBUG
            runHooksIfNeeded()
            #endif
        }
        .onChange(of: sortAscending) { ascending in
            // 排序接线（docs/09 D10）：外观设置页开关 / 菜单 → 查询重载
            Task { await viewModel.setSort(ascending: ascending) }
        }
        .onChange(of: scenePhase) { phase in
            // docs/13 S04/S11：进后台/失活立即保存位置（杀进程前最后一道保存）
            if phase != .active {
                selectionBridge.controller?.savePositionNow(reason: "scenePhase")
            }
        }
        .onReceive(service.$access) { _ in
            Task { await viewModel.start() }
        }
        .onReceive(undoCenter.$activeEntry) { entry in
            // 活跃条目从有到无（已撤销/过期）→ 收起横幅（初始 nil 不触发，避免误清计数）
            let has = entry != nil
            if hadActiveEntry && !has {
                showRecovery = false
                recoveryCount = 0
            }
            hadActiveEntry = has
        }
        #if DEBUG
        // CI 截图自诊断：网格异常时可直接读出 VM 状态（Release 不编译；不拦截触摸）
        .overlay(alignment: .top) {
            Text(viewModel.debugSummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(ds: DSColor.textPrimary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(ds: DSColor.accentFavorite))
                .cornerRadius(4)
                .padding(.top, 2)
                .allowsHitTesting(false)
                .accessibilityIdentifier("Library-DebugSummary")
                .accessibilityLabel("调试汇总")
                .accessibilityValue(viewModel.debugSummary)
        }
        #endif
    }

    // MARK: - 筛选无结果空态（docs/09 D10 §6）

    private var filterEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Text("没有符合筛选条件的照片")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Button {
                viewModel.clearFilter()
            } label: {
                Text("清除筛选")
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(ds: DSColor.tint))
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .accessibilityIdentifier("Library-Clear-Filter")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(ds: DSColor.bgPrimary))
    }
}

/// 查看器承载视图（R01：onClose 复位 viewerContext；独立 View 规避 body 类型检查超时）
private struct ViewerCover: View {
    let context: ViewerContext
    @Binding var viewerContext: ViewerContext?

    var body: some View {
        let viewerViewModel = AppContainer.shared.makeViewerViewModel(context: context)
        ViewerContainer(viewModel: viewerViewModel,
                        onClose: { viewerContext = nil })
    }
}

/// UI 测试钩子（docs/09 Phase 0）：网格就绪后自动打开第 n 张查看器
#if DEBUG
private extension LibraryRootView {
    func openHookViewerIfNeeded() {
        guard !hookViewerOpened, viewModel.viewState == .ready,
              let index = UITestHooks.intValue("-uiTestingViewerStartIndex"),
              viewModel.filteredItems.indices.contains(index) else { return }
        hookViewerOpened = true
        viewerContext = ViewerContext(items: viewModel.filteredItems,
                                      startItemID: viewModel.filteredItems[index].id,
                                      queryKey: viewModel.query.key)
    }

    /// UI 测试钩子集中入口（每次状态变化时调用；各自内部有一次性守卫）
    func runHooksIfNeeded() {
        openHookViewerIfNeeded()
        openHookSheetIfNeeded()
    }

    /// docs/13 M11：网格就绪后自动打开筛选/月份面板（每次 launch 只触发一次）
    func openHookSheetIfNeeded() {
        guard !hookSheetOpened, viewModel.viewState == .ready else { return }
        if UITestHooks.enabled("-uiTestingOpenFilterSheet") {
            hookSheetOpened = true
            showFilterSheet = true
        } else if UITestHooks.enabled("-uiTestingOpenMonthJump") {
            hookSheetOpened = true
            showMonthJump = true
        }
    }
}
#endif

/// 多选模式桥（docs/04 §3.1「多选」入口）：UIBarButtonItem → UIKit 控制器
final class SelectionModeBridge: ObservableObject {
    weak var controller: LibraryViewController?
}

/// 薄 UINavigationController host（docs/16 M12 §3.2）：
/// LibraryViewController 作为导航根，顶部栏按钮由其 navigationItem 承载。
struct LibraryContainer: UIViewControllerRepresentable {
    @ObservedObject var viewModel: LibraryViewModel
    /// 点击 cell → 打开全屏浏览器（assetID 上下文，docs/09 D01）
    let onOpenViewer: (PhotoItem) -> Void
    /// 「多选」按钮与 UIKit 控制器的桥
    let selectionBridge: SelectionModeBridge
    /// 多选操作行「筛选」按钮 → 打开筛选面板（docs/13 S06）
    let onOpenFilter: () -> Void
    /// M12 R05/R06/R07：唯一顶部栏回调（UIKit navigationItem 按钮 → SwiftUI sheet/cover）
    let onOpenSearch: () -> Void
    let onOpenMonthJump: () -> Void
    let onOpenTools: () -> Void
    let onShowVault: () -> Void
    @AppStorage("grid.columns") private var gridColumns = 3
    @AppStorage("grid.sortAsc") private var sortAscending = false

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigationController = AppContainer.shared.libraryHostController
        updateHostController(navigationController)
        return navigationController
    }

    func updateUIViewController(_ navigationController: UINavigationController, context: Context) {
        updateHostController(navigationController)
    }

    private func updateHostController(_ navigationController: UINavigationController) {
        guard let controller = navigationController.viewControllers.first as? LibraryViewController else { return }
        controller.setColumns(gridColumns)
        controller.onOpenViewer = onOpenViewer
        controller.onOpenFilter = onOpenFilter
        controller.onOpenSearch = onOpenSearch
        controller.onOpenMonthJump = onOpenMonthJump
        controller.onOpenTools = onOpenTools
        controller.onShowVault = onShowVault
        selectionBridge.controller = controller
    }
}
