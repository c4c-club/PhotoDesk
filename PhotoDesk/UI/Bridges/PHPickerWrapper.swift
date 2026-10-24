// MARK: - 职责说明：UIKit 桥接层占位（docs/03 §3 UI/Bridges）——
// iOS 15 无 SwiftUI PhotosPicker / ShareLink（AGENTS.md §2 黑名单），导入 / 分享 / 文档选择 / Live Photo 预览
// 一律经 UIViewControllerRepresentable 包装为 SwiftUI 可用组件。规划文件：
// PHPickerWrapper（M6 导入）· ActivityViewWrapper（M6 分享）· DocumentPickerWrapper（M6 批量导出）· LivePhotoViewWrapper。
// TODO(P6): 首个落位 PHPickerViewController + UIViewControllerRepresentable。
