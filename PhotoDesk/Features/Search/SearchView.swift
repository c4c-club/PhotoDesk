// MARK: - 职责说明：搜索/筛选页（docs/04 §2 / docs/05 M5 任务 5.1）——
// 日期三级下钻（年→月→日菜单）+ 媒体类型多选 chips + 状态筛选 + 结果计数与缩略图网格。
// 从照片库右上角放大镜进入（sheet）；谓词匹配全部在 SearchViewModel（PhotoFilter 纯函数）。

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss

    init(items: [PhotoItem]) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(items: items))
    }

    private static let monthNames = ["", "1月", "2月", "3月", "4月", "5月", "6月",
                                     "7月", "8月", "9月", "10月", "11月", "12月"]

    var body: some View {
        NavigationView {
            content
                .navigationTitle("搜索")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("完成") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("重置") { viewModel.reset() }
                            .disabled(viewModel.predicate.isDefault)
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterSection
                resultCount
                resultGrid
            }
            .padding(.horizontal, DSSpacing.screenPadding)
            .padding(.bottom, 32)
        }
        .background(Color(ds: DSColor.bgPrimary))
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

    private var resultGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: DSSpacing.gridSpacing)],
                  spacing: DSSpacing.gridSpacing) {
            ForEach(viewModel.results.prefix(200)) { item in
                ResultThumb(item: item, pipeline: AppContainer.shared.imagePipeline)
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
