// MARK: - 职责说明：行带平铺几何与序列（M19 T02，docs/42 §3.1）——
// 行带=(section,row) 是轨迹滑选的唯一选择单元；本类型只收 Double/Int（红线 2），
// App 侧由 GridHitTester 用真实 layoutAttributes 缓存构造（禁 DSSpacing 推算，docs/42 不变量 8）。
// bandIndex：粘性头下缘以下才可命中（有效 y = max(y, clipTop)）、全部行被遮挡 → nil、
// 段间空隙在 rowBandSnapTolerance 内吸附（平局归下一段首行）、空隙中部 → nil、布局外钳首/末带；
// bandSequence：双端含、反向镜像、越界钳制，只分配区间长度数组（不分配整库数组）。

import Foundation

/// 行带段的布局参数（App 由真实 layoutAttributes 换算喂入；非法段由 RowBandMap 跳过）。
public struct RowBandSection: Hashable, Sendable {
    public let section: Int
    public let itemCount: Int
    public let columns: Int
    /// 行带行距（次行 firstRowMinY − 首行 firstRowMinY，含行间距），行带跨度按连续 pitch 平铺
    public let rowHeight: Double
    public let firstRowMinY: Double
    public let headerHeight: Double

    public init(section: Int, itemCount: Int, columns: Int, rowHeight: Double,
                firstRowMinY: Double, headerHeight: Double) {
        self.section = section
        self.itemCount = itemCount
        self.columns = columns
        self.rowHeight = rowHeight
        self.firstRowMinY = firstRowMinY
        self.headerHeight = headerHeight
    }

    var isValid: Bool { columns > 0 && rowHeight.isFinite && rowHeight > 0 && itemCount > 0 }
    var rowCount: Int { (itemCount + columns - 1) / columns }
}

/// 一个行带：段内第 row 行的全部 item 下标（列升序）。
public struct RowBand: Hashable, Sendable {
    public let section: Int
    public let row: Int
    public let items: [Int]
}

/// 行带平铺表：section 升序 → row 升序（跳过非法段，平铺下标连续）。
public struct RowBandMap: Sendable {
    private struct FlatSection {
        let section: RowBandSection
        let base: Int
        let rowCount: Int
        let lastMaxY: Double
    }

    private let flat: [FlatSection]
    /// 平铺行带总数 = Σ ceil(itemCount/columns)（仅合法段）
    public let count: Int

    public init(sections: [RowBandSection]) {
        var built: [FlatSection] = []
        built.reserveCapacity(sections.count)
        var base = 0
        for entry in sections where entry.isValid {
            let rows = entry.rowCount
            built.append(FlatSection(section: entry, base: base, rowCount: rows,
                                     lastMaxY: entry.firstRowMinY + Double(rows) * entry.rowHeight))
            base += rows
        }
        flat = built
        count = base
    }

    /// 取平铺下标对应的行带（越界为编程错误，precondition）。
    public func band(at index: Int) -> RowBand {
        precondition(index >= 0 && index < count, "band index \(index) out of range [0, \(count))")
        let fs = flatSection(at: index)
        let row = index - fs.base
        let entry = fs.section
        let lower = row * entry.columns
        let upper = min(lower + entry.columns, entry.itemCount)
        return RowBand(section: entry.section, row: row, items: Array(lower..<upper))
    }

    /// 内容 y → 行带平铺下标；无可命中行带（全遮挡/空表/空隙中部）返回 nil。
    public func bandIndex(atContentY y: Double, clipTop: Double) -> Int? {
        guard count > 0, let last = flat.last, last.lastMaxY > clipTop else { return nil }
        let effectiveY = max(y, clipTop)
        guard effectiveY.isFinite else { return nil }
        let idx = sectionIndexForLookup(effectiveY)
        let fs = flat[idx]
        let entry = fs.section
        if effectiveY >= entry.firstRowMinY {
            let raw = ((effectiveY - entry.firstRowMinY) / entry.rowHeight).rounded(.down)
            let clamped = min(max(raw, 0), Double(fs.rowCount - 1))
            return fs.base + Int(clamped)
        }
        // 有效 y 落在 fs 首行上方：布局顶之外 → 钳首行带；段间空隙 → 容差吸附（平局归下一段首行）
        guard idx > 0 else { return fs.base }
        let prev = flat[idx - 1]
        let distUp = effectiveY - prev.lastMaxY
        let distDown = entry.firstRowMinY - effectiveY
        if distDown <= SlideSelectConfig.rowBandSnapTolerance { return fs.base }
        if distUp <= SlideSelectConfig.rowBandSnapTolerance { return prev.base + prev.rowCount - 1 }
        return nil
    }

    /// 行带下标序列：双端含；from > to 反向镜像；越界钳制到 [0, count)；空表返回 []。
    public func bandSequence(from: Int, to: Int) -> [Int] {
        guard count > 0 else { return [] }
        let lo = min(max(from, 0), count - 1)
        let hi = min(max(to, 0), count - 1)
        if lo <= hi { return Array(lo...hi) }
        return Array((hi...lo).reversed())
    }

    /// 行带下标序列 → 有序 item 展开（行主序：行序 + 行内列序；重复行带去重保首现；
    /// 越界下标防御性忽略）。产纯数值 RowBandItem（docs/42 §10.1），scope 过滤在 trail consume 层。
    public func items(forBandIndices bandIndices: [Int]) -> [RowBandItem] {
        guard count > 0, !bandIndices.isEmpty else { return [] }
        var out: [RowBandItem] = []
        out.reserveCapacity(bandIndices.count)
        var seenBands = Set<Int>(minimumCapacity: bandIndices.count)
        for bandIndex in bandIndices {
            guard bandIndex >= 0, bandIndex < count, seenBands.insert(bandIndex).inserted else { continue }
            let b = band(at: bandIndex)
            for item in b.items {
                out.append(RowBandItem(section: b.section, item: item))
            }
        }
        return out
    }

    /// 二分：第一个 lastMaxY ≥ effectiveY 的段；全部段 lastMaxY < effectiveY 时返回末段（越界钳末带）。
    private func sectionIndexForLookup(_ effectiveY: Double) -> Int {
        var lo = 0
        var hi = flat.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if flat[mid].lastMaxY >= effectiveY { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    /// 二分：包含平铺下标 index 的段（index < count 由调用方保证）。
    private func flatSection(at index: Int) -> FlatSection {
        var lo = 0
        var hi = flat.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if index < flat[mid].base + flat[mid].rowCount { hi = mid } else { lo = mid + 1 }
        }
        return flat[lo]
    }
}
