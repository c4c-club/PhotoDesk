// MARK: - 职责说明：月份选择面板（docs/13 §3.6 S09）——按年份分组 + 3 列月份卡片（月份名 + N 张），
// 点击跳转；卡片右上角「全选」；顶部「回到顶部」。分组/月份解析全部来自 PhotoDeskCore.MonthNavigator
//（红线 2：App 侧只做展示适配）。AX 标识：MonthJump-Sheet / MonthJump-Month-<id> / MonthJump-SelectAll-<id>。

import SwiftUI
import PhotoDeskCore

struct MonthJumpSheet: View {
    private struct Row: Identifiable {
        let id: String          // 月份 id："2024-05"
        let sectionIndex: Int   // 网格 section 下标（跳转目标）
        let title: String
        let count: Int
    }

    private struct YearBlock: Identifiable {
        let year: Int
        let rows: [Row]
        var id: Int { year }
    }

    private let blocks: [YearBlock]
    private let onSelect: (Int) -> Void
    private let onSelectAll: (Int) -> Void
    private let onScrollToTop: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - sections: 当前网格 sections（含空月；unknown 分组不出现在面板）
    ///   - onSelect: 点击月份卡片 → section 下标
    ///   - onSelectAll: 卡片「全选」→ section 下标
    init(sections: [MonthSection],
         onSelect: @escaping (Int) -> Void,
         onSelectAll: @escaping (Int) -> Void,
         onScrollToTop: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onSelectAll = onSelectAll
        self.onScrollToTop = onScrollToTop

        // id → 首个 section 下标（重复 id 取第一个；空月也会出现以便置灰展示）
        var indexByID: [String: Int] = [:]
        for (index, section) in sections.enumerated() where indexByID[section.id] == nil {
            indexByID[section.id] = index
        }
        // 核心包解析（跳过 unknown/畸形 id），再映射回 section 下标
        let infos = sections.map { MonthSectionInfo(id: $0.id, title: $0.title, count: $0.count) }
        let descriptors = MonthNavigator.descriptors(from: infos)
        var order: [Int] = []
        var buckets: [Int: [Row]] = [:]
        for descriptor in descriptors {
            guard let sectionIndex = indexByID[descriptor.id] else { continue }
            let row = Row(id: descriptor.id,
                          sectionIndex: sectionIndex,
                          title: descriptor.title,
                          count: descriptor.count)
            if buckets[descriptor.year] == nil {
                order.append(descriptor.year)
            }
            buckets[descriptor.year, default: []].append(row)
        }
        blocks = order.map { YearBlock(year: $0, rows: buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                content
                    .padding(DSSpacing.screenPadding)
            }
            .navigationTitle("按月份跳转")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .accessibilityIdentifier("MonthJump-Sheet")
    }

    // 拆小表达式（SwiftUI 复杂 body 会触发类型检查超时）

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            backToTopButton
            ForEach(blocks) { block in
                yearSection(block)
            }
        }
    }

    private var backToTopButton: some View {
        Button {
            onScrollToTop()
            dismiss()
        } label: {
            backToTopLabel
        }
        .accessibilityIdentifier("MonthJump-ScrollTop")
    }

    private var backToTopLabel: some View {
        Label("回到顶部", systemImage: "arrow.up.to.line")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(ds: DSColor.bgSecondary))
            .foregroundColor(Color(ds: DSColor.tint))
            .cornerRadius(DSSpacing.buttonCornerRadius)
    }

    private func yearSection(_ block: YearBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(String(block.year)) 年")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                ForEach(block.rows) { row in
                    monthCard(row)
                }
            }
        }
    }

    private static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    // MARK: - 月份卡片

    private func monthCard(_ row: Row) -> some View {
        ZStack(alignment: .topTrailing) {
            jumpButton(row)
            selectAllButton(row)
        }
    }

    private func jumpButton(_ row: Row) -> some View {
        Button {
            onSelect(row.sectionIndex)
            dismiss()
        } label: {
            cardLabel(row)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("MonthJump-Month-\(row.id)")
        .accessibilityLabel("\(row.title)，\(row.count) 张")
        .disabled(row.count == 0)
    }

    private func cardLabel(_ row: Row) -> some View {
        VStack(spacing: 2) {
            Text(row.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Text("\(row.count) 张")
                .font(.caption2)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(ds: DSColor.bgSecondary))
        .cornerRadius(8)
        .opacity(row.count == 0 ? 0.4 : 1)
    }

    private func selectAllButton(_ row: Row) -> some View {
        Button {
            onSelectAll(row.sectionIndex)
            dismiss()
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(ds: DSColor.tint))
                .padding(4)
        }
        .accessibilityIdentifier("MonthJump-SelectAll-\(row.id)")
        .accessibilityLabel("全选\(row.title)")
        .disabled(row.count == 0)
    }
}
