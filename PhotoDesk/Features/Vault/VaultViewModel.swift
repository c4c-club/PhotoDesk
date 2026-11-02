// MARK: - 职责说明：已隐藏相册 ViewModel（docs/09 D05 重做）★——
// 状态机 locked/unlocking/unlocked/failed/unavailable；进入自动唤起 Face ID（宽限期内免重复）；
// 加载前 flushHidesIfNeeded（待隐藏批量提交）；合并 pendingHideIDs（未提交也能在 Vault 查看）；
// PhotoChangeObserver 增量刷新；取消隐藏立即写库、删除走会话一次批量提交、收藏即时写。

import Foundation
import Photos
import UIKit
import PhotoDeskCore

@MainActor
final class VaultViewModel: ObservableObject {
    enum Phase: Equatable {
        case locked
        case unlocking
        case unlocked
        case failed(String)
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .locked
    @Published private(set) var items: [PhotoItem] = []
    /// 尚未提交到 PhotoKit 的待隐藏 id（网格角标「待隐藏」）
    @Published private(set) var pendingHideIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLimitedAccess = false

    /// 网格数据变化（VaultGridView representable 更新）
    var onItemsChanged: (() -> Void)?

    let vault: VaultService
    private let repository: AssetRepositoryProtocol
    private let writer: PhotoWriterProtocol
    private let reviewSession: ReviewSessionController
    private let undoCenter: UndoCenter
    private let settings: SettingsStore
    private var changeObserver: PhotoChangeObserver?

    init(vault: VaultService,
         repository: AssetRepositoryProtocol,
         writer: PhotoWriterProtocol,
         reviewSession: ReviewSessionController,
         undoCenter: UndoCenter,
         settings: SettingsStore) {
        self.vault = vault
        self.repository = repository
        self.writer = writer
        self.reviewSession = reviewSession
        self.undoCenter = undoCenter
        self.settings = settings
    }

    // MARK: - 生命周期

    /// 进页：自动唤起 Face ID（或锁关闭/宽限期内直接加载）
    func onAppear() async {
        isLimitedAccess = (AppContainer.shared.libraryService.access == .limited)
        guard settings.vaultLockEnabled else {
            await load()
            return
        }
        await unlock()
    }

    func unlock() async {
        if vault.isUnlocked {
            await load()
            return
        }
        phase = .unlocking
        let ok = await vault.unlock()
        if ok {
            await load()
        } else {
            switch vault.gate.status {
            case .failed(let message):
                phase = .failed(message)
            case .unavailable(let message):
                phase = .unavailable(message)
            default:
                phase = .failed("验证未通过")
            }
        }
    }

    func retry() async {
        await onAppear()
    }

    /// 离开页面 / 进后台：立即锁（docs/09 D06）
    func lock() {
        vault.lock()
        phase = .locked
    }

    // MARK: - 加载（含 pending 合并 + observer）

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // 进入 Vault 前批量提交待隐藏（docs/09 D04：未提交项 flush 后系统「已隐藏」可见）
        await reviewSession.flushHidesIfNeeded(reason: "enterVault")

        let total = await repository.prepare(scope: .hidden)
        var fetched: [PhotoItem] = []
        if total > 0 {
            fetched = await repository.fetch(scope: .hidden, offset: 0, limit: total)
        }
        // 合并 pendingHide（尚未写库 → fetch(.hidden) 拿不到；docs/09 D05 §4）
        pendingHideIDs = Set(reviewSession.session.pendingHideIDs)
        let fetchedIDs = Set(fetched.map(\.id))
        let missing = reviewSession.session.pendingHideIDs.filter { !fetchedIDs.contains($0) }
        let pendingItems = await repository.fetch(ids: missing)

        items = fetched + pendingItems
        phase = .unlocked
        onItemsChanged?()
        startObservingChanges()
    }

    private func startObservingChanges() {
        guard changeObserver == nil,
              let result = repository.latestResult(for: .hidden) else { return }
        let observer = PhotoChangeObserver { [weak self] _ in
            Task { @MainActor in
                await self?.reloadQuietly()
            }
        }
        observer.startMonitoring(result: result)
        changeObserver = observer
    }

    /// observer 回调刷新（隐藏/取消隐藏后列表同步；列表量级小，整表重取即可）
    private func reloadQuietly() async {
        guard phase == .unlocked else { return }
        if let newResult = repository.latestResult(for: .hidden) {
            repository.replaceResult(newResult, for: .hidden)
            changeObserver?.startMonitoring(result: newResult)
        }
        await load()
    }

    // MARK: - 操作

    /// 取消隐藏：立即写库；失败恢复 item 并提示
    func unhide(ids: [String]) async -> String? {
        do {
            try await writer.setHidden(ids: ids, isHidden: false)
            undoCenter.push(kind: .unhide,
                            assetIDs: ids,
                            toastText: "已取消隐藏",
                            window: settings.undoWindow)
            items.removeAll { ids.contains($0.id) }
            pendingHideIDs.subtract(ids)
            onItemsChanged?()
            return nil
        } catch {
            return "取消隐藏失败：\(error.localizedDescription)"
        }
    }

    /// 移到最近删除：入队 + 一次批量提交（系统确认 1 次；docs/09 D05）
    func delete(ids: [String]) async -> String? {
        reviewSession.enqueueDeletes(ids: ids)
        let result = await reviewSession.commitDeletes()
        if result.failed {
            return "系统未允许删除，\(ids.count) 张仍在待删除"
        }
        items.removeAll { ids.contains($0.id) }
        onItemsChanged?()
        return nil
    }

    /// 收藏：即时写
    func favorite(ids: [String]) async -> String? {
        do {
            try await writer.setFavorite(ids: ids, isFavorite: true)
            undoCenter.push(kind: .favorite,
                            assetIDs: ids,
                            toastText: "已收藏",
                            window: settings.undoWindow)
            return nil
        } catch {
            return "操作失败：\(error.localizedDescription)"
        }
    }

    func isPendingHide(_ id: String) -> Bool {
        pendingHideIDs.contains(id)
    }

    /// 长按/上下文菜单（取消隐藏 / 收藏 / 移到最近删除；docs/09 D05）
    func contextMenu(for item: PhotoItem) -> UIMenu {
        UIMenu(children: [
            UIAction(title: item.isFavorite ? "取消收藏" : "收藏",
                     image: UIImage(systemName: "heart")) { [weak self] _ in
                Task { _ = await self?.favorite(ids: [item.id]) }
            },
            UIAction(title: "取消隐藏",
                     image: UIImage(systemName: "eye")) { [weak self] _ in
                Task { _ = await self?.unhide(ids: [item.id]) }
            },
            UIAction(title: "移到最近删除",
                     image: UIImage(systemName: "trash"),
                     attributes: .destructive) { [weak self] _ in
                Task { _ = await self?.delete(ids: [item.id]) }
            },
        ])
    }

    /// 模拟器继续（仅模拟器编译：无 Face ID 硬件时的演示路径；真机无此入口）
    #if targetEnvironment(simulator)
    func simulatorBypass() async {
        vault.gate.markSimulatorBypass()
        await load()
    }
    #endif
}
