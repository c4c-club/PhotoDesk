// MARK: - 职责说明：分享桥接（docs/05 M6 任务 2）——
// UIActivityViewController 包装（iOS 15 无 ShareLink，AGENTS.md §2）。
// 用法：在 SwiftUI 层级挂载本视图（零尺寸），isPresented 置真时从顶层 VC 弹出分享面板。

import SwiftUI
import UIKit

struct ActivityViewWrapper: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.isPresenting else { return }
        context.coordinator.isPresenting = true

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
            context.coordinator.isPresenting = false
        }
        // iPad popover 锚点（挂在宿主控制器视图上）
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX,
                                                                    y: controller.view.bounds.maxY,
                                                                    width: 0, height: 0)
        topViewController()?.present(activity, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var isPresenting = false
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
