// MARK: - 职责说明：四态空态组件（docs/05 M1 任务 1.7 / docs/04 §3.1、§6）——
// 空（无照片）/ 加载骨架屏（shimmer）/ 无权限（去系统设置）/ 受限授权（管理选中照片横幅）。
// 文案口径见 docs/04 §7；颜色/字体一律 DesignSystem token（AGENTS.md §5）。

import SwiftUI
import UIKit

struct DSEmptyState: View {
    enum Kind {
        case loading
        case empty
        case denied
        case limited
    }

    let kind: Kind
    /// .limited 的「管理」按钮 / .denied 的「去系统设置」回调
    var onAction: (() -> Void)?

    var body: some View {
        switch kind {
        case .loading:
            SkeletonGridView()
        case .empty:
            VStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 48))
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Text("还没有照片")
                    .font(.headline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text("去拍一张或导入几张试试")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 48))
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Text("无法访问照片")
                    .font(.headline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text("请在系统设置中允许访问照片")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Button {
                    onAction?()
                } label: {
                    Text("去系统设置开启")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(ds: DSColor.tint))
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .limited:
            // 横幅形态：悬浮于网格底部（docs/04 §3.1 受限授权）
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Text("正在显示部分照片")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Spacer()
                Button {
                    onAction?()
                } label: {
                    Text("管理")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.tint))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(ds: DSColor.bgSecondary))
            .cornerRadius(DSSpacing.cardCornerRadius)
            .padding(.horizontal, DSSpacing.screenPadding)
        }
    }
}

/// 骨架屏：灰色圆角块 + 透明度呼吸（shimmer），尊重「减弱动态效果」（docs/04 §6）
private struct SkeletonGridView: View {
    @State private var phase = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: DSSpacing.gridSpacing)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DSSpacing.gridSpacing) {
                ForEach(0..<36, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DSSpacing.gridCornerRadius)
                        // 分隔线 token 做骨架底色（bgSecondary #F2F2F7 在白底上几乎不可见）
                        .fill(Color(ds: DSColor.separator))
                        .aspectRatio(1, contentMode: .fit)
                        .opacity(phase ? 0.55 : 1.0)
                }
            }
            .padding(DSSpacing.gridSpacing)
        }
        .onAppear {
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
        }
    }
}
