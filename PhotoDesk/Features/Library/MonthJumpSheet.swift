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
            // List（UIKit 宿主）承载：XCUITest 对纯 SwiftUI ScrollView 内 Button 的合成点击不可靠
            List {
                Section {
                    backToTopRow
                }
                ForEach(blocks) { block in
                    Section(header: Text("\(String(block.year)) 年")
                        .font(.headline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))) {
                        ForEach(block.rows) { row in
                            monthRow(row)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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

    // MARK: - 行（docs/13 S09；规格微调：月份卡片以列表行呈现——CI 实测 List 行点击可靠）

    private var backToTopRow: some View {
        Button {
            onScrollToTop()
            dismiss()
        } label: {
            Label("回到顶部", systemImage: "arrow.up.to.line")
                .foregroundColor(Color(ds: DSColor.tint))
        }
        .accessibilityIdentifier("MonthJump-ScrollTop")
    }

    private func monthRow(_ row: Row) -> some View {
        Button {
            onSelect(row.sectionIndex)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Text("\(row.count) 张")
                        .font(.caption2)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                Spacer()
                if row.count > 0 {
                    Button {
                        onSelectAll(row.sectionIndex)
                        dismiss()
                    } label: {
                        Text("全选")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(ds: DSColor.tint))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(ds: DSColor.tint).opacity(0.15))
                            .cornerRadius(10)
                    }
                    .accessibilityIdentifier("MonthJump-SelectAll-\(row.id)")
                    .accessibilityLabel("全选\(row.title)")
                }
            }
            .opacity(row.count == 0 ? 0.4 : 1)
        }
        .accessibilityIdentifier("MonthJump-Month-\(row.id)")
        .accessibilityLabel("\(row.title)，\(row.count) 张")
        .disabled(row.count == 0)
    }
}
