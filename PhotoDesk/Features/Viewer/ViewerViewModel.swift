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

    /// 会话暂存结果（docs/13 S12 删除事务：plan 阶段产物，不改 items/currentIndex）
    struct StagedPlan: Equatable {
        let action: SwipeAction
        /// 被移除条目在移除前的 index（VC 用 performBatchUpdates 删除 cell）
        let removedIndex: Int
        /// 撤销用：被移除的 item 快照
        let removedItem: PhotoItem
        /// 补位计划（ReplacementPlanner 纯函数）
        let plan: ReplacementPlan
        let kind: PendingKind
        let toastText: String
    }

    /// commitRemoval 的结果（completion 定位/关闭用）
    struct RemovalResult: Equatable {
        let nextIndex: Int?
        let shouldClose: Bool
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
    private var lastStaged: StagedPlan?

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

    // MARK: - 删除事务（docs/13 S12：plan 不改数组 → commit 在 batch block 内 → rollback 兜底）

    /// 阶段 1 · plan：入队会话 + 计算补位计划。**不改 items、不改 currentIndex**（单一事实来源不变量 I1/I2）。
    /// - Parameter exitEdge: 飞出边（上滑 = .top，下滑 = .bottom；工具栏动作 = nil → 默认底部前进）
    func planRemoval(action: SwipeAction, forItemID id: String, exitEdge: VerticalEdge?) -> StagedPlan? {
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

        let plan = ReplacementPlanner.plan(currentIndex: index,
                                           countAfterRemoval: items.count - 1,
                                           exitEdge: exitEdge,
                                           hasNext: index + 1 < items.count,
                                           hasPrevious: index > 0)
        let staged = StagedPlan(action: action,
                                removedIndex: index,
                                removedItem: item,
                                plan: plan,
                                kind: kind,
                                toastText: toast)
        lastStaged = staged
        return staged
    }

    /// 阶段 2 · commit：**只在 performBatchUpdates block 内调用一次**；移除 item 并按计划推进 currentIndex。
    func commitRemoval(_ staged: StagedPlan) -> RemovalResult {
        guard items.indices.contains(staged.removedIndex),
              items[staged.removedIndex].id == staged.removedItem.id else {
            // 数组与 plan 失配（回滚后重复 commit 等防御路径）：按当前长度钳制，不让 index 越界
            let clamped = min(staged.plan.nextIndex ?? 0, max(0, items.count - 1))
            currentIndex = max(0, clamped)
            isFavoriteCurrent = current?.isFavorite ?? false
            return RemovalResult(nextIndex: items.isEmpty ? nil : currentIndex,
                                 shouldClose: items.isEmpty)
        }
        items.remove(at: staged.removedIndex)
        if staged.plan.shouldClose || items.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(staged.plan.nextIndex ?? 0, items.count - 1)
        }
        isFavoriteCurrent = current?.isFavorite ?? false
        return RemovalResult(nextIndex: staged.plan.nextIndex,
                             shouldClose: staged.plan.shouldClose || items.isEmpty)
    }

    /// 阶段 3 · rollback：入队失败/取消时恢复 item 原位（零 PhotoKit 写）
    func rollbackRemoval(_ staged: StagedPlan) {
        reviewSession.undoPending(id: staged.removedItem.id, kind: staged.kind)
        guard !items.contains(where: { $0.id == staged.removedItem.id }) else { return }
        let insertIndex = min(staged.removedIndex, items.count)
        items.insert(staged.removedItem, at: insertIndex)
        currentIndex = insertIndex
        isFavoriteCurrent = current?.isFavorite ?? false
    }

    /// staged 撤销（Toast「撤销」）：从队列移除 + 本地还原（零 PhotoKit 写）
    func undoStaged() {
        guard let staged = lastStaged else { return }
        lastStaged = nil
        rollbackRemoval(staged)
        onItemRestored?()
    }

    /// staged 撤销窗口到期（docs/16 M12 R04：唯一时钟驱动到点调用）——
    /// 撤销入口失效；会话暂存保持（整理回顾仍可处理），不做任何 PhotoKit 写
    func expireStaged() {
        lastStaged = nil
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
