// MARK: - 职责说明：全屏浏览器 ViewModel（docs/05 M2/M3；docs/09 Phase 4 重写）★——
// 按 assetID 定位（ViewerContext）；删除/隐藏走会话暂存（D16）：同步入队 + 本地移除 + ReplacementPlan
// 补位计划，全程不 await PhotoKit（0 系统弹窗）；收藏/取消收藏仍即时写（乐观更新 + 撤销栈）。
// 红线 1：真正删除只发生在 ReviewSessionController.commitDeletes → PhotoWriter.moveToRecentlyDeleted。

import Foundation
import PhotoDeskCore

@MainActor
final class ViewerViewModel: ObservableObject {
    /// 动作执行结果（收藏等即时写路径）
    enum ActionOutcome {
        /// 成功：更新后的 item + Toast 文案 + 可撤销类型（nil=该动作不可撤销）
        case success(PhotoItem, toastText: String, undoKind: UndoCenter.ActionKind?)
        /// 拒绝执行，展示 message
        case rejected(String)
    }

    /// 会话暂存结果（docs/09 D02/D16：删除/隐藏滑动路径，同步返回补位计划）
    struct StagedOutcome {
        let plan: ReplacementPlan
        /// 被移除条目在移除前的 index（VC 用 performBatchUpdates 删除 cell）
        let removedIndex: Int
        let toastText: String
        let kind: PendingKind
        /// 撤销用：被移除的 item 快照
        let removedItem: PhotoItem
    }

    @Published private(set) var items: [PhotoItem]
    @Published private(set) var currentIndex: Int
    @Published private(set) var isFavoriteCurrent = false

    /// VC 注册：撤销成功后还原本地状态
    var onUndoApplied: (() -> Void)?
    /// staged 撤销后（恢复 item），VC 刷新集合视图
    var onItemRestored: (() -> Void)?

    var current: PhotoItem? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    /// 当前条目 id（DEBUG 横幅 / 测试）
    var currentItemID: String? { current?.id }

    private let settings: SettingsStore
    private let writer: PhotoWriterProtocol
    private let trashBin: TrashBin
    private let undoCenter: UndoCenter
    private let reviewSession: ReviewSessionController
    /// 最近一次 staged 条目（Toast「撤销」用；窗口与 Toast 生命周期一致）
    private var lastStaged: StagedOutcome?

    init(context: ViewerContext,
         settings: SettingsStore,
         writer: PhotoWriterProtocol,
         trashBin: TrashBin,
         undoCenter: UndoCenter,
         reviewSession: ReviewSessionController) {
        let startIndex = context.items.firstIndex(where: { $0.id == context.startItemID }) ?? 0
        self.items = context.items
        self.currentIndex = startIndex
        self.settings = settings
        self.writer = writer
        self.trashBin = trashBin
        self.undoCenter = undoCenter
        self.reviewSession = reviewSession
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    // MARK: - 方向 → 动作

    func action(for direction: SwipeDirection) -> SwipeAction {
        switch direction {
        case .up:   return settings.swipeUpAction
        case .down: return settings.swipeDownAction
        }
    }

    // MARK: - 会话暂存（docs/09 D16：滑动删除/隐藏 → 同步入队，不 await PhotoKit）

    /// - Parameter exitEdge: 飞出边（上滑 = .top，下滑 = .bottom；工具栏动作 = nil → 默认底部前进）
    func stage(_ action: SwipeAction, forItemID id: String, exitEdge: VerticalEdge?) -> StagedOutcome? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items[index]
        let kind: PendingKind
        let toast: String
        switch action {
        case .moveToRecentlyDeleted:
            kind = .delete
            toast = "已标记待删除"
        case .hide:
            kind = .hide
            toast = "已加入待隐藏"
        default:
            return nil
        }
        let enqueued = kind == .delete
            ? reviewSession.enqueueDelete(id: id, originIndex: index)
            : reviewSession.enqueueHide(id: id, originIndex: index)
        guard enqueued else { return nil }

        // 本地移除 + 补位计划（纯函数）
        items.remove(at: index)
        let countAfter = items.count
        let plan = ReplacementPlanner.plan(currentIndex: index,
                                           countAfterRemoval: countAfter,
                                           exitEdge: exitEdge,
                                           hasNext: index < countAfter,
                                           hasPrevious: index > 0)
        currentIndex = plan.nextIndex ?? 0
        isFavoriteCurrent = current?.isFavorite ?? false

        let outcome = StagedOutcome(plan: plan,
                                    removedIndex: index,
                                    toastText: toast,
                                    kind: kind,
                                    removedItem: item)
        lastStaged = outcome
        return outcome
    }

    /// staged 撤销（Toast「撤销」）：从队列移除 + 本地还原（零 PhotoKit 写）
    func undoStaged() {
        guard let staged = lastStaged else { return }
        lastStaged = nil
        reviewSession.undoPending(id: staged.removedItem.id, kind: staged.kind)
        // 还原到原 index（夹紧到当前长度）
        let insertIndex = min(staged.removedIndex, items.count)
        items.insert(staged.removedItem, at: insertIndex)
        currentIndex = insertIndex
        isFavoriteCurrent = current?.isFavorite ?? false
        onItemRestored?()
    }

    var hasUndoableStaged: Bool { lastStaged != nil }

    // MARK: - 即时写动作（收藏 / 取消收藏 / 取消隐藏；docs/09 §2.4 动作策略表）

    func execute(_ action: SwipeAction, for item: PhotoItem) async -> ActionOutcome {
        // 新的即时动作覆盖旧的 staged 撤销窗口（Toast 一次只对应最近一个动作）
        lastStaged = nil
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

            case .unhide:
                try await writer.setHidden(ids: [item.id], isHidden: false)
                return await success(item, isFavorite: item.isFavorite, isHidden: false,
                                     kind: .unhide, toastText: action.toastText)

            case .hide, .moveToRecentlyDeleted:
                // 会话暂存路径（stage），不走这里（docs/09 D16：滑动全程 0 PhotoKit 写）
                return .rejected("")

            case .addToAlbum, .share, .showInfo, .rotate:
                // VC 直接处理（相簿选择器 / 分享面板 / 信息面板 / 编辑器旋转），不再返回「未开放」
                return .rejected("")

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

    private func success(_ item: PhotoItem, isFavorite: Bool, isHidden: Bool,
                         kind: UndoCenter.ActionKind, toastText: String) async -> ActionOutcome {
        applyLocal(item: item, isFavorite: isFavorite, isHidden: isHidden)
        undoCenter.push(kind: kind,
                        assetIDs: [item.id],
                        toastText: toastText,
                        window: settings.undoWindow)
        return .success(item, toastText: toastText, undoKind: kind)
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

    // MARK: - 翻页

    func updateIndex(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        currentIndex = index
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    func index(of id: String) -> Int? {
        items.firstIndex(where: { $0.id == id })
    }

    // MARK: - 撤销

    /// Toast「撤销」：staged（零写）优先，其次 PhotoKit 反向写
    func undoLast() async {
        if hasUndoableStaged {
            undoStaged()
            return
        }
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
