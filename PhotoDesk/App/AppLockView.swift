// MARK: - 职责说明：App 锁屏覆盖层 + 隐私遮罩（docs/09 D06）——
// AppLockView：全屏锁定界面（Face ID 按钮 + 失败原因 + 重试 / 去设置）；
// PrivacyShield：scenePhase 非 active 时的不透明遮罩（防 App Switcher 截屏泄露）。

import SwiftUI

struct AppLockView: View {
    @ObservedObject var appLock: AppLockController
    @State private var attemptedOnAppear = false

    var body: some View {
        ZStack {
            Color(ds: DSColor.bgPrimary)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundColor(Color(ds: DSColor.tint))
                Text("照片管家已锁定")
                    .font(.title3)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text("用 Face ID / 设备密码解锁")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textSecondary))

                Button {
                    Task { await appLock.unlock() }
                } label: {
                    Label("解锁", systemImage: "faceid")
                        .font(.body)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color(ds: DSColor.tint))
                        .foregroundColor(.white)
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                }
                .accessibilityIdentifier("AppLock-Unlock")

                if let message = appLock.failureMessage {
                    Text(message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(ds: DSColor.accentDelete))
                        .padding(.horizontal, 32)
                    Button("重试") {
                        Task { await appLock.unlock() }
                    }
                    .accessibilityIdentifier("AppLock-Retry")
                }
                Spacer()
                Text("照片只在本机处理，不上传任何数据")
                    .font(.caption2)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
        }
        .onAppear {
            // 冷启动自动唤起验证（仅一次；失败后用户手动重试，避免反复弹窗）
            guard !attemptedOnAppear else { return }
            attemptedOnAppear = true
            Task { await appLock.unlock() }
        }
    }
}

/// 隐私遮罩（scenePhase != .active）：App 锁开启或保险箱已解锁时防止 App Switcher 截屏
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Color(ds: DSColor.bgPrimary)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 44))
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Text("内容已隐藏")
                    .font(.headline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
            }
        }
        .transition(.opacity)
    }
}
