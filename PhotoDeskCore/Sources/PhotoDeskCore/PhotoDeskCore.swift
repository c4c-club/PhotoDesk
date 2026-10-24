// MARK: - 职责说明：P-1 占位模块——仅用于打通「Docker swift test / CI core-linux」链路。
// 手势判定、日期分组、dHash/pHash、去重分组、撤销策略、回收站淘汰等纯逻辑自 M0 起按 docs/03 §3 逐步落位于本包；
// 边界规则（只允许 import Foundation，禁止任何 Apple 框架）见 AGENTS.md 红线 2。

public enum PhotoDeskCoreInfo {
    /// 包版本号（P-1 冒烟用；M0 起随骨架演进）
    public static let placeholderVersion = "0.1.0"
}
