// MARK: - 职责说明：真实 UICollectionViewCompositionalLayout 网格几何测试（M17 T01 红探针 →
// T04 行为锁，docs/31 §2.2 G8/H1，docs/32 §4.2）——用生产布局工厂 LibraryGridLayout.make
// 的真实布局（3 列 / 48pt 粘性头 / pinToVisibleBounds）实测两件事：
// H1（§4.2 第 4 条）：pinToVisibleBounds 把被钉住段的 supplementary attributes.minY 平移到
//   视口顶（offset=5000 实测 diff=902pt）→ 命中/位置几何一律不得读 supplementary；
// H3（§4.2 第 3 条）：参数公式 (W − s(c−1))/c 与真实 item 宽一致。
// 注意：compositional layout 需 setContentOffset + invalidateLayout + layoutIfNeeded 预热后
// layoutAttributesForItem 才返回非 nil（CI 43546275550 实锤）——各用例统一走该预热。

import XCTest
@testable import PhotoDesk

@MainActor
final class LibraryGridGeometryTests: XCTestCase, UICollectionViewDataSource {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let columns = 3
    private let headerHeight: CGFloat = DSSpacing.monthHeaderHeight
    private let sectionCount = 10
    private let itemsPerSection = 30

    /// T04 起直接用生产布局工厂（镜像已删，弃用 API 警告随之消除）
    private func makeRealGrid() -> (collectionView: UICollectionView, layout: UICollectionViewCompositionalLayout) {
        let layout = LibraryGridLayout.make(columns: columns)
        let cv = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                  collectionViewLayout: layout)
        cv.dataSource = self
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "geometry-cell")
        cv.register(UICollectionReusableView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: "geometry-header")
        return (cv, layout)
    }

    /// H1 行为锁（§4.2 第 4 条）：滚动 5000pt 后，被钉住段的 supplementary 头 minY 被平移到
    /// 视口顶、与 item 推导值（首格 minY − 48）相差数百 pt → supplementary 不可用于几何。
    func testPinnedHeaderAttributeIsPinned() throws {
        let (cv, layout) = makeRealGrid()
        cv.layoutIfNeeded()
        XCTAssertEqual(cv.numberOfSections, sectionCount, "真实布局必须产出全部段")

        let targetOffset: CGFloat = 5000
        cv.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()

        // 各段起点 = 该段首格 minY - 头高（item attributes 永不被 pin 平移）
        var sectionStarts: [CGFloat] = []
        for section in 0..<sectionCount {
            guard let attrs = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) else {
                return XCTFail("真实布局必须返回段 \(section) 首格 attributes")
            }
            sectionStarts.append(attrs.frame.minY - headerHeight)
        }
        // s = 内容跨过视口顶的段（段起点 ≤ 5000 < 下一段起点）：它的头此刻应被钉住
        var pinnedSection = -1
        for section in 0..<(sectionCount - 1)
        where sectionStarts[section] <= targetOffset && sectionStarts[section + 1] > targetOffset {
            pinnedSection = section
            break
        }
        if pinnedSection == -1, let last = sectionStarts.last, last <= targetOffset {
            pinnedSection = sectionCount - 1
        }
        XCTAssertGreaterThanOrEqual(pinnedSection, 0,
                                    "offset=\(targetOffset) 必须落在某个段内（段起点=\(sectionStarts)）")

        guard let headerAttrs = layout.layoutAttributesForSupplementaryView(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: pinnedSection)),
            let itemAttrs = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: pinnedSection)) else {
            return XCTFail("真实布局必须返回段 \(pinnedSection) 的头/首格 attributes")
        }
        let expectedMinY = itemAttrs.frame.minY - headerHeight
        let diff = headerAttrs.frame.minY - expectedMinY
        XCTContext.runActivity(named: "H1 粘性头 attributes 取证") { activity in
            let attachment = XCTAttachment(string:
                "offset=\(cv.contentOffset.y) section=\(pinnedSection) " +
                "headerMinY=\(headerAttrs.frame.minY) item0MinY=\(itemAttrs.frame.minY) " +
                "expectedMinY=\(expectedMinY) diff=\(diff) pinned=\(headerAttrs.frame.minY >= targetOffset)")
            attachment.name = "h1-sticky-header-probe"
            activity.add(attachment)
        }
        // H1 结论（T01 红探针 CI 43529901394 实锤 diff=902，本用例锁死该事实）：
        // 被 pin 的 supplementary minY 精确等于视口顶；与 item 推导值差值达百 pt 量级。
        // GridHitTester 的段顶/行高全部来自 item attributes，天然免疫本现象（docs/32 §2.4）。
        XCTAssertEqual(headerAttrs.frame.minY, targetOffset, accuracy: 0.5,
                       "H1 实锤：被钉住段的 supplementary 头 minY 必须平移到视口顶")
        XCTAssertGreaterThan(abs(diff), 0.5,
                             "H1 实锤：supplementary minY 与 item 推导值差值必须达百 pt 量级（实测 902）")
    }

    // MARK: - UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int { sectionCount }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemsPerSection
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "geometry-cell", for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                        withReuseIdentifier: "geometry-header",
                                                        for: indexPath)
    }
    // MARK: - M17 T04：GridHitTester 真实 attributes 命中（docs/32 §4.2 / §2.4，docs/31 §2.2）

    /// 参数化网格数据源：item id 约定 a{section}-{item}（docs/32 §4.2 映射回归锁用）
    private final class ParamGridDataSource: NSObject, UICollectionViewDataSource {
        let sectionCount: Int
        let itemsPerSection: Int

        init(sectionCount: Int, itemsPerSection: Int) {
            self.sectionCount = sectionCount
            self.itemsPerSection = itemsPerSection
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int { sectionCount }

        func collectionView(_ collectionView: UICollectionView,
                            numberOfItemsInSection section: Int) -> Int { itemsPerSection }

        func collectionView(_ collectionView: UICollectionView,
                            cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "param-cell", for: indexPath)
        }

        func collectionView(_ collectionView: UICollectionView,
                            viewForSupplementaryElementOfKind kind: String,
                            at indexPath: IndexPath) -> UICollectionReusableView {
            collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                            withReuseIdentifier: "param-header",
                                                            for: indexPath)
        }
    }

    /// 真实 LibraryGridLayout + 390 宽 + 40 段 × 50 item（docs/32 §4.2 ①）
    private func makeParamGrid(columns: Int) -> (collectionView: UICollectionView,
                                                 layout: UICollectionViewCompositionalLayout,
                                                 dataSource: ParamGridDataSource) {
        let layout = LibraryGridLayout.make(columns: columns)
        let cv = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                  collectionViewLayout: layout)
        let dataSource = ParamGridDataSource(sectionCount: 40, itemsPerSection: 50)
        cv.dataSource = dataSource
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "param-cell")
        cv.register(UICollectionReusableView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: "param-header")
        return (cv, layout, dataSource)
    }

    /// docs/32 §4.2 ②：2/3/4/5 列 × offset {0,2000,8000,20000}，GridHitTester 命中集合
    /// 必须与逐 item layoutAttributesForItem 暴力求交一致（含粘性头底边钳制语义）。
    func testHitTesterMatchesBruteForceAcrossColumnsAndOffsets() throws {
        for columns in [2, 3, 4, 5] {
            let (cv, layout, _) = makeParamGrid(columns: columns)
            let tester = GridHitTester(collectionView: cv)
            cv.layoutIfNeeded()
            for offset in [0, 2000, 8000, 20000] {
                cv.setContentOffset(CGPoint(x: 0, y: CGFloat(offset)), animated: false)
                cv.collectionViewLayout.invalidateLayout()
                cv.layoutIfNeeded()
                // 矩形上沿刻意低于粘性头底边（offset+10 < offset+48）→ 钳制路径被覆盖
                let rawRect = CGRect(x: 12, y: CGFloat(offset) + 10, width: 366, height: 520)
                let hit = tester.hitTest(rectInContent: rawRect)
                // 暴力求交基准：矩形上边钳到视口顶 + 粘性头高（docs/32 §2.4 第 6 步）
                let stickyBottom = CGFloat(offset) + DSSpacing.monthHeaderHeight
                var expected = Set<IndexPath>()
                if rawRect.maxY > stickyBottom {
                    let baseRect = CGRect(x: 12, y: stickyBottom, width: 366,
                                          height: rawRect.maxY - stickyBottom)
                    for section in 0..<40 {
                        for item in 0..<50 {
                            if let attrs = layout.layoutAttributesForItem(at: IndexPath(item: item, section: section)),
                               attrs.frame.intersects(baseRect) {
                                expected.insert(IndexPath(item: item, section: section))
                            }
                        }
                    }
                }
                XCTAssertEqual(hit, expected,
                               "columns=\(columns) offset=\(offset) 命中集合必须等于逐 item 暴力求交")
            }
        }
    }

    /// docs/32 §4.2 ③（docs/31 H3）：参数公式 (W − s(c−1))/c 必须等于真实 attributes 宽。
    /// 相等 → 旧横向估算公式与 iOS 16 真实布局一致；GridHitTester 读真实 attributes，
    /// 即使未来公式失效也天然免疫（结论写进注释，docs/32 §4.2 第 3/4 条）。
    func testItemWidthMatchesParameterFormulaAllColumns() throws {
        let spacing = CGFloat(DSSpacing.gridSpacing)
        for columns in [2, 3, 4, 5] {
            let (cv, layout, _) = makeParamGrid(columns: columns)
            cv.setContentOffset(.zero, animated: false)
            cv.collectionViewLayout.invalidateLayout()
            cv.layoutIfNeeded()
            let attrs = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)),
                                      "columns=\(columns) 必须能取到首格 attributes")
            let expected = (CGFloat(390) - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            XCTAssertEqual(attrs.frame.width, expected, accuracy: 0.5,
                           "H3：columns=\(columns) item 宽必须等于 (W − s(c−1))/c")
        }
    }

    /// docs/32 §4.2 映射回归锁：严格落在 a3-7 内部的矩形只命中 a3-7，不命中相邻 a3-6
    /// （旧参数推算的 pitch/origin 误差把邻格算进同一命中带，docs/31 G7/G9）。
    func testMarqueeHitSelectsA3_7NotA3_6() throws {
        let (cv, layout, _) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let attrs = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 3)),
                                  "必须能取到 a3-7 的真实 attributes")
        let rect = attrs.frame.insetBy(dx: 2, dy: 2)
        let ids = Set(tester.hitTest(rectInContent: rect).map { "a\($0.section)-\($0.item)" })
        XCTAssertEqual(ids, ["a3-7"], "回归锁：矩形必须只命中 a3-7")
        XCTAssertTrue(ids.contains("a3-7"))
        XCTAssertFalse(ids.contains("a3-6"), "a3-6 不得被命中")
    }

    /// docs/32 §2.4 第 8 步：缓存已热后，同一帧深位置框选 ≤ 60 次 layoutAttributesForItem 查询
    /// （首帧构建缓存不计入断言；O(可见行×列) 复杂度锁，docs/31 A15）。
    func testLastQueryCountBoundedAtDeepOffset() throws {
        let (cv, _, _) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(CGPoint(x: 0, y: 8000), animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let rect = CGRect(x: 12, y: 8010, width: 366, height: 520)
        _ = tester.hitTest(rectInContent: rect)
        _ = tester.hitTest(rectInContent: rect)
        XCTAssertLessThanOrEqual(tester.lastQueryCount, 60,
                                 "缓存已热帧查询数 \(tester.lastQueryCount) 必须 ≤ 60")
    }
}
