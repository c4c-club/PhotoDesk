// MARK: - 职责说明：隐私与锁定（docs/05 M7 任务 3）——隐私声明页（零上传/零分析/零第三方 SDK，
// 纯本机处理口径）+ 照片权限状态/去系统设置 + Face ID 开关（「已隐藏」相册门禁；关闭后直接进入）。

import SwiftUI
import UIKit
import Photos

struct PrivacyView: View {
    @AppStorage("vault.lockEnabled") private var vaultLockEnabled = true
    @State private var permissionStatus: PHAuthorizationStatus = .notDetermined

    private var permissionText: String {
        switch permissionStatus {
        case .authorized: return "完全访问"
        case .limited: return "受限访问（仅允许的照片）"
        case .denied: return "已拒绝"
        case .restricted: return "受系统策略限制"
        case .notDetermined: return "尚未选择"
        @unknown default: return "未知"
        }
    }

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

            Section {
                LabeledRow(title: "当前授权", value: permissionText)
                if permissionStatus == .limited {
                    Text("受限访问下只显示你允许的照片。可在照片库分类菜单点「管理可见照片」调整可见范围。")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("去系统设置", systemImage: "gearshape")
                }
                .accessibilityIdentifier("Privacy-Open-Settings")
            } header: {
                Text("照片权限")
            } footer: {
                Text("授权状态变化后会自动刷新（回到本页时更新）。")
            }

            Section {
                Toggle(isOn: $vaultLockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("「已隐藏」相册需要 Face ID / 密码")
                        Text("解锁后 5 分钟内免重复验证")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
            } header: {
                Text("锁定")
            } footer: {
                Text("若 Face ID / 密码不可用，请到系统「设置 → 面容 ID 与密码」（或「触控 ID 与密码」）开启设备验证后返回重试。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("隐私与锁定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { permissionStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
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
