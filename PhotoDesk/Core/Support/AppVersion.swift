// MARK: - 职责说明：App 版本文本唯一出处（docs/22 Phase 4 设置页缺陷）——
// 从 Bundle 读取 MARKETING_VERSION / CURRENT_PROJECT_VERSION，禁止在设置/工具页硬编码。

import Foundation

enum AppVersion {
    /// 形如 "1.4.0 (5)"；Info.plist 缺失时回退 "未知版本"（不伪造版本号）。
    static var display: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        guard !short.isEmpty else { return "未知版本" }
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}
