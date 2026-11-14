// MARK: - 职责说明：框选命中测试器（M17 T04，docs/32 §2.4 1–8 步）——命中一律读真实
// layoutAttributes，废除网格参数推算（docs/31 G7/G8/G9/H1/H3 根治）：段范围缓存自
// item(0)/item(count−1) attributes（supplementary 的钉住态 frame 不参与 → 粘性头污染免疫）；
// 列数由段内首行 attributes 探测；真实行高 = 次行.minY − 首行.minY；二分找候选段，只枚举
// 相交行、每行 ≤ columns 次 item attributes 查询按 frame.intersects 判定（docs/31 A15 每段
// 全扫根治）；矩形上边钳到视口顶 + 粘性头高，被钉住头完全遮住与已滚出屏的 cell 不命中
// （docs/31 G11 / docs/32 §2.4 第 6 步）。缓存随 snapshot apply / 列数变化 / 布局 pass 由 VC
// 调 invalidateGeometry() 失效。DEBUG lastQueryCount 供测试断言缓存已热帧 ≤ 60 次查询。

import UIKit

@MainActor
final class GridHitTester {
    /// 段几何缓存（全部来自 item attributes；item frame 与 contentOffset 无关，缓存跨滚动有效）
    private struct SectionGeometry {
        let section: Int
        let itemCount: Int
        let firstRowMinY: Double
        let lastMaxY: Double
        let rowHeight: Double
        let headerNaturalMinY: Double
    }

    private weak var collectionView: UICollectionView?
    private var sections: [SectionGeometry] = []
    private var derivedColumns = 0

    #if DEBUG
    /// 最近一次 hitTest 的 layoutAttributesForItem 查询次数（含缓存构建帧；断言 ≤ 60 须在缓存已热帧）。
    private(set) var lastQueryCount = 0
    #endif

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
    }

    /// snapshot apply / 列数变化 / 布局变化后由 VC 调用；下一次 hitTest 重建缓存。
    func invalidateGeometry() {
        sections = []
        derivedColumns = 0
    }

    /// 矩形（内容坐标）→ 命中 IndexPath 集合。零尺寸矩形扩展 1pt 由调用方负责（起手 cell 命中）。
    func hitTest(rectInContent rawRect: CGRect) -> Set<IndexPath> {
        #if DEBUG
        lastQueryCount = 0
        #endif
        guard let collectionView,
              rawRect.origin.x.isFinite, rawRect.origin.y.isFinite,
              rawRect.width.isFinite, rawRect.height.isFinite else { return [] }
        ensureCache()
        guard !sections.isEmpty, derivedColumns >= 1 else { return [] }

        // G11 / docs/32 §2.4 第 6 步：视口顶所在段的粘性头（pinToVisibleBounds）正钉在视口顶，
        // 遮挡 [视口顶, 视口顶+头高]；矩形上边钳到头底边，被完全遮住与已滚出屏的 cell 不命中。
        // 视口顶越出全部段（顶端回弹）时无钉住头 → 不钳制。
        let viewportTop = Double(collectionView.contentOffset.y)
            + Double(collectionView.adjustedContentInset.top)
        var rect = rawRect
        if sectionIndex(containingContentY: viewportTop) != nil {
            let stickyBottom = viewportTop + Double(DSSpacing.monthHeaderHeight)
            if rect.maxY <= stickyBottom { return [] }
            if rect.minY < stickyBottom {
                rect = CGRect(x: rect.minX, y: stickyBottom,
                              width: rect.width, height: rect.maxY - stickyBottom)
            }
        }

        let layout = collectionView.collectionViewLayout
        let minY = Double(rect.minY)
        let maxY = Double(rect.maxY)
        var result = Set<IndexPath>()
        // 候选段：lastMaxY 升序二分第一个与矩形相交的段，线性推进到段顶越过矩形底边即停
        var index = firstSectionIndex(withLastMaxYAtLeast: minY)
        while index < sections.count {
            let geo = sections[index]
            if geo.headerNaturalMinY > maxY { break }
            guard geo.rowHeight.isFinite, geo.rowHeight > 0 else { index += 1; continue }
            // 行候选：矩形 y 范围换算行号，首行向前回退一行防浮点误差；真实行高枚举
            let firstRow = max(0, Int(((minY - geo.firstRowMinY) / geo.rowHeight).rounded(.down)) - 1)
            let lastRow = Int(((maxY - geo.firstRowMinY) / geo.rowHeight).rounded(.up))
            var row = firstRow
            while row <= lastRow {
                let rowTop = geo.firstRowMinY + Double(row) * geo.rowHeight
                if rowTop > maxY { break }
                guard rowTop + geo.rowHeight >= minY else {
                    row += 1
                    continue
                }
                // 列命中：每行最多 columns 次 layoutAttributesForItem，真实 frame 相交判定
                for column in 0..<derivedColumns {
                    let item = row * derivedColumns + column
                    guard item < geo.itemCount else { break }
                    if let attrs = query(layout, item: item, section: geo.section),
                       attrs.frame.intersects(rect) {
                        result.insert(IndexPath(item: item, section: geo.section))
                    }
                }
                row += 1
            }
            index += 1
        }
        return result
    }

    // MARK: - 缓存

    private func ensureCache() {
        guard let collectionView else { return }
        let sectionCount = collectionView.numberOfSections
        guard sectionCount > 0 else { return }
        if sections.count == sectionCount, derivedColumns >= 1 { return }
        let layout = collectionView.collectionViewLayout
        if derivedColumns < 1 {
            derivedColumns = probeColumns(layout: layout)
        }
        var built: [SectionGeometry] = []
        built.reserveCapacity(sectionCount)
        for section in 0..<sectionCount {
            let itemCount = collectionView.numberOfItems(inSection: section)
            guard itemCount > 0, let first = query(layout, item: 0, section: section) else { continue }
            // 真实行高：次行首项 minY − 首行 minY（docs/32 §2.4 第 4 步）；单行段取首行高度
            var rowHeight = Double(first.frame.height)
            if itemCount > derivedColumns,
               let secondRow = query(layout, item: derivedColumns, section: section) {
                let derived = Double(secondRow.frame.minY) - Double(first.frame.minY)
                if derived.isFinite, derived > 0.5 { rowHeight = derived }
            }
            let last = itemCount > 1 ? (query(layout, item: itemCount - 1, section: section) ?? first) : first
            built.append(SectionGeometry(section: section,
                                         itemCount: itemCount,
                                         firstRowMinY: Double(first.frame.minY),
                                         lastMaxY: Double(last.frame.maxY),
                                         rowHeight: rowHeight,
                                         headerNaturalMinY: Double(first.frame.minY) - Double(DSSpacing.monthHeaderHeight)))
        }
        sections = built
    }

    /// 列数探测：取第一个 ≥2 item 的段，数首行 minY 相同的连续 item（行优先布局，
    /// 同行同 minY）。探测上限 32（本 App 列数 2..5）；全库单行段的退化场景回退 1。
    private func probeColumns(layout: UICollectionViewLayout) -> Int {
        guard let collectionView else { return 1 }
        for section in 0..<collectionView.numberOfSections {
            let itemCount = collectionView.numberOfItems(inSection: section)
            guard itemCount >= 2, let first = query(layout, item: 0, section: section) else { continue }
            let baseY = first.frame.minY
            var column = 1
            while column < min(itemCount, 32),
                  let attrs = query(layout, item: column, section: section),
                  abs(attrs.frame.minY - baseY) < 0.5 {
                column += 1
            }
            if column >= 2 { return column }
        }
        return 1
    }

    #if DEBUG
    private func query(_ layout: UICollectionViewLayout, item: Int, section: Int) -> UICollectionViewLayoutAttributes? {
        lastQueryCount += 1
        return layout.layoutAttributesForItem(at: IndexPath(item: item, section: section))
    }
    #else
    private func query(_ layout: UICollectionViewLayout, item: Int, section: Int) -> UICollectionViewLayoutAttributes? {
        layout.layoutAttributesForItem(at: IndexPath(item: item, section: section))
    }
    #endif

    // MARK: - 二分

    /// 视口顶所在段：最后一个 headerNaturalMinY ≤ y 的缓存段（其粘性头正被钉住）；
    /// y 小于首段顶（顶端回弹）返回 nil。headerNaturalMinY 随段序单调不减。
    private func sectionIndex(containingContentY y: Double) -> Int? {
        var low = 0
        var high = sections.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if sections[mid].headerNaturalMinY <= y {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// 二分第一个 lastMaxY ≥ y 的缓存段（lastMaxY 随段序单调不减）；无则返回数组长度。
    private func firstSectionIndex(withLastMaxYAtLeast y: Double) -> Int {
        var low = 0
        var high = sections.count
        while low < high {
            let mid = (low + high) / 2
            if sections[mid].lastMaxY < y {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
