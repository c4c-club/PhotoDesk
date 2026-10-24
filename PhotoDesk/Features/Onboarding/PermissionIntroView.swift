// MARK: - 职责说明：授权引导页（docs/05 M1 任务 1.8 / docs/04 §7 文案）——
// 三种形态：首次引导（触发系统授权弹窗）/ 被拒绝（去系统设置）/ 受限（说明）。零上传口径必须原文保留。

import SwiftUI
import UIKit

struct PermissionIntroView: View {
    enum Mode {
        case intro        // notDetermined：点按钮触发系统弹窗
        case denied       // 拒绝：引导去系统设置 + 重新检查
        case restricted   // 受限（家长控制等）：仅说明
    }

    let mode: Mode
    /// intro → 触发 requestAccess；denied → 重新检查；restricted → nil
    let action: (() -> Void)?

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
            Spacer()
            if let action {
                Button {
                    action()
                } label: {
                    Text(buttonTitle)
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(ds: DSColor.tint))
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                }
                .padding(.horizontal, DSSpacing.screenPadding)
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
    }

    private var title: String {
        switch mode {
        case .intro:      return "照片管家"
        case .denied:     return "无法访问照片"
        case .restricted: return "访问受限"
        }
    }

    /// docs/04 §7 授权引导文案（零上传口径原文）
    private var message: String {
        switch mode {
        case .intro:
            return "照片管家需要访问你的照片来完成整理。所有处理都在本机完成，不会上传任何数据。"
        case .denied:
            return "你在系统设置中关闭了照片访问权限。请在「设置 → 隐私与安全性 → 照片」中重新允许，然后回来继续。"
        case .restricted:
            return "照片访问被系统策略限制（如家长控制）。本应用需要访问照片才能完成整理。"
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .intro:      return "允许访问照片"
        case .denied:     return "重新检查授权"
        case .restricted: return ""
        }
    }
}
