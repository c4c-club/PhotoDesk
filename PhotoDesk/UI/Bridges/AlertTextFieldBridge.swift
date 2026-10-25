// MARK: - 职责说明：iOS 15 兼容的带文本框弹窗桥接——SwiftUI `.alert` 内嵌 TextField 是 iOS 16+
// （AGENTS.md §2 黑名单），命名/新建相簿等需要输入的场景经本桥接用 UIAlertController 呈现。

import SwiftUI
import UIKit

struct AlertWithTextField: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let title: String
    let placeholder: String
    let initialText: String
    let actionTitle: String
    /// 提交回调（空文本由调用方自行处理）
    let onCommit: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.isPresenting else { return }
        context.coordinator.isPresenting = true

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = placeholder
            field.text = initialText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            isPresented = false
            context.coordinator.isPresenting = false
        })
        alert.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            onCommit(text)
            isPresented = false
            context.coordinator.isPresenting = false
        })

        topViewController()?.present(alert, animated: true)
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
