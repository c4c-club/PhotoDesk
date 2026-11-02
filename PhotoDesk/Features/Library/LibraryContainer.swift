// MARK: - 职责说明：照片库 SwiftUI 桥接与根视图（docs/05 M1 任务 1.4/1.8；docs/09 Phase 2 重做）——
// LibraryRootView：顶部五段 ScopePicker（全部/收藏/视频/截图/已隐藏）+ 筛选栏 + 网格 + 会话徽标；
// 「已隐藏」弹出 VaultView（fullScreenCover）；筛选无结果空态（清除筛选）；筛选面板 sheet。
// LibraryContainer：UIViewControllerRepresentable 包装 LibraryViewController（UIKit 网格）。
// 查看器打开走 ViewerContext（assetID 定位，docs/09 D01）。

import SwiftUI
import UIKit

/// 顶部视图切换（docs/09 D15：全部/收藏/视频/截图/已隐藏）
enum LibraryScopeOption: String, CaseIterable, Identifiable {
    case all, favorites, videos, screenshots, hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:         return "全部"
        case .favorites:   return "收藏"
        case .videos:      return "视频"
        case .screenshots: return "截图"
        case .hidden:      return "已隐藏"
        }
    }

    var scope: PhotoScope? {
        switch self {
        case .all:         return .all
        case .favorites:   return .favorites
        case .videos:      return .videos
        case .screenshots: return .screenshots
        case .hidden:      return nil   // 走 VaultView，不是普通 scope
        }
    }
}

struct LibraryRootView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @ObservedObject var service: PhotoLibraryService
    @ObservedObject var undoCenter: UndoCenter
    /// 五段切换选中项（.hidden 只短暂存在，立即回弹并弹出 Vault）
    @State private var scopeOption: LibraryScopeOption = .all
    @State private var viewerContext: ViewerContext?
    @State private var showSearch = false
    @State private var showFilterSheet = false
    @State private var showVault = false
    @State private var showSessionReview = false
    /// 排序接线（docs/09 D10）：外观设置页 @AppStorage("grid.sortAsc") 变化 → 查询重载
    @AppStorage("grid.sortAsc") private var sortAscending = false
    /// 「多选」工具栏按钮 → UIKit 控制器桥
    @StateObject private var selectionBridge = SelectionModeBridge()
    /// 重启恢复横幅（docs/05 M3 验收：重启后 10 秒内提示「上次有 N 个操作可撤销」）
    @State private var recoveryCount = 0
    @State private var showRecovery = false
    @State private var hadActiveEntry = false
    #if DEBUG
    /// UI 测试钩子：-uiTestingViewerStartIndex 启动即打开第 n 张查看器（只触发一次）
    @State private var hookViewerOpened = false
    #endif

    var body: some View {
        NavigationView {
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
                    VStack(spacing: 0) {
                        scopePicker
                        LibraryFilterBar(viewModel: viewModel) {
                            showFilterSheet = true
                        }
                        ZStack {
                            LibraryContainer(viewModel: viewModel,
                                             onOpenViewer: { item in
                                                 viewerContext = ViewerContext(
                                                     items: viewModel.filteredItems,
                                                     startItemID: item.id,
                                                     queryKey: viewModel.query.key)
                                             },
                                             selectionBridge: selectionBridge)
                            if viewModel.filteredItems.isEmpty && viewModel.query.filter.isActive {
                                filterEmptyState
                            }
                        }
                    }
                }
            }
            .navigationTitle("照片管家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SessionBadgeView(session: AppContainer.shared.reviewSession) {
                        showSessionReview = true
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索与筛选")
                    .disabled(viewModel.viewState != .ready)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // docs/04 §3.1 底部工具栏「多选」入口（导航栏承载；与长按进入等价）
                    Button {
                        selectionBridge.controller?.toggleSelectionMode()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityIdentifier("Library-Select")
                    .accessibilityLabel("多选")
                    .disabled(viewModel.viewState != .ready)
                }
            }
        }
        .navigationViewStyle(.stack)   // iOS 15 双层导航陷阱（AGENTS.md §7）
        .sheet(isPresented: $showSearch) {
            SearchView(items: viewModel.itemsSnapshot) { predicate in
                // 「应用筛选到主库」（docs/09 D15）
                viewModel.setFilter(predicate)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            LibraryFilterSheet(viewModel: viewModel)
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
            ViewerContainer(viewModel: AppContainer.shared.makeViewerViewModel(context: context))
        }
        .onAppear {
            Task { await viewModel.start() }
            // 重启恢复：读取未过期 ActionLog（即刻提示，保持至撤销或窗口过期）
            recoveryCount = undoCenter.recoverableCount()
            undoCenter.restoreLatestIfNeeded()
            showRecovery = recoveryCount > 0
            openHookViewerIfNeeded()
        }
        .onChange(of: viewModel.viewState) { _ in
            openHookViewerIfNeeded()
        }
        .onChange(of: sortAscending) { ascending in
            // 排序接线（docs/09 D10）：外观设置页开关 / 菜单 → 查询重载
            Task { await viewModel.setSort(ascending: ascending) }
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
        // CI 截图自诊断：网格异常时可直接读出 VM 状态（Release 不编译）
        .overlay(alignment: .top) {
            Text(viewModel.debugSummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(ds: DSColor.textPrimary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(ds: DSColor.accentFavorite))
                .cornerRadius(4)
                .padding(.top, 2)
        }
        #endif
    }

    // MARK: - 顶部五段切换

    private var scopePicker: some View {
        Picker("视图", selection: $scopeOption) {
            ForEach(LibraryScopeOption.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DSSpacing.screenPadding)
        .padding(.vertical, 6)
        .accessibilityIdentifier("Library-ScopePicker")
        .onChange(of: scopeOption) { option in
            handleScopeChange(option)
        }
    }

    private func handleScopeChange(_ option: LibraryScopeOption) {
        guard let scope = option.scope else {
            // 「已隐藏」：弹出 Vault（docs/09 D15）；关闭后回弹到原 scope
            showVault = true
            DispatchQueue.main.async {
                scopeOption = scopeBeforeHidden
            }
            return
        }
        Task { await viewModel.setScope(scope) }
    }

    /// 进入「已隐藏」前的 scope（回弹目标）
    private var scopeBeforeHidden: LibraryScopeOption {
        switch viewModel.query.scope {
        case .favorites: return .favorites
        case .videos:    return .videos
        case .screenshots: return .screenshots
        default:         return .all
        }
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
}
#endif

/// 多选模式桥（docs/04 §3.1 底部工具栏「多选」入口）：SwiftUI 工具栏按钮 → UIKit 控制器
final class SelectionModeBridge: ObservableObject {
    weak var controller: LibraryViewController?
}

struct LibraryContainer: UIViewControllerRepresentable {
    @ObservedObject var viewModel: LibraryViewModel
    /// 点击 cell → 打开全屏浏览器（assetID 上下文，docs/09 D01）
    let onOpenViewer: (PhotoItem) -> Void
    /// 工具栏「多选」按钮与 UIKit 控制器的桥
    let selectionBridge: SelectionModeBridge
    @AppStorage("grid.columns") private var gridColumns = 3
    @AppStorage("grid.sortAsc") private var sortAscending = false

    func makeUIViewController(context: Context) -> LibraryViewController {
        let controller = LibraryViewController(viewModel: viewModel,
                                               pipeline: AppContainer.shared.imagePipeline,
                                               settings: AppContainer.shared.settings,
                                               positionStore: AppContainer.shared.positionStore)
        controller.setColumns(gridColumns)
        controller.onOpenViewer = onOpenViewer
        selectionBridge.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: LibraryViewController, context: Context) {
        controller.setColumns(gridColumns)
        selectionBridge.controller = controller
    }
}
