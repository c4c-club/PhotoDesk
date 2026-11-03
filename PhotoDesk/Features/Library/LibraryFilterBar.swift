// MARK: - 职责说明：主库筛选栏（docs/09 D10）——活动筛选 chips（可单删）+「筛选」入口 +
// 清除 + 结果计数。位于 ScopePicker 与网格之间；无活动筛选时仅显示计数。

import SwiftUI

struct LibraryFilterBar: View {
    @ObservedObject var viewModel: LibraryViewModel
    var onOpenSheet: () -> Void

    private var filter: SearchPredicate { viewModel.query.filter }
    private var isActive: Bool { filter.isActive }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button(action: onOpenSheet) {
                    Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(Color(ds: DSColor.tint))
                }
                .accessibilityIdentifier("Library-Filter")
                .accessibilityLabel("筛选")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let year = filter.year {
                            chip(text: "\(String(year)) 年") { draft { $0.year = nil; $0.month = nil; $0.day = nil } }
                            if let month = filter.month {
                                chip(text: "\(month) 月") { draft { $0.month = nil; $0.day = nil } }
                            }
                            if let day = filter.day {
                                chip(text: "\(day) 日") { draft { $0.day = nil } }
                            }
                        }
                        ForEach(Array(filter.media).sorted { $0.rawValue < $1.rawValue }) { media in
                            chip(text: media.displayName) { draft { $0.media.remove(media) } }
                        }
                        ForEach(Array(filter.status).sorted { $0.rawValue < $1.rawValue }) { status in
                            chip(text: status.displayName) { draft { $0.status.remove(status) } }
                        }
                        if filter.location != .any {
                            chip(text: locationChipText) { draft { $0.location = .any } }
                        }
                    }
                }

                if isActive {
                    Button("清除") {
                        viewModel.clearFilter()
                    }
                    .font(.subheadline)
                    .foregroundColor(Color(ds: DSColor.tint))
                    .accessibilityIdentifier("Library-Filter-Clear")
                }
            }
            .padding(.horizontal, DSSpacing.screenPadding)
            .padding(.vertical, 6)

            HStack {
                Spacer()
                Text("共 \(viewModel.filteredItems.count) 项")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
                    .accessibilityIdentifier("Library-Result-Count")
                    .accessibilityLabel("筛选结果 \(viewModel.filteredItems.count) 项")
                    .padding(.horizontal, DSSpacing.screenPadding)
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .accessibilityIdentifier("Library-FilterBar")   // 稳定性 UI 测试锚点（S06 断言其不存在）
    }

    private var locationChipText: String {
        switch filter.location {
        case .withLocation:     return "有位置"
        case .withoutLocation:  return "无位置"
        case .near(let region): return String(format: "%.1f°,%.1f° 附近", region.center.latitude, region.center.longitude)
        case .any:              return ""
        }
    }

    private func chip(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(ds: DSColor.tint).opacity(0.15))
        .foregroundColor(Color(ds: DSColor.tint))
        .cornerRadius(12)
    }

    /// 单删 chip：复制当前筛选 → 移除该维度 → 应用
    private func draft(_ change: (inout SearchPredicate) -> Void) {
        var next = filter
        change(&next)
        viewModel.setFilter(next)
    }
}
