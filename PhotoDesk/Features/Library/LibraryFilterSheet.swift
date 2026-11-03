// MARK: - 职责说明：完整筛选面板（docs/09 D10）——日期三级下钻 + 媒体类型多选 + 状态 + 位置
// （含聚类列表入口）；应用/重置。数据源选项来自 viewModel 当前 scope 全量（PhotoFilter.available*）。
// 筛选条件经 LibraryViewModel.setFilter 持久化（library.filter.<scope>）。

import SwiftUI
import PhotoDeskCore

struct LibraryFilterSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var draft: SearchPredicate
    @State private var showLocationPicker = false
    /// 预览计数（docs/13 S03 修复 6：@State + 200ms debounce，不在 body 里全量扫描）
    @State private var previewCount: Int?
    @State private var previewTask: Task<Void, Never>?
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
                // docs/13 S06：顶部筛选栏移除后，chips 迁移到面板顶部「当前条件」
                if !conditionChips.isEmpty {
                    currentConditionsSection
                }
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
        .onAppear { schedulePreview() }
        .onChange(of: draft) { _ in schedulePreview() }
        .onDisappear { previewTask?.cancel() }
        .sheet(isPresented: $showLocationPicker) {
            LocationFilterView(items: viewModel.visibleItems,
                               selected: draft.location) { location in
                draft.location = location
            }
        }
    }

    /// 200ms debounce 计算一次预览计数（后台 Task，不在 body 内）
    private func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak viewModel] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let items = viewModel?.visibleItems ?? []
            let predicate = draft
            let count = PhotoFilter.apply(items, predicate: predicate).count
            guard !Task.isCancelled else { return }
            await MainActor.run { previewCount = count }
        }
    }

    // MARK: - 当前条件（docs/13 S06：chips + 清除全部）

    private var currentConditionsSection: some View {
        Section("当前条件") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(conditionChips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(ds: DSColor.tint).opacity(0.15))
                            .foregroundColor(Color(ds: DSColor.tint))
                            .cornerRadius(12)
                    }
                }
            }
            Button("清除全部条件") {
                draft = .default
            }
            .foregroundColor(Color(ds: DSColor.tint))
        }
    }

    private var conditionChips: [String] {
        var chips: [String] = []
        if let year = draft.year {
            chips.append("\(year) 年")
            if let month = draft.month { chips.append("\(month) 月") }
            if let day = draft.day { chips.append("\(day) 日") }
        }
        chips.append(contentsOf: draft.media.sorted { $0.rawValue < $1.rawValue }.map(\.displayName))
        chips.append(contentsOf: draft.status.sorted { $0.rawValue < $1.rawValue }.map(\.displayName))
        switch draft.location {
        case .withLocation:     chips.append("有位置")
        case .withoutLocation:  chips.append("无位置")
        case .near(let region): chips.append(String(format: "%.1f°,%.1f° 附近",
                                                    region.center.latitude, region.center.longitude))
        case .any:              break
        }
        return chips
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
                Text(previewCountText)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(Color(ds: DSColor.tint))
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private var previewCountText: String {
        guard let count = previewCount else { return "计算中…" }
        return "应用筛选（预计 \(count) 项）"
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
