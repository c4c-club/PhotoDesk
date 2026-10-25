// MARK: - 职责说明：全屏浏览器 ViewModel（docs/05 M2 任务 2.6 执行管线）——
// 持有照片快照（LibraryViewModel.items 的值拷贝，关闭浏览器后由库侧 observer 增量同步）；
// 方向 → 动作解析（设置 gesture.up/down）；动作执行（PhotoWriter）→ 撤销入栈（UndoCenter）→ autoAdvance 标记。
// 红线 1：moveToRecentlyDeleted 在 TrashBin（M3）就绪前不执行，明确拒绝而非假装成功。

import Foundation
import PhotoDeskCore

@MainActor
final class ViewerViewModel: ObservableObject {
    /// 动作执行结果
    enum ActionOutcome {
        /// 成功：更新后的 item + Toast 文案 + 可撤销条目
        case success(PhotoItem, toastText: String, undo: UndoCenter.Entry.Kind?)
        /// 拒绝执行（含「后续版本开放」），展示 message
        case rejected(String)
    }

    @Published private(set) var items: [PhotoItem]
    @Published private(set) var currentIndex: Int
    @Published private(set) var isFavoriteCurrent = false

    /// VC 注册：撤销成功后还原本地状态（favorite/hidden 取反）
    var onUndoApplied: (() -> Void)?

    var current: PhotoItem? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    private let settings: SettingsStore
    private let writer: PhotoWriter
    private let undoCenter: UndoCenter

    init(items: [PhotoItem],
         startIndex: Int,
         settings: SettingsStore,
         writer: PhotoWriter,
         undoCenter: UndoCenter) {
        self.items = items
        self.currentIndex = max(0, min(startIndex, max(0, items.count - 1)))
        self.settings = settings
        self.writer = writer
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
                return success(item, isFavorite: true, isHidden: item.isHidden,
                               kind: .favorite([item.id]), toastText: action.toastText)

            case .unfavorite:
                try await writer.setFavorite(ids: [item.id], isFavorite: false)
                return success(item, isFavorite: false, isHidden: item.isHidden,
                               kind: .unfavorite([item.id]), toastText: action.toastText)

            case .toggleFavorite:
                return await execute(item.isFavorite ? .unfavorite : .favorite, for: item)

            case .hide:
                try await writer.setHidden(ids: [item.id], isHidden: true)
                return success(item, isFavorite: item.isFavorite, isHidden: true,
                               kind: .hide([item.id]), toastText: action.toastText)

            case .unhide:
                try await writer.setHidden(ids: [item.id], isHidden: false)
                return success(item, isFavorite: item.isFavorite, isHidden: false,
                               kind: .unhide([item.id]), toastText: action.toastText)

            case .moveToRecentlyDeleted:
                // 红线 1：唯一删除实现是 deleteAssets（移入系统「最近删除」30 天），
                // 且执行前必须先落 TrashBin 撤销保险副本（M3）。就绪前明确拒绝，不做假删除。
                return .rejected("「移到最近删除」将在撤销保险副本就绪后开放（当前版本）")

            case .addToAlbum, .share, .showInfo, .rotate:
                return .rejected("该动作将在后续里程碑开放")

            case .dismiss:
                return .rejected("退出浏览由浏览页直接处理")

            case .none:
                return .rejected("")
            }
        } catch {
            return .rejected("操作失败：\(error.localizedDescription)")
        }
    }

    private func success(_ item: PhotoItem, isFavorite: Bool, isHidden: Bool,
                         kind: UndoCenter.Entry.Kind, toastText: String) -> ActionOutcome {
        let updated = PhotoItem(id: item.id,
                                mediaType: item.mediaType,
                                mediaSubtypes: item.mediaSubtypes,
                                creationDate: item.creationDate,
                                modificationDate: item.modificationDate,
                                pixelWidth: item.pixelWidth,
                                pixelHeight: item.pixelHeight,
                                duration: item.duration,
                                isFavorite: isFavorite,
                                isHidden: isHidden,
                                location: item.location,
                                burstIdentifier: item.burstIdentifier,
                                isCloudOnly: item.isCloudOnly)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        }
        isFavoriteCurrent = isFavorite
        let entry = undoCenter.push(kind: kind, toastText: toastText,
                                    window: settings.undoWindow)
        return .success(updated, toastText: toastText, undo: entry.kind)
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
        let ids: [String]
        let isFavorite: Bool?
        let isHidden: Bool?
        switch entry.kind {
        case .favorite(let list):  ids = list; isFavorite = false; isHidden = nil
        case .unfavorite(let list): ids = list; isFavorite = true; isHidden = nil
        case .hide(let list):       ids = list; isFavorite = nil; isHidden = false
        case .unhide(let list):     ids = list; isFavorite = nil; isHidden = true
        }
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
        onUndoApplied?()
    }
}
