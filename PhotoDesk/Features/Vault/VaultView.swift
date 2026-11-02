// MARK: - 职责说明：已隐藏相册页（docs/09 D05 重做）★——VaultViewModel 状态机驱动：
// locked/unlocking（自动 Face ID）/ unlocked（UIKit 网格，可点开查看器 + 上下文菜单）/
// failed（原因 + 重试 + 去系统设置）/ unavailable（去设置；模拟器附继续入口）。
// 空态/受限态完整；离开页面立即锁；网格点开走 ViewerContainer（assetID 定位）。

import SwiftUI
import UIKit
import PhotoDeskCore

struct VaultView: View {
    @ObservedObject var viewModel: VaultViewModel
    /// fullScreenCover 打开时的关闭入口（ToolsView 推入时为 nil）
    var onClose: (() -> Void)?
    @State private var viewerContext: ViewerContext?
    @State private var actionMessage: String?
    @State private var hasAttemptedUnlock = false

    var body: some View {
        Group {
            switch viewModel.phase {
            case .locked, .unlocking:
                lockView
            case .unlocked:
                unlockedContent
            case .failed(let message):
                failedView(message: message)
            case .unavailable(let message):
                unavailableView(message: message)
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("已隐藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        viewModel.lock()
                        onClose()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.onAppear()
                hasAttemptedUnlock = true
            }
        }
        .onDisappear {
            viewModel.lock()
        }
        .fullScreenCover(item: $viewerContext) { context in
            ViewerContainer(viewModel: AppContainer.shared.makeViewerViewModel(context: context))
        }
    }

    // MARK: - 门禁

    private var lockView: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.phase == .unlocking ? "faceid" : "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Text(viewModel.phase == .unlocking ? "正在验证 Face ID / 密码…" : "「已隐藏」相册已锁定")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            if viewModel.phase == .locked {
                Button {
                    Task { await viewModel.unlock() }
                } label: {
                    Label("使用 Face ID / 密码解锁", systemImage: "faceid")
                        .font(.body)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(ds: DSColor.tint))
                        .foregroundColor(.white)
                        .cornerRadius(DSSpacing.buttonCornerRadius)
                }
                .accessibilityIdentifier("Vault-Unlock")
            }
            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.accentDelete))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 已解锁（网格）

    private var unlockedContent: some View {
        ZStack {
            if viewModel.isLimitedAccess {
                limitedNotice
            } else if viewModel.items.isEmpty {
                emptyView
            } else {
                VaultGridView(viewModel: viewModel,
                              pipeline: AppContainer.shared.imagePipeline) { item in
                    viewerContext = ViewerContext(items: viewModel.items,
                                                  startItemID: item.id,
                                                  queryKey: "vault")
                }
            }
            if viewModel.isLoading {
                ProgressView("正在加载…")
                    .padding()
                    .background(Color(ds: DSColor.bgSecondary))
                    .cornerRadius(DSSpacing.cardCornerRadius)
            }
            if let actionMessage {
                VStack {
                    Spacer()
                    Text(actionMessage)
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(ds: DSColor.bgSecondary))
                        .cornerRadius(DSSpacing.cardCornerRadius)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Text("这里空空如也")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text("在浏览页下滑即可隐藏照片；隐藏后 5 分钟内进入无需再次验证")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var limitedNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(Color(ds: DSColor.accentDelete))
            Text("受限访问下无法读取已隐藏照片")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text("请到 系统设置 → 照片 → 照片管家 允许完全访问")
                .font(.subheadline)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 失败 / 不可用

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.accentDelete))
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textPrimary))
                .padding(.horizontal, 32)
            Button {
                Task { await viewModel.retry() }
            } label: {
                Text("重试")
                    .font(.body)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(ds: DSColor.tint))
                    .foregroundColor(.white)
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .accessibilityIdentifier("Vault-Retry")
            Button {
                openSystemSettings()
            } label: {
                Text("使用设备密码解锁")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.tint))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Text("无法验证身份")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .padding(.horizontal, 32)
            Button {
                openSystemSettings()
            } label: {
                Text("去系统设置")
                    .font(.body)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(ds: DSColor.tint))
                    .foregroundColor(.white)
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            #if targetEnvironment(simulator)
            // 模拟器演示入口（真机不编译：docs/09 D06 不再静默放行）
            Button("继续（仅模拟器）") {
                Task { await viewModel.simulatorBypass() }
            }
            .font(.subheadline)
            .foregroundColor(Color(ds: DSColor.textSecondary))
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
