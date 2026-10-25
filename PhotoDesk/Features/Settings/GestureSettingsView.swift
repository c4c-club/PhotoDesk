// MARK: - 职责说明：手势设置页 ★（docs/04 §3.4 / docs/05 M7 任务 1）——
// 上/下滑动作选择（ActionPickerView）、灵敏度三档、触觉、破坏性确认、撤销窗口、自动前进、
// 遵循减弱动态效果；底部「移到最近删除」说明（docs/04 原文口径）；撤销保险副本开关 + 容量上限；
// 重新观看手势教学。全部 @AppStorage 驱动，改动即生效（浏览页每次手势判定实时读取）。

import SwiftUI
import PhotoDeskCore

struct GestureSettingsView: View {
    @ObservedObject private var settings = AppContainer.shared.settings

    var body: some View {
        List {
            Section("滑动动作") {
                NavigationLink {
                    ActionPickerView(direction: .up)
                } label: {
                    LabeledRow(title: "上滑", value: settings.swipeUpAction.displayName)
                }
                .accessibilityIdentifier("Gesture-Up")

                NavigationLink {
                    ActionPickerView(direction: .down)
                } label: {
                    LabeledRow(title: "下滑", value: settings.swipeDownAction.displayName)
                }
                .accessibilityIdentifier("Gesture-Down")
            }

            Section("灵敏度") {
                Picker("灵敏度", selection: $settings.sensitivityRaw) {
                    ForEach(Sensitivity.allCases, id: \.rawValue) { level in
                        Text(sensitivityName(level)).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("舒适触发最快（80pt）；标准 120pt；保守需更明确的滑动（180pt）")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }

            Section("触发与反馈") {
                Toggle("触觉反馈", isOn: $settings.hapticsEnabled)
                Toggle("破坏性操作确认", isOn: $settings.confirmDestructive)
                Picker("撤销窗口", selection: $settings.undoWindow) {
                    Text("3 秒").tag(3.0)
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                }
                Toggle("执行后自动前进", isOn: $settings.autoAdvance)
                Toggle("遵循「减弱动态效果」", isOn: $settings.respectReduceMotion)
            }

            Section("关于「移到最近删除」") {
                Text("「移到最近删除」只会把照片放进系统「最近删除」，保留 30 天后由系统清除，本 App 不会永久删除。iOS 会弹出一次确认框且无法关闭；若想更快，建议把下滑设为「隐藏」。")
                    .font(.footnote)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }

            Section("撤销保险副本") {
                Toggle(isOn: $settings.safetyCopyEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("撤销保险副本")
                        Text("删除前先把原件拷贝到本机沙盒，撤销窗口内可一键恢复；关闭后撤销窗口内不再提供恢复")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
                }
                if settings.safetyCopyEnabled {
                    Picker("副本容量上限", selection: $settings.trashLimitMB) {
                        Text("512 MB").tag(512)
                        Text("1 GB").tag(1024)
                        Text("2 GB").tag(2048)
                        Text("4 GB").tag(4096)
                    }
                }
            }

            Section {
                NavigationLink {
                    GestureTutorialView()
                } label: {
                    Label("重新观看手势教学", systemImage: "play.rectangle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("手势设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sensitivityName(_ level: Sensitivity) -> String {
        switch level {
        case .comfortable:  return "舒适"
        case .standard:     return "标准"
        case .conservative: return "保守"
        }
    }
}
