// MARK: - 职责说明：搜索/筛选 ViewModel（docs/05 M5 任务 5.1/5.2）——
// 谓词（@Published）→ PhotoFilter 纯函数 → 结果集。
// M17 T08 X03：数据源改为实时快照——itemsProvider 闭包 + 打开/激活 refresh() 重取；
// apply() 放后台（Task.detached）+ 代际令牌，过期结果丢弃（参照 LibraryViewModel
// rebuildDerivedInBackground）。不触碰 PhotoKit。
/// OCR 关键词索引与搜索历史/智能视图为后续增强，登记于已知问题。

import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var predicate = SearchPredicate.default
    @Published private(set) var results: [PhotoItem] = []
    /// 最近筛选历史（最多 10 条，JSON 持久化；docs/22 Phase 4 搜索页）
    @Published private(set) var history: [SearchPredicate] = []

    /// 实时快照源（X03：sheet 打开瞬间不再固化图库）
    private let itemsProvider: () -> [PhotoItem]
    private(set) var items: [PhotoItem]
    /// apply 代际令牌：谓词连续变化时只落最新一代结果
    private var applyGeneration = 0
    private static let historyKey = "search.filter.history"

    init(itemsProvider: @escaping () -> [PhotoItem]) {
        self.itemsProvider = itemsProvider
        self.items = itemsProvider()
        results = items
        loadHistory()
    }

    /// 打开/激活时刷新（X03）：重取最新快照并按当前谓词重算
    func refresh() {
        items = itemsProvider()
        apply()
    }

    /// 谓词变化后重算（SwiftUI onChange 驱动）：后台执行 + 代际令牌
    func apply() {
        applyGeneration += 1
        let generation = applyGeneration
        let snapshot = items
        let predicate = self.predicate
        Task.detached(priority: .userInitiated) { [weak self] in
            let filtered = PhotoFilter.apply(snapshot, predicate: predicate)
            await MainActor.run { [weak self] in
                guard let self, generation == self.applyGeneration else { return }
                self.results = filtered
            }
        }
    }

    func toggleMedia(_ filter: SearchPredicate.MediaFilter) {
        if predicate.media.contains(filter) {
            predicate.media.remove(filter)
        } else {
            predicate.media.insert(filter)
        }
        apply()
    }

    func toggleStatus(_ status: SearchPredicate.StatusFilter) {
        if predicate.status.contains(status) {
            predicate.status.remove(status)
        } else {
            predicate.status.insert(status)
        }
        apply()
    }

    func setYear(_ year: Int?) {
        predicate.year = year
        predicate.month = nil
        predicate.day = nil
        apply()
    }

    func setMonth(_ month: Int?) {
        predicate.month = month
        predicate.day = nil
        apply()
    }

    func setDay(_ day: Int?) {
        predicate.day = day
        apply()
    }

    func reset() {
        predicate = .default
        apply()
    }

    // MARK: - 最近筛选历史（最多 10 条）

    func recordCurrentFilter() {
        guard !predicate.isDefault else { return }
        var next = history.filter { $0 != predicate }
        next.insert(predicate, at: 0)
        if next.count > 10 { next = Array(next.prefix(10)) }
        history = next
        saveHistory()
    }

    func applyHistory(_ item: SearchPredicate) {
        predicate = item
        apply()
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    /// 删除单条历史（docs/25 §7 #5：历史 chip 上的 × 按钮）
    func removeHistory(at index: Int) {
        guard history.indices.contains(index) else { return }
        history.remove(at: index)
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([SearchPredicate].self, from: data) else { return }
        history = Array(decoded.prefix(10))
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }

    // MARK: - 下钻选项源

    var availableYears: [Int] {
        PhotoFilter.availableYears(items)
    }

    func availableMonths(inYear year: Int) -> [Int] {
        PhotoFilter.availableMonths(items, year: year)
    }

    func availableDays(inYear year: Int, month: Int) -> [Int] {
        PhotoFilter.availableDays(items, year: year, month: month)
    }
}
