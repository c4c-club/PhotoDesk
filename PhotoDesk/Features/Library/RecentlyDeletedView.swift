// MARK: - 职责说明：「最近删除」页（docs/05 M3 任务 3.3b）——
// 说明 + 引导页：照片移入系统「最近删除」后保留 30 天，由系统自动清除。
// ⚠️ PhotoKit 无公开 API 枚举「最近删除」资源（隐私设计）——App 内只读浏览不可实现，
// 本页只做说明与跳转（photos-redirect://），**不提供任何删除/清空操作**（红线 1）。

import SwiftUI

struct RecentlyDeletedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "trash.circle")
                .font(.system(size: 64))
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Text("照片在系统「最近删除」保留 30 天")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textPrimary))
                .padding(.horizontal, 32)
            Text("移到「最近删除」的照片由系统统一保管，30 天后自动清除。本应用不会也不能清除或永久擦除它们。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .padding(.horizontal, 32)
            Spacer()
            Button {
                // 跳转系统相册（恢复操作只能在系统相册完成）
                if let url = URL(string: "photos-redirect://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("去系统相册恢复", systemImage: "photo.on.rectangle.angled")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(ds: DSColor.tint))
                    .foregroundColor(.white)
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .padding(.horizontal, DSSpacing.screenPadding)
            .padding(.bottom, DSSpacing.screenPadding)
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("最近删除")
        .navigationBarTitleDisplayMode(.inline)
    }
}
