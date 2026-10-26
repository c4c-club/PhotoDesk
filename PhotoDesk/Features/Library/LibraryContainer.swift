// MARK: - 职责说明：照片库 SwiftUI 桥接与根视图（docs/05 M1 任务 1.4 / 1.8）——
// LibraryRootView：按授权/加载状态切换 授权引导页 / 四态空态 / 网格（.limited 附系统选择器入口横幅）；
// LibraryContainer：UIViewControllerRepresentable 包装 LibraryViewController（UIKit 网格，docs/02 §3.1），
// 列数经 @AppStorage("grid.columns") 双向记忆。

import SwiftUI
import UIKit

struct LibraryRootView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @ObservedObject var service: PhotoLibraryService
    @ObservedObject var undoCenter: UndoCenter
    @State private var viewerAnchor: ViewerAnchor?
    @State private var showSearch = false
    /// 「多选」工具栏按钮 → UIKit 控制器桥
    @StateObject private var selectionBridge = SelectionModeBridge()
    /// 重启恢复横幅（docs/05 M3 验收：重启后 10 秒内提示「上次有 N 个操作可撤销」）
    @State private var recoveryCount = 0
    @State private var showRecovery = false
    @State private var hadActiveEntry = false

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
                    ZStack(alignment: .bottom) {
                        LibraryContainer(viewModel: viewModel,
                                         onOpenViewer: { index in
                            viewerAnchor = ViewerAnchor(startIndex: index)
                                         },
                                         selectionBridge: selectionBridge)
                        if viewModel.isLimitedAccess {
                            DSEmptyState(kind: .limited) {
                                viewModel.requestManageLimitedPhotos()
                            }
                            .padding(.bottom, DSSpacing.toastBottomOffset)
                        }
                    }
                }
            }
            .navigationTitle("照片管家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            SearchView(items: viewModel.itemsSnapshot)
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
        .fullScreenCover(item: $viewerAnchor) { anchor in
            ViewerContainer(viewModel: AppContainer.shared.makeViewerViewModel(startIndex: anchor.startIndex))
        }
        .onAppear {
            Task { await viewModel.start() }
            // 重启恢复：读取未过期 ActionLog（即刻提示，保持至撤销或窗口过期）
            recoveryCount = undoCenter.recoverableCount()
            undoCenter.restoreLatestIfNeeded()
            showRecovery = recoveryCount > 0
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
}

/// 多选模式桥（docs/04 §3.1 底部工具栏「多选」入口）：SwiftUI 工具栏按钮 → UIKit 控制器
final class SelectionModeBridge: ObservableObject {
    weak var controller: LibraryViewController?
}

struct LibraryContainer: UIViewControllerRepresentable {
    @ObservedObject var viewModel: LibraryViewModel
    /// 点击 cell → 打开全屏浏览器（flatIndex）
    let onOpenViewer: (Int) -> Void
    /// 工具栏「多选」按钮与 UIKit 控制器的桥
    let selectionBridge: SelectionModeBridge
    @AppStorage("grid.columns") private var gridColumns = 3

    func makeUIViewController(context: Context) -> LibraryViewController {
        let controller = LibraryViewController(viewModel: viewModel,
                                               pipeline: AppContainer.shared.imagePipeline,
                                               settings: AppContainer.shared.settings)
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
