// MARK: - 职责说明：全屏浏览器 SwiftUI 桥接（docs/05 M2 任务 2.1；docs/16 M12 R01 附带）——
// LibraryRootView 以 .fullScreenCover(item:) 呈现（iOS 15 无 NavigationStack，M0 已定 ZStack/cover 路线）；
// zoom 转场需自定义 UIViewControllerTransitioning（docs/04 §4.1），M2 先用系统全屏呈现。
// M12：onClose 接线复位 viewerContext——旧版全项目无赋值 → 关闭后 fullScreenCover 的 item 仍非 nil，
// 再次打开时 updateUIViewController 空实现导致复用旧 ViewerViewModel（旧 items/旧 index）。

import SwiftUI

struct ViewerAnchor: Identifiable {
    let id = UUID()
    let startIndex: Int
}

struct ViewerContainer: UIViewControllerRepresentable {
    let viewModel: ViewerViewModel
    /// 关闭回调（复位 viewerContext；fullScreenCover(item:) 复开时走 makeUIViewController 重建 VM）
    var onClose: (() -> Void)?

    func makeUIViewController(context: Context) -> ViewerViewController {
        let controller = ViewerViewController(viewModel: viewModel,
                                              pipeline: AppContainer.shared.imagePipeline,
                                              settings: AppContainer.shared.settings,
                                              undoCenter: AppContainer.shared.undoCenter)
        controller.onClose = onClose
        return controller
    }

    func updateUIViewController(_ controller: ViewerViewController, context: Context) {
        // 每次刷新重接 onClose（闭包捕获的状态绑定保持最新）
        controller.onClose = onClose
    }
}
