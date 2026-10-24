// MARK: - 职责说明：App 入口——两个 Tab：照片库 / 工具（docs/04 §2 信息架构，首版固定 2 Tab）。
// M1 起照片库 Tab 换为 Features/Library 的 UIKit 网格（UIViewControllerRepresentable 包装）；
// 工具 Tab 换为清理/相簿/统计/设置入口。颜色一律取自 DesignSystem token（AGENTS.md §5）。

import SwiftUI

@main
struct PhotoDeskApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Text("照片库")
                    .font(.largeTitle)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(ds: DSColor.bgPrimary))
                    .tabItem { Label("照片库", systemImage: "photo.stack") }

                Text("工具")
                    .font(.largeTitle)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(ds: DSColor.bgSecondary))
                    .tabItem { Label("工具", systemImage: "wrench.and.screwdriver") }
            }
        }
    }
}
