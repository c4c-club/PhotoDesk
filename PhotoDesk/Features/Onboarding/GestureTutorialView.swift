// MARK: - 职责说明：手势教学页（docs/05 M2 任务 2.11 / docs/04 §3.2）——
// 纯代码循环动画（手形图标沿垂直往复 + 箭头指示）+ 可交互练习卡（真实上/下滑触发反馈），
// 文案「上滑 = 收藏 / 下滑 = 隐藏 / 在设置里可以随时调换」。尊重「减弱动态效果」（docs/04 §6）。
// 「去设置」：注入 presentSettings 时走回调；否则（嵌入 NavigationView）用 NavigationLink 推入。

import SwiftUI

struct GestureTutorialView: View {
    /// 静态演示（减弱动效 / 预览）时不做循环动画
    var animate = true

    @State private var offsetUp: CGFloat = 0
    @State private var offsetDown: CGFloat = 0
    /// 练习卡反馈文案（上/下滑触发）
    @State private var practiceFeedback: String?
    /// M7 接手势设置页回调；nil 时（NavigationStack 内呈现）退回 NavigationLink
    var presentSettings: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                demoRow(direction: .up, icon: "hand.point.up.left.fill", label: "上滑 = 收藏",
                        tint: Color(ds: DSColor.accentFavorite), offset: $offsetUp)
                demoRow(direction: .down, icon: "hand.point.down.fill", label: "下滑 = 隐藏",
                        tint: Color(ds: DSColor.accentHide), offset: $offsetDown)
                practiceCard
                Text("在设置里可以随时调换")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                settingsButton
                    .padding(.horizontal, DSSpacing.screenPadding)
            }
            .padding(.top, 16)
            .padding(.bottom, DSSpacing.screenPadding)
        }
        .background(Color(ds: DSColor.bgPrimary))
        .onAppear { startAnimationIfNeeded() }
    }

    // MARK: - 可交互练习（docs/25 §7 #23：真实手势触发演示反馈）

    private var practiceCard: some View {
        VStack(spacing: 10) {
            Text("试一试")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            ZStack {
                RoundedRectangle(cornerRadius: DSSpacing.cardCornerRadius)
                    .fill(Color(ds: DSColor.bgSecondary))
                    .frame(height: 110)
                if let practiceFeedback {
                    Label(practiceFeedback,
                          systemImage: practiceFeedback.hasPrefix("上滑") ? "heart.fill" : "eye.slash.fill")
                        .font(.title3)
                        .foregroundColor(Color(ds: DSColor.tint))
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 30))
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                        Text("在这里向上或向下滑动")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
            }
            .padding(.horizontal, DSSpacing.screenPadding)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation {
                    practiceFeedback = value.translation.height < 0 ? "上滑 → 收藏 ✓" : "下滑 → 隐藏 ✓"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { practiceFeedback = nil }
                }
            })
            .accessibilityIdentifier("Tutorial-Practice")
            .accessibilityLabel("手势练习区，向上或向下滑动查看对应动作")
        }
    }

    // MARK: - 去设置（回调注入优先；否则 NavigationLink 兜底——工具页/设置页均在 NavigationView 栈内）

    @ViewBuilder
    private var settingsButton: some View {
        if let presentSettings {
            Button {
                presentSettings()
            } label: {
                settingsButtonLabel(tinted: true)
            }
        } else {
            NavigationLink {
                GestureSettingsView()
            } label: {
                settingsButtonLabel(tinted: true)
            }
        }
    }

    private func settingsButtonLabel(tinted: Bool) -> some View {
        Text("去设置")
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tinted ? Color(ds: DSColor.tint) : Color(ds: DSColor.bgSecondary))
            .foregroundColor(tinted ? .white : Color(ds: DSColor.textSecondary))
            .cornerRadius(DSSpacing.buttonCornerRadius)
    }

    private enum DemoDirection { case up, down }

    private func demoRow(direction: DemoDirection, icon: String, label: String,
                         tint: Color, offset: Binding<CGFloat>) -> some View {
        HStack(spacing: 24) {
            // 演示窗口：手形图标在竖直轨道上往复
            ZStack {
                RoundedRectangle(cornerRadius: DSSpacing.cardCornerRadius)
                    .fill(Color(ds: DSColor.bgSecondary))
                    .frame(width: 64, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(tint)
                    .offset(y: offset.wrappedValue)
                Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                    .offset(x: 22)
            }
            Text(label)
                .font(.title3)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Spacer()
        }
        .padding(.horizontal, DSSpacing.screenPadding + 8)
    }

    private func startAnimationIfNeeded() {
        guard animate, !(UIAccessibility.isReduceMotionEnabled && AppContainer.shared.settings.respectReduceMotion) else { return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            offsetUp = -18
            offsetDown = 18
        }
    }
}
