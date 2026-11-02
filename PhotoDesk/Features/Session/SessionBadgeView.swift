// MARK: - 职责说明：待处理计数徽标（docs/09 D16 §2）——照片库/查看器顶部「待删除 N / 待隐藏 M」，
// 点击打开 SessionReviewView（整理回顾）。计数为 0 时隐藏。

import SwiftUI

struct SessionBadgeView: View {
    @ObservedObject var session: ReviewSessionController
    var onTap: () -> Void

    private var isEmpty: Bool {
        session.pendingDeleteCount == 0 && session.pendingHideCount == 0
    }

    var body: some View {
        if !isEmpty {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .font(.caption)
                    if session.pendingDeleteCount > 0 {
                        Text("待删除 \(session.pendingDeleteCount)")
                            .font(.caption)
                    }
                    if session.pendingHideCount > 0 {
                        Text("待隐藏 \(session.pendingHideCount)")
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(ds: DSColor.bgSecondary))
                .foregroundColor(Color(ds: DSColor.textPrimary))
                .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .accessibilityIdentifier("SessionBadge")
            .accessibilityLabel("待删除 \(session.pendingDeleteCount) 张，待隐藏 \(session.pendingHideCount) 张，点按查看整理回顾")
        }
    }
}
