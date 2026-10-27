// MARK: - 职责说明：iOS 15 导航 Router（docs/03 §2）——NavigationStack 属 iOS 16（AGENTS.md §2 黑名单），
// 自建 path 栈 + Route 枚举；首版按 docs/03 §2 推荐路线：ZStack + 自定义 Transition 手工管理 push/pop，
// 页面栈 ≤ 3 层，Viewer 用 .fullScreenCover 呈现。
// 实际落地说明：M5 起导航由 SwiftUI NavigationView(.stack) + NavigationLink 承担（层浅够用），
// 本占位保留作 M9+ 深层导航需求（如多级下钻回栈）的备选方案记录。
