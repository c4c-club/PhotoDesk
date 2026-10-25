// MARK: - 职责说明：搜索/筛选 ViewModel（docs/05 M5 任务 5.1/5.2）——
// 谓词（@Published）→ PhotoFilter 纯函数 → 结果集；筛选在主线程对已加载快照执行
// （万级 < 500ms，SearchPredicateTests 实测），不触碰 PhotoKit。
/// OCR 关键词随 P2 的 OCRText 索引接入（TODO(P5-P2)）；搜索历史/智能视图同属 P2。

import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var predicate = SearchPredicate.default
    @Published private(set) var results: [PhotoItem] = []

    let items: [PhotoItem]

    init(items: [PhotoItem]) {
        self.items = items
        results = items
    }

    /// 谓词变化后重算（SwiftUI onChange 驱动）
    func apply() {
        results = PhotoFilter.apply(items, predicate: predicate)
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
