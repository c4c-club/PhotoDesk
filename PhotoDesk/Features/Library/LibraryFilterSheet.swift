// MARK: - 职责说明：完整筛选面板（docs/09 D10）——日期三级下钻 + 媒体类型多选 + 状态 + 位置
// （含聚类列表入口）；应用/重置。数据源选项来自 viewModel 当前 scope 全量（PhotoFilter.available*）。
// 筛选条件经 LibraryViewModel.setFilter 持久化（library.filter.<scope>）。

import SwiftUI
import PhotoDeskCore

struct LibraryFilterSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var draft: SearchPredicate
    @State private var showLocationPicker = false
    @Environment(\.dismiss) private var dismiss

    private static let monthNames = ["", "1月", "2月", "3月", "4月", "5月", "6月",
                                     "7月", "8月", "9月", "10月", "11月", "12月"]

    init(viewModel: LibraryViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.query.filter)
    }

    var body: some View {
        NavigationView {
            Form {
                dateSection
                mediaSection
                statusSection
                locationSection
                actionSection
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("重置") { draft = .default }
                        .disabled(draft.isDefault)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        viewModel.setFilter(draft)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showLocationPicker) {
            LocationFilterView(items: viewModel.visibleItems,
                               selected: draft.location) { location in
                draft.location = location
            }
        }
    }

    // MARK: - 日期（三级下钻）

    private var dateSection: some View {
        Section("日期") {
            drillMenu(title: draft.year.map(String.init) ?? "不限年份",
                      options: PhotoFilter.availableYears(viewModel.visibleItems).map(String.init),
                      isSelected: draft.year == nil,
                      onSelect: { text in
                          draft.year = Int(text)
                          draft.month = nil
                          draft.day = nil
                      })
            if let year = draft.year {
                drillMenu(title: draft.month.map { Self.monthNames[$0] } ?? "不限月份",
                          options: PhotoFilter.availableMonths(viewModel.visibleItems, year: year)
                              .map { Self.monthNames[$0] },
                          isSelected: draft.month == nil,
                          onSelect: { text in
                              draft.month = Self.monthNumber(from: text)
                              draft.day = nil
                          })
            }
            if let year = draft.year, let month = draft.month {
                drillMenu(title: draft.day.map { "\($0) 日" } ?? "不限日期",
                          options: PhotoFilter.availableDays(viewModel.visibleItems, year: year, month: month)
                              .map { "\($0) 日" },
                          isSelected: draft.day == nil,
                          onSelect: { text in
                              draft.day = Int(text.prefix(while: \.isNumber))
                          })
            }
            if draft.year != nil || draft.month != nil || draft.day != nil {
                Button("清除日期条件") {
                    draft.year = nil
                    draft.month = nil
                    draft.day = nil
                }
                .foregroundColor(Color(ds: DSColor.tint))
            }
        }
    }

    // MARK: - 媒体类型

    private var mediaSection: some View {
        Section("媒体类型") {
            ForEach(SearchPredicate.MediaFilter.allCases) { filter in
                Button {
                    if draft.media.contains(filter) {
                        draft.media.remove(filter)
                    } else {
                        draft.media.insert(filter)
                    }
                } label: {
                    HStack {
                        Text(filter.displayName)
                            .foregroundColor(Color(ds: DSColor.textPrimary))
                        Spacer()
                        if draft.media.contains(filter) {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(ds: DSColor.tint))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section("状态") {
            // .hidden 仅 scope == .hidden 场景可见（docs/09 D10）
            let statuses = viewModel.query.scope == .hidden
                ? SearchPredicate.StatusFilter.allCases
                : SearchPredicate.StatusFilter.allCases.filter { $0 != .hidden }
            ForEach(statuses) { status in
                Button {
                    if draft.status.contains(status) {
                        draft.status.remove(status)
                    } else {
                        draft.status.insert(status)
                    }
                } label: {
                    HStack {
                        Text(status.displayName)
                            .foregroundColor(Color(ds: DSColor.textPrimary))
                        Spacer()
                        if draft.status.contains(status) {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(ds: DSColor.tint))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 位置

    private var locationSection: some View {
        Section("位置") {
            Button {
                showLocationPicker = true
            } label: {
                HStack {
                    Text("位置条件")
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Spacer()
                    Text(locationSummary)
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }
            if case .near(let region) = draft.location {
                Button("清除位置条件") {
                    draft.location = .any
                }
                .foregroundColor(Color(ds: DSColor.tint))
                Text(String(format: "当前：%.1f°, %.1f° 附近 %.0f km",
                            region.center.latitude, region.center.longitude, region.radiusKm))
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
        }
    }

    private var locationSummary: String {
        switch draft.location {
        case .any:              return "不限"
        case .withLocation:     return "有位置"
        case .withoutLocation:  return "无位置"
        case .near(let region): return String(format: "%.1f°, %.1f° 附近", region.center.latitude, region.center.longitude)
        }
    }

    // MARK: - 应用

    private var actionSection: some View {
        Section {
            Button {
                viewModel.setFilter(draft)
                dismiss()
            } label: {
                Text("应用筛选（预计 \(previewCount) 项）")
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(Color(ds: DSColor.tint))
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private var previewCount: Int {
        PhotoFilter.apply(viewModel.visibleItems, predicate: draft).count
    }

    // MARK: - helpers

    private func drillMenu(title: String, options: [String], isSelected: Bool,
                           onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { onSelect(option) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
        }
        .accessibilityLabel("日期筛选，当前 \(title)")
    }

    private static func monthNumber(from name: String) -> Int? {
        monthNames.firstIndex(of: name).flatMap { $0 > 0 ? $0 : nil }
    }
}
