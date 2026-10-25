// MARK: - 职责说明：隐私与锁定（docs/05 M7 任务 3）——隐私声明页（零上传/零分析/零第三方 SDK，
// 纯本机处理口径）+ Face ID 开关（「已隐藏」相册门禁；关闭后直接进入）。

import SwiftUI

struct PrivacyView: View {
    @AppStorage("vault.lockEnabled") private var vaultLockEnabled = true

    var body: some View {
        List {
            Section("隐私声明") {
                StatementRow(title: "零上传",
                             detail: "照片与所有数据只在本机处理，不经过任何网络传输。")
                StatementRow(title: "零分析",
                             detail: "不收集任何使用数据，不内置任何统计或广告组件。")
                StatementRow(title: "零第三方 SDK",
                             detail: "仅使用 Apple 系统框架（Photos / Vision / Core Image 等），没有第三方代码。")
                StatementRow(title: "删除语义",
                             detail: "所有「删除」都是移入系统「最近删除」，由系统保留 30 天后清除，本 App 不提供永久删除。")
                StatementRow(title: "撤销保险副本",
                             detail: "移到最近删除前会把原件拷贝进本机沙盒（默认上限 2GB），仅用于撤销窗口内恢复，可随时在「手势设置」关闭。")
            }

            Section("锁定") {
                Toggle(isOn: $vaultLockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("「已隐藏」相册需要 Face ID / 密码")
                        Text("解锁后 5 分钟内免重复验证")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("隐私与锁定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatementRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text(detail)
                .font(.subheadline)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
