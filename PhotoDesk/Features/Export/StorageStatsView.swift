// MARK: - 职责说明：存储统计页（docs/05 M5 任务 5.7；docs/09 D07 重做）——
// 统计中：环形进度 + 已统计 N/M + 取消（不再永久转圈）；完成：总占用 + 按类型环 + 按年份柱；
// 90s 软超时显示部分结果 + 「部分 iCloud 资源大小未知」脚注 + 继续统计；未知大小计数脚注；
// .refreshable 强制重算。图表全部 Path/Shape 自绘（禁用 Swift Charts，iOS 16+，AGENTS §2）；
// VoiceOver：图表带数值 accessibilityLabel。数据经 StorageStatsViewModel（批量取字节 + 缓存）。

import SwiftUI
import Photos

struct StorageStatsView: View {
    @StateObject private var viewModel: StorageStatsViewModel

    struct TypeSlice: Identifiable {
        let id = UUID()
        let name: String
        let bytes: Int64
        let color: UIColor
    }

    struct YearBar: Identifiable {
        let id = UUID()
        let year: Int
        let bytes: Int64
    }

    init() {
        _viewModel = StateObject(wrappedValue: AppContainer.shared.makeStorageStatsViewModel())
    }

    @State private var slices: [TypeSlice] = []
    @State private var bars: [YearBar] = []

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .computing, .cancelled:
                progressView
            case .done(let partial):
                statsList(partial: partial)
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("存储统计")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.start()
        }
        .onChange(of: viewModel.phase) { _ in
            rebuildCharts()
        }
    }

    // MARK: - 统计中（进度环 + 取消）

    private var progressView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(ds: DSColor.bgSecondary), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(Color(ds: DSColor.tint),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progressFraction * 100))%")
                    .font(.title2)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
            }
            .frame(width: 140, height: 140)

            Text("已统计 \(viewModel.progress.done) / \(viewModel.progress.total)")
                .font(.body)
                .foregroundColor(Color(ds: DSColor.textSecondary))
                .accessibilityIdentifier("StorageStats-Progress")

            if viewModel.phase == .cancelled {
                Text("已取消")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }

            Button("取消统计") {
                viewModel.cancel()
            }
            .foregroundColor(Color(ds: DSColor.accentDelete))
            .accessibilityIdentifier("StorageStats-Cancel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressFraction: CGFloat {
        guard viewModel.progress.total > 0 else { return 0 }
        return CGFloat(viewModel.progress.done) / CGFloat(viewModel.progress.total)
    }

    // MARK: - 结果

    private func statsList(partial: Bool) -> some View {
        List {
            Section("总占用") {
                HStack {
                    Text("照片 + 视频")
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Spacer()
                    Text(Self.byteFormatter.string(fromByteCount: viewModel.summary.totalBytes))
                        .font(.headline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("StorageStats-Total")
                Text("\(viewModel.itemCount) 个项目")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))

                if partial {
                    // 软超时部分结果（docs/09 D07：绝不永久转圈）
                    VStack(alignment: .leading, spacing: 6) {
                        Text("部分 iCloud 资源大小未知（已统计 \(viewModel.partialCount)/\(viewModel.itemCount)）")
                            .font(.caption)
                            .foregroundColor(Color(ds: DSColor.accentDelete))
                        Button("继续统计") {
                            Task { await viewModel.resume() }
                        }
                        .font(.subheadline)
                    }
                } else if viewModel.summary.unknownCount > 0 {
                    Text("\(viewModel.summary.unknownCount) 项大小未知（iCloud 原件未下载或读取失败）")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
            }

            if !slices.isEmpty {
                Section("按类型") {
                    donutChart
                        .frame(height: 160)
                        .listRowInsets(EdgeInsets())
                    ForEach(slices) { slice in
                        legendRow(slice)
                    }
                }
            }

            if !bars.isEmpty {
                Section("按年份") {
                    barChart
                        .frame(height: 150)
                        .padding(.vertical, 8)
                    ForEach(bars) { bar in
                        HStack {
                            Text("\(String(bar.year)) 年")
                                .foregroundColor(Color(ds: DSColor.textPrimary))
                            Spacer()
                            Text(Self.byteFormatter.string(fromByteCount: bar.bytes))
                                .foregroundColor(Color(ds: DSColor.textSecondary))
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(String(bar.year)) 年 \(Self.byteFormatter.string(fromByteCount: bar.bytes))")
                    }
                }
            }

            Section {
                Button("重新统计") {
                    Task { await viewModel.start(forceRefresh: true) }
                }
                .accessibilityIdentifier("StorageStats-Rerun")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // 强制重算（忽略缓存，docs/09 D07）
            await viewModel.start(forceRefresh: true)
        }
    }

    private func rebuildCharts() {
        guard case .done = viewModel.phase else { return }
        let summary = viewModel.summary
        var newSlices = [
            TypeSlice(name: "照片", bytes: summary.photoBytes, color: DSColor.tint),
            TypeSlice(name: "视频", bytes: summary.videoBytes, color: DSColor.accentAlbum),
        ]
        if summary.otherBytes > 0 {
            newSlices.append(TypeSlice(name: "其他", bytes: summary.otherBytes, color: DSColor.textSecondary))
        }
        slices = newSlices.filter { $0.bytes > 0 }
        bars = summary.byYear.keys.sorted(by: >).map { YearBar(year: $0, bytes: summary.byYear[$0] ?? 0) }
    }

    // MARK: - 自绘环形（docs/02 §2：自绘 Path/Shape 替代 Charts）

    /// 预计算角度段（start/end 弧度）——ViewBuilder 内不可累积角度，先算后画
    private struct DonutSegment: Identifiable {
        let id = UUID()
        let start: Double
        let end: Double
        let slice: TypeSlice
    }

    private var donutSegments: [DonutSegment] {
        let total = max(1, viewModel.summary.totalBytes)
        var angle = -Double.pi / 2
        return slices.map { slice in
            let sweep = Double(slice.bytes) / Double(total) * 2 * .pi
            let segment = DonutSegment(start: angle, end: angle + sweep, slice: slice)
            angle += sweep
            return segment
        }
    }

    private var donutChart: some View {
        ZStack {
            ForEach(donutSegments) { segment in
                RingSegment(startAngle: segment.start, endAngle: segment.end)
                    .stroke(Color(uiColor: segment.slice.color),
                            style: StrokeStyle(lineWidth: 26, lineCap: .butt))
            }
            VStack(spacing: 2) {
                Text(Self.byteFormatter.string(fromByteCount: viewModel.summary.totalBytes))
                    .font(.headline)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text("总计")
                    .font(.caption2)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeDonutAccessibilityLabel())
    }

    private func legendRow(_ slice: TypeSlice) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(uiImageColor: slice.color))
                .frame(width: 10, height: 10)
            Text(slice.name)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Spacer()
            Text("\(Self.byteFormatter.string(fromByteCount: slice.bytes)) · \(percent(of: slice.bytes))%")
                .font(.caption)
                .foregroundColor(Color(ds: DSColor.textSecondary))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slice.name) \(Self.byteFormatter.string(fromByteCount: slice.bytes))，占 \(percent(of: slice.bytes))%")
    }

    // MARK: - 自绘柱状（Path 矩形）

    private var barChartMaxBytes: Int64 {
        max(1, bars.map(\.bytes).max() ?? 1)
    }

    private func barRect(index: Int, count: Int, bar: YearBar,
                         size: CGSize, maxBytes: Int64) -> CGRect {
        let step = size.width / CGFloat(max(1, count))
        let barWidth = step * 0.6
        let plotHeight = size.height - 34
        let barHeight = max(2, CGFloat(bar.bytes) / CGFloat(maxBytes) * plotHeight)
        let x = CGFloat(index) * step + (step - barWidth) / 2
        return CGRect(x: x, y: size.height - 14 - barHeight, width: barWidth, height: barHeight)
    }

    private var barChart: some View {
        let maxBytes = barChartMaxBytes
        let count = bars.count
        return GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    let y = proxy.size.height - 14
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
                .stroke(Color(ds: DSColor.separator), lineWidth: 1)

                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    let rect = barRect(index: index, count: count, bar: bar,
                                       size: proxy.size, maxBytes: maxBytes)
                    Path { path in
                        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 2, height: 2))
                    }
                    .fill(Color(uiColor: DSColor.tint))

                    Text(String(format: "%02d", bar.year % 100))
                        .font(.system(size: 8))
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                        .position(x: rect.midX, y: proxy.size.height - 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(makeBarsAccessibilityLabel())
    }

    private func percent(of bytes: Int64) -> Int {
        guard viewModel.summary.totalBytes > 0 else { return 0 }
        return Int(Double(bytes) / Double(viewModel.summary.totalBytes) * 100)
    }

    private func makeDonutAccessibilityLabel() -> String {
        slices.map { "\($0.name) \(Self.byteFormatter.string(fromByteCount: $0.bytes))" }
            .joined(separator: "，")
    }

    private func makeBarsAccessibilityLabel() -> String {
        bars.map { "\($0.year) 年 \(Self.byteFormatter.string(fromByteCount: $0.bytes))" }
            .joined(separator: "，")
    }
}

/// 环形段（自绘 Shape：圆弧路径；描边样式由调用方 .stroke 施加）
private struct RingSegment: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 16
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .radians(startAngle),
                    endAngle: .radians(endAngle),
                    clockwise: false)
        return path
    }
}

private extension Color {
    /// UIColor token → SwiftUI（与 Color(ds:) 同义；环形图内联处使用）
    init(uiImageColor color: UIColor) {
        self.init(uiColor: color)
    }
}
