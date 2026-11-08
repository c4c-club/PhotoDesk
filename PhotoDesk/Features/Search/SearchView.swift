// MARK: - 职责说明：搜索/筛选页（docs/04 §2 / docs/05 M5 任务 5.1；docs/09 D10/D15 改造）——
// 日期三级下钻（年→月→日菜单）+ 媒体类型多选 chips + 状态筛选 + 结果计数与缩略图网格。
// docs/09：结果可点开查看器（ViewerContext）；「应用筛选到主库」回调；去掉 200 上限（全量展示）。

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    /// 「应用筛选到主库」（docs/09 D15：作用于 LibraryViewModel.setFilter）
    var onApplyFilter: ((SearchPredicate) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var viewerContext: ViewerContext?

    init(items: [PhotoItem], onApplyFilter: ((SearchPredicate) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(items: items))
        self.onApplyFilter = onApplyFilter
    }

    private static let monthNames = ["", "1月", "2月", "3月", "4月", "5月", "6月",
                                     "7月", "8月", "9月", "10月", "11月", "12月"]

    var body: some View {
        NavigationView {
            content
                .navigationTitle("搜索与筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("完成") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("重置") { viewModel.reset() }
                            .disabled(viewModel.predicate.isDefault)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("应用到主库") {
                            viewModel.recordCurrentFilter()
                            onApplyFilter?(viewModel.predicate)
                            dismiss()
                        }
                        .disabled(viewModel.predicate.isDefault)
                        .accessibilityIdentifier("Search-Apply")
                    }
                }
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(item: $viewerContext) { context in
            ViewerContainer(viewModel: AppContainer.shared.makeViewerViewModel(context: context))
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                historySection
                filterSection
                resultCount
                resultGrid
            }
            .padding(.horizontal, DSSpacing.screenPadding)
            .padding(.bottom, 32)
        }
        .background(Color(ds: DSColor.bgPrimary))
    }

    // MARK: - 最近筛选历史

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最近筛选")
                        .font(.headline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Spacer()
                    Button("清除") { viewModel.clearHistory() }
                        .font(.caption)
                        .accessibilityIdentifier("Search-History-Clear")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.history.indices, id: \.self) { index in
                            let item = viewModel.history[index]
                            HStack(spacing: 4) {
                                Button {
                                    viewModel.applyHistory(item)
                                } label: {
                                    Text(summary(of: item))
                                        .font(.caption)
                                        .padding(.vertical, 6)
                                        .foregroundColor(Color(ds: DSColor.textPrimary))
                                }
                                Button {
                                    viewModel.removeHistory(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(Color(ds: DSColor.textSecondary))
                                }
                                .accessibilityLabel("删除筛选历史：\(summary(of: item))")
                            }
                            .padding(.horizontal, 10)
                            .background(Color(ds: DSColor.bgSecondary))
                            .cornerRadius(14)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func summary(of predicate: SearchPredicate) -> String {
        var parts: [String] = []
        if let year = predicate.year { parts.append("\(year)年") }
        if let month = predicate.month { parts.append("\(month)月") }
        if let day = predicate.day { parts.append("\(day)日") }
        if !predicate.media.isEmpty {
            parts.append(predicate.media.map(\.displayName).sorted().joined(separator: "/"))
        }
        if !predicate.status.isEmpty {
            parts.append(predicate.status.map(\.displayName).sorted().joined(separator: "/"))
        }
        return parts.isEmpty ? "全部照片" : parts.joined(separator: " · ")
    }

    // MARK: - 筛选区

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日期")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            HStack(spacing: 10) {
                drillMenu(title: viewModel.predicate.year.map(String.init) ?? "不限年份",
                          options: viewModel.availableYears.map { String($0) },
                          onSelect: { viewModel.setYear(Int($0)) })
                if let year = viewModel.predicate.year {
                    drillMenu(title: viewModel.predicate.month.map { Self.monthNames[$0] } ?? "不限月份",
                              options: viewModel.availableMonths(inYear: year).map { Self.monthNames[$0] },
                              onSelect: { viewModel.setMonth(Self.monthNumber(from: $0)) })
                }
                if let year = viewModel.predicate.year, let month = viewModel.predicate.month {
                    drillMenu(title: viewModel.predicate.day.map { "\($0) 日" } ?? "不限日期",
                              options: viewModel.availableDays(inYear: year, month: month).map { "\($0) 日" },
                              onSelect: { text in
                                  // "12 日" → 12（取前导数字）
                                  if let day = Int(text.prefix(while: \.isNumber)) {
                                      viewModel.setDay(day)
                                  }
                              })
                }
            }

            Text("媒体类型")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            chipRow(items: SearchPredicate.MediaFilter.allCases,
                    isSelected: { viewModel.predicate.media.contains($0) },
                    label: { $0.displayName },
                    toggle: { viewModel.toggleMedia($0) })

            Text("状态")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            chipRow(items: SearchPredicate.StatusFilter.allCases,
                    isSelected: { viewModel.predicate.status.contains($0) },
                    label: { $0.displayName },
                    toggle: { viewModel.toggleStatus($0) })
        }
        .padding(.top, 8)
    }

    private func drillMenu(title: String, options: [String], onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { onSelect(option) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(ds: DSColor.bgSecondary))
            .foregroundColor(Color(ds: DSColor.textPrimary))
            .cornerRadius(DSSpacing.buttonCornerRadius)
        }
        .accessibilityLabel("日期筛选，当前 \(title)")
    }

    private func chipRow<T: Hashable>(items: [T],
                                      isSelected: @escaping (T) -> Bool,
                                      label: @escaping (T) -> String,
                                      toggle: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button {
                        toggle(item)
                    } label: {
                        Text(label(item))
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected(item)
                                        ? Color(ds: DSColor.tint)
                                        : Color(ds: DSColor.bgSecondary))
                            .foregroundColor(isSelected(item) ? .white : Color(ds: DSColor.textPrimary))
                            .cornerRadius(16)
                    }
                    .accessibilityLabel("\(label(item))\(isSelected(item) ? "，已选中" : "")")
                }
            }
        }
    }

    // MARK: - 结果

    private var resultCount: some View {
        Text("共 \(viewModel.results.count) 项")
            .font(.subheadline)
            .foregroundColor(Color(ds: DSColor.textSecondary))
            .accessibilityLabel("筛选结果 \(viewModel.results.count) 项")
    }

    @ViewBuilder
    private var resultGrid: some View {
        if viewModel.results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Text("没有符合条件的照片")
                    .font(.headline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text("试试减少筛选条件，或清除全部筛选")
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                Button("清除筛选") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("Search-ClearFilters")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            // docs/09 D15：去掉 200 上限，全量懒加载展示；可点开查看器
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: DSSpacing.gridSpacing)],
                      spacing: DSSpacing.gridSpacing) {
                ForEach(viewModel.results) { item in
                    Button {
                        viewerContext = ViewerContext(items: viewModel.results,
                                                      startItemID: item.id,
                                                      queryKey: "search")
                    } label: {
                        ResultThumb(item: item, pipeline: AppContainer.shared.imagePipeline)
                    }
                    .accessibilityLabel(PhotoGridCell.accessibilityLabel(for: item))
                }
            }
        }
    }

    private static func monthNumber(from name: String) -> Int? {
        Self.monthNames.firstIndex(of: name).flatMap { $0 > 0 ? $0 : nil }
    }
}

private struct ResultThumb: View {
    let item: PhotoItem
    let pipeline: ImagePipelineProtocol
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(ds: DSColor.bgSecondary))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .cornerRadius(DSSpacing.gridCornerRadius)
        .task {
            image = await pipeline.thumbnail(for: item.id,
                                             size: CGSize(width: 100, height: 100),
                                             scale: UIScreen.main.scale)
        }
    }
}
