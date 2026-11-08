// MARK: - 职责说明：「最近删除」页（docs/05 M3 任务 3.3b）——
// 说明 + 引导页：照片移入系统「最近删除」后保留 30 天，由系统自动清除。
// ⚠️ PhotoKit 无公开 API 枚举「最近删除」资源（隐私设计）——App 内只读浏览不可实现，
// 本页只做说明与跳转（photos-redirect://），**不提供任何删除/清空操作**（红线 1）。

import SwiftUI
import UIKit

struct RecentlyDeletedView: View {
    @State private var showJumpFailure = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 8)
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
                Button {
                    // 跳转系统相册（恢复操作只能在系统相册完成）
                    guard let url = URL(string: "photos-redirect://"),
                          UIApplication.shared.canOpenURL(url) else {
                        showJumpFailure = true
                        return
                    }
                    UIApplication.shared.open(url)
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

                faqSection
            }
            .padding(.bottom, 24)
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("最近删除")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法打开系统相册", isPresented: $showJumpFailure) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请手动打开「照片」App，在「相簿 → 最近删除」中恢复照片。")
        }
    }

    /// 常见问题（docs/25 §7 #22）
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("常见问题")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            faqRow("为什么应用里看不到「最近删除」的照片？",
                   "iOS 隐私设计不允许第三方应用枚举「最近删除」相簿，查看与恢复只能在系统「照片」App 完成。")
            faqRow("移到「最近删除」后还能恢复吗？",
                   "可以。30 天内打开系统「照片」→「相簿」→「最近删除」，选中照片点「恢复」；超过 30 天由系统自动清除，无法找回。")
            faqRow("应用内撤销和它有什么区别？",
                   "应用内删除后立即出现的「撤销」提示（撤销窗口内）可直接把照片放回原处，不需要去系统相册。")
            faqRow("应用能帮我彻底删除照片吗？",
                   "不能，也不会。本应用只把照片移入系统「最近删除」，最终清除由系统在 30 天后自动完成。")
        }
        .padding(.horizontal, DSSpacing.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func faqRow(_ question: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text(answer)
                .font(.caption)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
