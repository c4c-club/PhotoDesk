// MARK: - 职责说明：手势教学页（docs/05 M2 任务 2.11 / docs/04 §3.2）——
// 纯代码循环动画（手形图标沿垂直往复 + 箭头指示），文案「上滑 = 收藏 / 下滑 = 隐藏 / 在设置里可以随时调换」，
// 底部「去设置」按钮（M7 接设置页前置灰）。尊重「减弱动态效果」（docs/04 §6）。

import SwiftUI

struct GestureTutorialView: View {
    /// 静态演示（减弱动效 / 预览）时不做循环动画
    var animate = true

    @State private var offsetUp: CGFloat = 0
    @State private var offsetDown: CGFloat = 0
    /// M7 接手势设置页前置灰；presentSetting 由调用方注入（当前工具页无导航栈）
    var presentSettings: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            demoRow(direction: .up, icon: "hand.point.up.left.fill", label: "上滑 = 收藏",
                    tint: Color(ds: DSColor.accentFavorite), offset: $offsetUp)
            demoRow(direction: .down, icon: "hand.point.down.fill", label: "下滑 = 隐藏",
                    tint: Color(ds: DSColor.accentHide), offset: $offsetDown)
            Text("在设置里可以随时调换")
                .font(.subheadline)
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Spacer()
            Button {
                presentSettings?()
            } label: {
                Text("去设置")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(presentSettings == nil
                                ? Color(ds: DSColor.bgSecondary)
                                : Color(ds: DSColor.tint))
                    .foregroundColor(presentSettings == nil
                                     ? Color(ds: DSColor.textSecondary)
                                     : .white)
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .disabled(presentSettings == nil)   // M7 接线前置灰
            .padding(.horizontal, DSSpacing.screenPadding)
            .padding(.bottom, DSSpacing.screenPadding)
        }
        .background(Color(ds: DSColor.bgPrimary))
        .onAppear { startAnimationIfNeeded() }
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
