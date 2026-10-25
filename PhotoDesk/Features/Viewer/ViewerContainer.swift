// MARK: - 职责说明：全屏浏览器 SwiftUI 桥接（docs/05 M2 任务 2.1）——
// LibraryRootView 以 .fullScreenCover(item:) 呈现（iOS 15 无 NavigationStack，M0 已定 ZStack/cover 路线）；
// zoom 转场需自定义 UIViewControllerTransitioning（docs/04 §4.1），M2 先用系统全屏呈现。

import SwiftUI

struct ViewerAnchor: Identifiable {
    let id = UUID()
    let startIndex: Int
}

struct ViewerContainer: UIViewControllerRepresentable {
    let viewModel: ViewerViewModel

    func makeUIViewController(context: Context) -> ViewerViewController {
        ViewerViewController(viewModel: viewModel,
                             pipeline: AppContainer.shared.imagePipeline,
                             settings: AppContainer.shared.settings,
                             undoCenter: AppContainer.shared.undoCenter)
    }

    func updateUIViewController(_ controller: ViewerViewController, context: Context) {}
}
