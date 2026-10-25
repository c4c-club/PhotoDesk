// MARK: - 职责说明：撤销中心（docs/03 §5.1 撤销实现 / docs/02 §3.5）——
// 内存撤销栈 + 过期判定（窗口来自设置，默认 5 秒可设 3/5/10）；反向操作经 PhotoWriter。
// M2 范围：收藏 / 取消收藏 / 隐藏 / 取消隐藏；只保留最新一条（Toast 单条交互）。
// TODO(P3): ActionLog 持久化（App 被杀重启 10 秒内仍可撤销）与多条目队列。

import Foundation

@MainActor
final class UndoCenter: ObservableObject {
    /// 可撤销条目：kind 记录「已执行的动作」，undo 时做反向操作
    struct Entry: Identifiable, Equatable {
        enum Kind: Equatable {
            case favorite([String])        // 已收藏 → 撤销 = 取消收藏
            case unfavorite([String])      // 已取消收藏 → 撤销 = 重新收藏
            case hide([String])            // 已隐藏 → 撤销 = 取消隐藏
            case unhide([String])          // 已取消隐藏 → 撤销 = 重新隐藏
        }

        let id = UUID()
        let kind: Kind
        let toastText: String
        let expiresAt: Date
    }

    /// 最新可撤销条目（驱动 DSToast 显示）
    @Published private(set) var activeEntry: Entry?
    /// 是否有可撤销条目（Toast 是否显示「撤销」按钮）
    var hasActiveEntry: Bool { activeEntry != nil }
    /// 过期时通知（VC 收起 Toast）
    var onExpire: ((Entry) -> Void)?

    private let writer: PhotoWriter
    private var ticker: Timer?

    init(writer: PhotoWriter) {
        self.writer = writer
    }

    /// 入栈：新动作顶掉旧条目（旧条目视为过期）
    func push(kind: Entry.Kind, toastText: String, window: TimeInterval) -> Entry {
        let entry = Entry(kind: kind, toastText: toastText, expiresAt: Date().addingTimeInterval(window))
        activeEntry = entry
        startTicker()
        return entry
    }

    /// 撤销最新条目：反向写 PhotoKit，成功后清栈
    /// - Returns: 撤销的动作（供 VM 还原本地状态）
    func undo() async -> Entry? {
        guard let entry = activeEntry else { return nil }
        activeEntry = nil
        stopTicker()
        do {
            switch entry.kind {
            case .favorite(let ids):  try await writer.setFavorite(ids: ids, isFavorite: false)
            case .unfavorite(let ids): try await writer.setFavorite(ids: ids, isFavorite: true)
            case .hide(let ids):       try await writer.setHidden(ids: ids, isHidden: false)
            case .unhide(let ids):     try await writer.setHidden(ids: ids, isHidden: true)
            }
            return entry
        } catch {
            return nil
        }
    }

    func dismissActive() {
        activeEntry = nil
        stopTicker()
    }

    // MARK: - 过期计时

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let weakSelf = self else { return }
            Task { @MainActor in
                weakSelf.expireIfNeeded()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func expireIfNeeded() {
        guard let entry = activeEntry, Date() >= entry.expiresAt else { return }
        activeEntry = nil
        stopTicker()
        onExpire?(entry)
    }
}
