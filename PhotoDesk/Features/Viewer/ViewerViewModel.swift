// MARK: - 职责说明：全屏浏览器 ViewModel（docs/05 M2 任务 2.6 执行管线 / M3 任务 3.2）——
// 持有照片快照（LibraryViewModel.items 的值拷贝，关闭浏览器后由库侧 observer 增量同步）；
// 方向 → 动作解析（设置 gesture.up/down）；动作执行（PhotoWriter / TrashBin）→ 撤销入栈（UndoCenter）。
// 红线 1：moveToRecentlyDeleted 前必经 TrashBin 落副本（iCloud 未下载 → .needsDownload 拒绝并提示
// 「请先下载原件」）；副本开关关闭时直接删除（系统「最近删除」30 天兜底，撤销窗口内不提供恢复）。

import Foundation
import PhotoDeskCore

@MainActor
final class ViewerViewModel: ObservableObject {
    /// 动作执行结果
    enum ActionOutcome {
        /// 成功：更新后的 item + Toast 文案
        case success(PhotoItem, toastText: String)
        /// 拒绝执行，展示 message
        case rejected(String)
    }

    @Published private(set) var items: [PhotoItem]
    @Published private(set) var currentIndex: Int
    @Published private(set) var isFavoriteCurrent = false

    /// VC 注册：撤销成功后还原本地状态
    var onUndoApplied: (() -> Void)?

    var current: PhotoItem? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    private let settings: SettingsStore
    private let writer: PhotoWriterProtocol
    private let trashBin: TrashBin
    private let undoCenter: UndoCenter

    init(items: [PhotoItem],
         startIndex: Int,
         settings: SettingsStore,
         writer: PhotoWriterProtocol,
         trashBin: TrashBin,
         undoCenter: UndoCenter) {
        self.items = items
        self.currentIndex = max(0, min(startIndex, max(0, items.count - 1)))
        self.settings = settings
        self.writer = writer
        self.trashBin = trashBin
        self.undoCenter = undoCenter
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    // MARK: - 方向 → 动作

    func action(for direction: SwipeDirection) -> SwipeAction {
        switch direction {
        case .up:   return settings.swipeUpAction
        case .down: return settings.swipeDownAction
        }
    }

    // MARK: - 执行管线

    /// 锁定并松手后执行。调用方（VC）负责确认弹窗与飞出动画时机。
    func execute(_ action: SwipeAction, for item: PhotoItem) async -> ActionOutcome {
        do {
            switch action {
            case .favorite:
                try await writer.setFavorite(ids: [item.id], isFavorite: true)
                return await success(item, isFavorite: true, isHidden: item.isHidden,
                                     kind: .favorite, toastText: action.toastText)

            case .unfavorite:
                try await writer.setFavorite(ids: [item.id], isFavorite: false)
                return await success(item, isFavorite: false, isHidden: item.isHidden,
                                     kind: .unfavorite, toastText: action.toastText)

            case .toggleFavorite:
                return await execute(item.isFavorite ? .unfavorite : .favorite, for: item)

            case .hide:
                try await writer.setHidden(ids: [item.id], isHidden: true)
                return await success(item, isFavorite: item.isFavorite, isHidden: true,
                                     kind: .hide, toastText: action.toastText)

            case .unhide:
                try await writer.setHidden(ids: [item.id], isHidden: false)
                return await success(item, isFavorite: item.isFavorite, isHidden: false,
                                     kind: .unhide, toastText: action.toastText)

            case .moveToRecentlyDeleted:
                return await moveToRecentlyDeleted(item)

            case .addToAlbum, .share, .showInfo, .rotate:
                return .rejected("该动作将在后续里程碑开放")

            case .dismiss:
                return .rejected("退出浏览由浏览页直接处理")

            case .none:
                return .rejected("")
            }
        } catch let error as TrashError {
            return .rejected(error.localizedDescription)   // 含「请先下载原件」（docs/04 §7）
        } catch {
            return .rejected("操作失败：\(error.localizedDescription)")
        }
    }

    /// 红线 1 流程：TrashBin 落副本 → writer.moveToRecentlyDeleted（唯一删除实现）
    private func moveToRecentlyDeleted(_ item: PhotoItem) async -> ActionOutcome {
        var trashRecordIDs: [UUID] = []
        if trashBin.isSafetyCopyEnabled {
            do {
                let record = try await trashBin.storeCopy(forAssetID: item.id)
                trashRecordIDs = [record.id]
            } catch let error as TrashError {
                return .rejected(error.localizedDescription)   // 「请先下载原件」等
            } catch {
                return .rejected("操作失败：\(error.localizedDescription)")
            }
        }
        // 副本开关关闭：直接删除（撤销窗口内不提供恢复，docs/04 §3.4「撤销保险副本」说明）
        do {
            try await writer.moveToRecentlyDeleted(ids: [item.id])
        } catch {
            return .rejected("操作失败：\(error.localizedDescription)")
        }
        removeLocally([item.id])

        if !trashRecordIDs.isEmpty {
            undoCenter.push(kind: .moveToRecentlyDeleted,
                            assetIDs: [item.id],
                            trashRecordIDs: trashRecordIDs,
                            toastText: SwipeAction.moveToRecentlyDeleted.toastText,
                            window: settings.undoWindow)
        }
        return .success(item, toastText: SwipeAction.moveToRecentlyDeleted.toastText)
    }

    private func success(_ item: PhotoItem, isFavorite: Bool, isHidden: Bool,
                         kind: UndoCenter.ActionKind, toastText: String) async -> ActionOutcome {
        applyLocal(item: item, isFavorite: isFavorite, isHidden: isHidden)
        undoCenter.push(kind: kind,
                        assetIDs: [item.id],
                        toastText: toastText,
                        window: settings.undoWindow)
        return .success(item, toastText: toastText)
    }

    // MARK: - 本地状态

    private func applyLocal(item target: PhotoItem, isFavorite: Bool, isHidden: Bool) {
        guard let index = items.firstIndex(where: { $0.id == target.id }) else { return }
        let old = items[index]
        items[index] = PhotoItem(id: old.id,
                                 mediaType: old.mediaType,
                                 mediaSubtypes: old.mediaSubtypes,
                                 creationDate: old.creationDate,
                                 modificationDate: old.modificationDate,
                                 pixelWidth: old.pixelWidth,
                                 pixelHeight: old.pixelHeight,
                                 duration: old.duration,
                                 isFavorite: isFavorite,
                                 isHidden: isHidden,
                                 location: old.location,
                                 burstIdentifier: old.burstIdentifier,
                                 isCloudOnly: old.isCloudOnly)
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    /// 删除后从快照移除（photo 已进系统「最近删除」）
    private func removeLocally(_ ids: [String]) {
        items.removeAll { ids.contains($0.id) }
        if currentIndex >= items.count {
            currentIndex = max(0, items.count - 1)
        }
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    // MARK: - 翻页

    func updateIndex(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        currentIndex = index
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    /// autoAdvance：前进到下一张（最后一张留在原地，docs/04 §3.4）
    var nextIndexAfterAction: Int {
        min(currentIndex + 1, items.count - 1)
    }

    // MARK: - 撤销

    /// Toast「撤销」：反向写库并还原本地状态
    func undoLast() async {
        guard let entry = await undoCenter.undo() else { return }
        switch entry.kind {
        case .favorite:   applyFlag(ids: entry.assetIDs, isFavorite: false, isHidden: nil)
        case .unfavorite: applyFlag(ids: entry.assetIDs, isFavorite: true, isHidden: nil)
        case .hide:       applyFlag(ids: entry.assetIDs, isFavorite: nil, isHidden: false)
        case .unhide:     applyFlag(ids: entry.assetIDs, isFavorite: nil, isHidden: true)
        case .moveToRecentlyDeleted, .addToAlbum:
            break   // 重建资源/相簿引用经库侧 observer 同步；快照中旧项已在删除时移除
        }
        onUndoApplied?()
    }

    private func applyFlag(ids: [String], isFavorite: Bool?, isHidden: Bool?) {
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            let old = items[index]
            items[index] = PhotoItem(id: old.id,
                                     mediaType: old.mediaType,
                                     mediaSubtypes: old.mediaSubtypes,
                                     creationDate: old.creationDate,
                                     modificationDate: old.modificationDate,
                                     pixelWidth: old.pixelWidth,
                                     pixelHeight: old.pixelHeight,
                                     duration: old.duration,
                                     isFavorite: isFavorite ?? old.isFavorite,
                                     isHidden: isHidden ?? old.isHidden,
                                     location: old.location,
                                     burstIdentifier: old.burstIdentifier,
                                     isCloudOnly: old.isCloudOnly)
        }
        isFavoriteCurrent = current?.isFavorite ?? false
    }
}
