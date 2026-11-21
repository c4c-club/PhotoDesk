// MARK: - 职责说明：授权引导页（docs/05 M1 任务 1.8 / docs/04 §7 文案；docs/49 T03 重构）——
// 三种形态：首次引导（Permission-Allow 触发系统授权弹窗）/ 被拒绝（主按钮去系统设置 +
// 次按钮重新检查）/ 受限（重新检查）。主按钮绝不调用 requestAccess 假装弹窗（docs/49 T03 §2.1）。

import SwiftUI
import UIKit

struct PermissionIntroView: View {
    enum Mode {
        case intro        // notDetermined：Permission-Allow 触发系统弹窗
        case denied       // 拒绝：主按钮去系统设置 + 次按钮重新检查
        case restricted   // 受限（家长控制等）：重新检查
    }

    let mode: Mode
    /// intro 主按钮：触发系统授权弹窗（仅 notDetermined 合法）
    var onAllow: (() -> Void)? = nil
    /// denied 主按钮：跳系统设置（denied 不得用 requestAccess 假装弹窗）
    var onOpenSettings: (() -> Void)? = nil
    /// denied / restricted 次按钮：重新检查授权（只刷新状态，不弹系统框）
    var onRecheck: (() -> Void)? = nil
    /// intro 可选次按钮：暂不授权（语义由调用方决定；nil 不显示、不占位）
    var onLater: (() -> Void)? = nil
    /// recheck 后仍 denied 的内联提示（状态由调用方持有，跨重渲染保留）
    var showsRecheckHint: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundColor(Color(ds: DSColor.tint))
            Text(title)
                .font(.largeTitle)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .padding(.horizontal, 32)
            if showsRecheckHint {
                Text("仍未授权，请到系统设置开启")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
            Spacer()
            primaryButton
            if mode == .intro, onLater != nil {
                Button {
                    onLater?()
                } label: {
                    Text("暂不授权")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .accessibilityIdentifier("Permission-Later")
                .padding(.horizontal, DSSpacing.screenPadding)
            }
            if showsSecondary {
                Button {
                    onRecheck?()
                } label: {
                    Label("重新检查授权", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.tint))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .accessibilityIdentifier("Permission-Recheck")
                .padding(.horizontal, DSSpacing.screenPadding)
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
    }

    /// 主按钮：intro = 允许访问照片；denied = 去系统设置（系统不会再弹框，跳转是唯一出路）
    @ViewBuilder
    private var primaryButton: some View {
        switch mode {
        case .intro:
            Button {
                onAllow?()
            } label: {
                Text("允许访问照片")
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(ds: DSColor.tint))
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .accessibilityIdentifier("Permission-Allow")
            .padding(.horizontal, DSSpacing.screenPadding)
        case .denied:
            Button {
                if let onOpenSettings {
                    onOpenSettings()
                } else {
                    openSystemSettings()
                }
            } label: {
                Label("去系统设置", systemImage: "gearshape")
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(ds: DSColor.tint))
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .accessibilityIdentifier("Permission-Open-Settings")
            .padding(.horizontal, DSSpacing.screenPadding)
        case .restricted:
            EmptyView()
        }
    }

    private var showsSecondary: Bool {
        (mode == .denied || mode == .restricted) && onRecheck != nil
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var title: String {
        switch mode {
        case .intro:      return "照片管家"
        case .denied:     return "无法访问照片"
        case .restricted: return "访问受限"
        }
    }

    /// docs/04 §7 授权引导文案（零上传口径原文）；denied 必含「系统不会再次弹出授权框」指引（docs/49 T03）
    private var message: String {
        switch mode {
        case .intro:
            return "照片管家需要访问你的照片来完成整理。所有处理都在本机完成，不会上传任何数据。"
        case .denied:
            return "你在系统设置中关闭了照片访问权限。系统不会再次弹出授权框；请到系统设置 → 隐私与安全性 → 照片 开启，然后回来继续。"
        case .restricted:
            return "照片访问被系统策略限制（如家长控制）。若使用「受限访问」，本应用只显示你允许的照片；可在照片库分类菜单点「管理可见照片」调整。"
        }
    }
}
