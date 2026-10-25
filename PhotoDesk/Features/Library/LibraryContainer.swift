// MARK: - 职责说明：照片库 SwiftUI 桥接与根视图（docs/05 M1 任务 1.4 / 1.8）——
// LibraryRootView：按授权/加载状态切换 授权引导页 / 四态空态 / 网格（.limited 附系统选择器入口横幅）；
// LibraryContainer：UIViewControllerRepresentable 包装 LibraryViewController（UIKit 网格，docs/02 §3.1），
// 列数经 @AppStorage("grid.columns") 双向记忆。

import SwiftUI
import UIKit

struct LibraryRootView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @ObservedObject var service: PhotoLibraryService
    @State private var viewerAnchor: ViewerAnchor?

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
                ZStack(alignment: .bottom) {
                    LibraryContainer(viewModel: viewModel) { index in
                        viewerAnchor = ViewerAnchor(startIndex: index)
                    }
                    if viewModel.isLimitedAccess {
                        DSEmptyState(kind: .limited) {
                            viewModel.requestManageLimitedPhotos()
                        }
                        .padding(.bottom, DSSpacing.toastBottomOffset)
                    }
                }
            }
        }
        .fullScreenCover(item: $viewerAnchor) { anchor in
            ViewerContainer(viewModel: AppContainer.shared.makeViewerViewModel(startIndex: anchor.startIndex))
        }
        .onAppear {
            Task { await viewModel.start() }
        }
        .onReceive(service.$access) { _ in
            Task { await viewModel.start() }
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

struct LibraryContainer: UIViewControllerRepresentable {
    @ObservedObject var viewModel: LibraryViewModel
    /// 点击 cell → 打开全屏浏览器（flatIndex）
    let onOpenViewer: (Int) -> Void
    @AppStorage("grid.columns") private var gridColumns = 3

    func makeUIViewController(context: Context) -> LibraryViewController {
        let controller = LibraryViewController(viewModel: viewModel,
                                               pipeline: AppContainer.shared.imagePipeline,
                                               settings: AppContainer.shared.settings)
        controller.setColumns(gridColumns)
        controller.onOpenViewer = onOpenViewer
        return controller
    }

    func updateUIViewController(_ controller: LibraryViewController, context: Context) {
        controller.setColumns(gridColumns)
    }
}
