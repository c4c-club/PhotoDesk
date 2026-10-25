// MARK: - 职责说明：存储统计页（docs/05 M5 任务 5.7 / docs/04 §2）——
// 总占用 + 按类型占比（自绘环形 Shape）+ 按年份分布（自绘柱状 Path）。
// 禁用 Swift Charts（iOS 16+，AGENTS.md §2）——全部 Path/Shape 自绘；
// VoiceOver：图表带数值 accessibilityLabel（docs/04 §6）。
// 数据：全量 items + PHAssetResource 字节数（KVC 失败回退 0，不中断统计）。

import SwiftUI
import Photos

struct StorageStatsView: View {
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

    @State private var slices: [TypeSlice] = []
    @State private var bars: [YearBar] = []
    @State private var totalBytes: Int64 = 0
    @State private var itemCount = 0
    @State private var isLoading = true

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("统计中…")
                        .font(.caption)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                statsList
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("存储统计")
        .navigationBarTitleDisplayMode(.inline)
        .task { await compute() }
    }

    private var statsList: some View {
        List {
            Section("总占用") {
                HStack {
                    Text("照片 + 视频")
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Spacer()
                    Text(Self.byteFormatter.string(fromByteCount: totalBytes))
                        .font(.headline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                }
                .accessibilityElement(children: .combine)
                Text("\(itemCount) 个项目")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
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
        }
        .listStyle(.insetGrouped)
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
        let total = max(1, totalBytes)
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
                Text(Self.byteFormatter.string(fromByteCount: totalBytes))
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

    // MARK: - 自绘柱状（Path 矩形；几何计算拆分为小函数避免表达式类型检查超时）

    private var barChartMaxBytes: Int64 {
        max(1, bars.map(\.bytes).max() ?? 1)
    }

    /// 单根柱的矩形（heights 基于 proxy 尺寸预计算传入）
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
                // 基线
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

                    // 年份标签（每根柱下方，两位年）
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

    // MARK: - 数据计算（后台 utility；fileSize KVC 失败按 0）

    private func compute() async {
        let repository = AppContainer.shared.assetRepository
        let total = await repository.prepare(scope: .all)
        var items: [PhotoItem] = []
        var cursor = 0
        while cursor < total {
            let batch = await repository.fetch(scope: .all, offset: cursor, limit: AssetRepository.batchSize)
            guard !batch.isEmpty else { break }
            items.append(contentsOf: batch)
            cursor += batch.count
        }

        var photoBytes: Int64 = 0
        var videoBytes: Int64 = 0
        var otherBytes: Int64 = 0
        var byYear: [Int: Int64] = [:]
        let ids = items.map(\.id)
        let sizes = await withTaskGroup(of: (String, Int64).self,
                                        returning: [String: Int64].self) { group in
            for id in ids {
                group.addTask(priority: .utility) {
                    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                    return (id, assets.firstObject?.fileSizeBytes ?? 0)
                }
            }
            var result: [String: Int64] = [:]
            for await (id, size) in group { result[id] = size }
            return result
        }
        let calendar = Calendar.current
        for item in items {
            let size = sizes[item.id] ?? 0
            switch item.mediaType {
            case .image: photoBytes += size
            case .video: videoBytes += size
            case .unknown: otherBytes += size
            }
            if let date = item.creationDate {
                byYear[calendar.component(.year, from: date), default: 0] += size
            }
        }

        totalBytes = photoBytes + videoBytes + otherBytes
        itemCount = items.count
        slices = [
            TypeSlice(name: "照片", bytes: photoBytes, color: DSColor.tint),
            TypeSlice(name: "视频", bytes: videoBytes, color: DSColor.accentAlbum),
        ]
        if otherBytes > 0 {
            slices.append(TypeSlice(name: "其他", bytes: otherBytes, color: DSColor.textSecondary))
        }
        bars = byYear.keys.sorted(by: >).map { YearBar(year: $0, bytes: byYear[$0] ?? 0) }
        isLoading = false
    }

    private func percent(of bytes: Int64) -> Int {
        guard totalBytes > 0 else { return 0 }
        return Int(Double(bytes) / Double(totalBytes) * 100)
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
