// MARK: - 职责说明：撤销中心（docs/03 §5.1 / docs/02 §3.5 / docs/05 M3 任务 4）——
// 五类撤销：收藏 / 取消收藏 / 隐藏 / 取消隐藏 / 移到最近删除（TrashBin 副本重建）/ 加相簿（移出引用）。
// 持久化：Core Data ActionLog（prevState 语义由 kind 载荷承载）——杀 App 重启后恢复未过期条目，
// 顶部提示「上次有 N 个操作可撤销」。窗口判定用 PhotoDeskCore.UndoPolicy + 注入 Clock（docs/03 §8）。
// 只保留最新一条活跃条目（Toast 单条交互）；撤销窗口过后由系统「最近删除」30 天兜底（红线 1）。

import CoreData
import Foundation
import PhotoDeskCore

@MainActor
final class UndoCenter: ObservableObject {
    /// 可撤销动作类型（持久化 kind 原值）
    enum ActionKind: String, Codable {
        case favorite
        case unfavorite
        case hide
        case unhide
        case moveToRecentlyDeleted
        case addToAlbum
    }

    /// 活跃撤销条目
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let kind: ActionKind
        let assetIDs: [String]
        /// addToAlbum 的目标相簿（撤销 = 移出引用，照片本身不删）
        let albumID: String?
        /// moveToRecentlyDeleted 的副本记录 id（撤销 = TrashBin 重建）
        let trashRecordIDs: [UUID]
        let toastText: String
        let createdAt: Date
        let expiresAt: Date
    }

    /// 最新可撤销条目（驱动 DSToast 显示）
    @Published private(set) var activeEntry: Entry?
    /// 是否有可撤销条目（Toast 是否显示「撤销」按钮）
    var hasActiveEntry: Bool { activeEntry != nil }
    /// 过期时通知（VC 收起 Toast）
    var onExpire: ((Entry) -> Void)?

    private let writer: PhotoWriterProtocol
    private let trashBin: TrashBin?
    private let persistence: PersistenceController
    private let clock: Clock
    private var ticker: Timer?

    init(writer: PhotoWriterProtocol,
         trashBin: TrashBin? = nil,
         persistence: PersistenceController = .shared,
         clock: Clock = SystemClock()) {
        self.writer = writer
        self.trashBin = trashBin
        self.persistence = persistence
        self.clock = clock
    }

    // MARK: - 入栈（执行成功后调用）

    func push(kind: ActionKind,
              assetIDs: [String],
              albumID: String? = nil,
              trashRecordIDs: [UUID] = [],
              toastText: String,
              window: TimeInterval) -> Entry {
        let entry = Entry(id: UUID(),
                          kind: kind,
                          assetIDs: assetIDs,
                          albumID: albumID,
                          trashRecordIDs: trashRecordIDs,
                          toastText: toastText,
                          createdAt: clock.now,
                          expiresAt: clock.now.addingTimeInterval(window))
        activeEntry = entry
        persist(entry)
        startTicker()
        return entry
    }

    // MARK: - 撤销（Toast「撤销」/ 重启恢复横幅）

    /// 执行反向 PhotoKit 写；成功返回条目（供调用方还原本地状态）
    func undo() async -> Entry? {
        guard let entry = activeEntry else { return nil }
        activeEntry = nil
        stopTicker()
        do {
            switch entry.kind {
            case .favorite(let ids):           try await writer.setFavorite(ids: ids, isFavorite: false)
            case .unfavorite(let ids):         try await writer.setFavorite(ids: ids, isFavorite: true)
            case .hide(let ids):               try await writer.setHidden(ids: ids, isHidden: false)
            case .unhide(let ids):             try await writer.setHidden(ids: ids, isHidden: true)
            case .moveToRecentlyDeleted(let recordIDs, _):
                guard let trashBin else { throw PhotoWriter.PhotoWriterError.changeRejected }
                for recordID in recordIDs {
                    _ = try await trashBin.restore(recordID: recordID)   // 重建照片（新 localID 经 observer 同步回网格）
                }
            case .addToAlbum(let ids, let albumID):
                try await writer.remove(ids: ids, fromAlbum: albumID)
            }
            markUndone(entry)
            return entry
        } catch {
            // 撤销失败：保留条目（窗口内可重试）
            activeEntry = entry
            startTicker()
            return nil
        }
    }

    func dismissActive() {
        guard let entry = activeEntry else { return }
        activeEntry = nil
        stopTicker()
        markUndone(entry)
    }

    // MARK: - 重启恢复（docs/05 M3 验收：重启后 10 秒内提示）

    /// 未过期且未撤销的持久化条目数
    func recoverableCount() -> Int {
        fetchRows().filter { clock.now < $0.expiresAt }.count
    }

    /// 取最新未过期条目恢复为活跃条目（重启后调用）
    @discardableResult
    func restoreLatestIfNeeded() -> Entry? {
        guard activeEntry == nil,
              let row = fetchRows().first(where: { clock.now < $0.expiresAt }) else { return nil }
        let entry = Entry(id: row.id,
                          kind: row.kind,
                          assetIDs: row.assetIDs,
                          albumID: row.albumID,
                          trashRecordIDs: row.trashRecordIDs,
                          toastText: row.toastText,
                          createdAt: row.createdAt,
                          expiresAt: row.expiresAt)
        activeEntry = entry
        startTicker()
        return entry
    }

    // MARK: - 过期计时

    var onExpire: ((Entry) -> Void)?

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
        guard let entry = activeEntry, clock.now >= entry.expiresAt else { return }
        activeEntry = nil
        stopTicker()
        removeRow(id: entry.id)
        onExpire?(entry)
    }

    // MARK: - ActionLog 持久化（Core Data）

    private struct LogRow {
        let id: UUID
        let kind: ActionKind
        let assetIDs: [String]
        let albumID: String?
        let trashRecordIDs: [UUID]
        let toastText: String
        let createdAt: Date
        let expiresAt: Date
    }

    private func persist(_ entry: Entry) {
        persistence.performBackground { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: "ActionLog", into: context)
            object.setValue(entry.id, forKey: "id")
            object.setValue(entry.kind.rawValue, forKey: "kind")
            object.setValue(Self.json(entry.assetIDs), forKey: "assetIDsJSON")
            object.setValue(entry.albumID, forKey: "albumID")
            object.setValue(Self.json(entry.trashRecordIDs.map(\.uuidString)), forKey: "prevStateJSON")
            object.setValue(entry.toastText, forKey: "toastText")
            object.setValue(entry.createdAt, forKey: "createdAt")
            object.setValue(entry.expiresAt, forKey: "expiresAt")
            object.setValue(false, forKey: "isUndone")
            try? context.save()
        }
    }

    private func markUndone(_ entry: Entry) {
        persistence.performBackground { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ActionLog")
            request.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
            (try? context.fetch(request))?.forEach {
                $0.setValue(true, forKey: "isUndone")
            }
            try? context.save()
        }
    }

    private func removeRow(id: UUID) {
        persistence.performBackground { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ActionLog")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            (try? context.fetch(request))?.forEach { context.delete($0) }
            try? context.save()
        }
    }

    private func fetchRows() -> [LogRow] {
        var rows: [LogRow] = []
        persistence.container.viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ActionLog")
            request.predicate = NSPredicate(format: "isUndone == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            let objects = (try? persistence.container.viewContext.fetch(request)) ?? []
            rows = objects.compactMap { object in
                guard let id = object.value(forKey: "id") as? UUID,
                      let kindRaw = object.value(forKey: "kind") as? String,
                      let kind = ActionKind(rawValue: kindRaw),
                      let assetIDsJSON = object.value(forKey: "assetIDsJSON") as? String,
                      let assetIDsData = assetIDsJSON.data(using: .utf8),
                      let assetIDs = try? JSONDecoder().decode([String].self, from: assetIDsData),
                      let createdAt = object.value(forKey: "createdAt") as? Date,
                      let expiresAt = object.value(forKey: "expiresAt") as? Date else { return nil }
                let prevStateJSON = object.value(forKey: "prevStateJSON") as? String
                let recordIDs = (prevStateJSON.flatMap { $0.data(using: .utf8) })
                    .flatMap { try? JSONDecoder().decode([String].self, from: $0) }?
                    .compactMap { UUID(uuidString: $0) } ?? []
                return LogRow(id: id, kind: kind, assetIDs: assetIDs,
                              albumID: object.value(forKey: "albumID") as? String,
                              trashRecordIDs: recordIDs,
                              toastText: object.value(forKey: "toastText") as? String ?? "",
                              createdAt: createdAt, expiresAt: expiresAt)
            }
        }
        return rows
    }



    private nonisolated static func json(_ array: [String]) -> String {
        guard let data = try? JSONEncoder().encode(array),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}
