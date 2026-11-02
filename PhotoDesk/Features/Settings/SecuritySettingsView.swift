// MARK: - 职责说明：安全设置（docs/09 D06）——App 启动锁开关 / 保险箱锁开关 / 立即锁定 /
// 后台宽限时间；隐私声明沿用 PrivacyView。开关直接读写 AppLockController（@Published 手动持久化）。

import SwiftUI

struct SecuritySettingsView: View {
    @ObservedObject private var appLock = AppContainer.shared.appLock
    @AppStorage("vault.lockEnabled") private var vaultLockEnabled = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $appLock.lockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启动时用 Face ID / 密码锁定")
                        Text("打开 App 时需要验证身份（冷启动即锁）")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
                .accessibilityIdentifier("Security-AppLock")

                Toggle(isOn: $vaultLockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("「已隐藏」相册需要 Face ID / 密码")
                        Text("解锁后 5 分钟内免重复验证")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
                .accessibilityIdentifier("Security-VaultLock")
            } header: {
                Text("锁定")
            } footer: {
                Text("「立即锁定」只在启动锁开启时可用；切到后台超过宽限时间后，回到 App 需要重新验证。")
            }

            Section("后台宽限时间") {
                Picker("重新锁定需等待", selection: $appLock.graceSeconds) {
                    Text("立即").tag(0.0)
                    Text("15 秒").tag(15.0)
                    Text("30 秒").tag(30.0)
                    Text("60 秒").tag(60.0)
                }
            }

            Section {
                Button {
                    appLock.lockNow()
                } label: {
                    Text("立即锁定")
                        .foregroundColor(Color(ds: DSColor.accentDelete))
                }
                .disabled(!appLock.lockEnabled)
                .accessibilityIdentifier("Security-LockNow")
            }

            Section {
                StatementRow(title: "零上传",
                             detail: "照片与所有数据只在本机处理，不经过任何网络传输。")
                StatementRow(title: "验证数据",
                             detail: "Face ID / 密码验证由 iOS 系统完成，本 App 无法也不读取你的生物特征或密码。")
            } header: {
                Text("隐私")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("安全与锁定")
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
