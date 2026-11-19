// MARK: - 职责说明：真实 UICollectionViewCompositionalLayout 网格几何测试（M17 T01 红探针 →
// T04 行为锁，docs/31 §2.2 G8/H1，docs/32 §4.2）——用生产布局工厂 LibraryGridLayout.make
// 的真实布局（3 列 / 48pt 粘性头 / pinToVisibleBounds）实测两件事：
// H1（§4.2 第 4 条）：pinToVisibleBounds 把被钉住段的 supplementary attributes.minY 平移到
//   视口顶（offset=5000 实测 diff=902pt）→ 命中/位置几何一律不得读 supplementary；
// H3（§4.2 第 3 条）：参数公式 (W − s(c−1))/c 与真实 item 宽一致。
// 注意：compositional layout 需 setContentOffset + invalidateLayout + layoutIfNeeded 预热后
// layoutAttributesForItem 才返回非 nil（CI 43546275550 实锤）——各用例统一走该预热。

import XCTest
import PhotoDeskCore
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

    /// 真实 LibraryGridLayout + 390 宽 + 40 段 × 50 item（docs/32 §4.2 ①）。
    /// 注意：UICollectionView.dataSource 是弱引用——调用方必须保活返回的 dataSource，
    /// 否则网格退化为 0 段，命中断言空对空假绿（CI 43549332935 实锤）。
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

    /// docs/32 §4.2 ③（docs/31 H3）：参数公式 (W − s(c−1))/c 必须等于真实 attributes 宽。
    /// 相等 → 旧横向估算公式与 iOS 16 真实布局一致；GridHitTester 读真实 attributes，
    /// 即使未来公式失效也天然免疫（结论写进注释，docs/32 §4.2 第 3/4 条）。
    func testItemWidthMatchesParameterFormulaAllColumns() throws {
        let spacing = CGFloat(DSSpacing.gridSpacing)
        for columns in [2, 3, 4, 5] {
            let (cv, layout, gridData) = makeParamGrid(columns: columns)
            cv.layoutIfNeeded()
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

    /// 映射回归锁（docs/32 §4.2 迁移到线段语义，docs/38 §4）：完全落在 a3-7 内部的竖向
    /// 短线段只命中 a3-7，不命中相邻 a3-6 / a3-8 / a3-4（docs/31 G7/G9 根治回归锁）。
    func testHitTestLineSelectsA3_7NotNeighbors() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let attrs = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 3)),
                                  "必须能取到 a3-7 的真实 attributes")
        let start = CGPoint(x: attrs.frame.midX, y: attrs.frame.minY + 2)
        let end = CGPoint(x: attrs.frame.midX, y: attrs.frame.maxY - 2)
        let ids = tester.hitTestLine(from: start, to: end).map { "a\($0.section)-\($0.item)" }
        XCTAssertEqual(ids, ["a3-7"], "回归锁：格内短线段必须只命中 a3-7")
        XCTAssertFalse(ids.contains("a3-6"), "a3-6 不得被命中")
        XCTAssertFalse(ids.contains("a3-8"), "a3-8 不得被命中")
        XCTAssertFalse(ids.contains("a3-4"), "a3-4 不得被命中")
    }

    // MARK: - M17 T08 X08：缩略图像素尺寸与布局同源（LibraryGridLayout.itemWidth）

    /// cellPixelSize 公式改为与布局工厂同一来源：(rowWidth − (c−1)×gridSpacing) / c。
    func testGridItemWidthMatchesLayoutFormula() {
        XCTAssertEqual(LibraryGridLayout.itemWidth(for: 3, rowWidth: 390),
                       (390 - 2 * DSSpacing.gridSpacing) / 3, accuracy: 0.001)
        XCTAssertEqual(LibraryGridLayout.itemWidth(for: 2, rowWidth: 320),
                       (320 - DSSpacing.gridSpacing) / 2, accuracy: 0.001)
        XCTAssertEqual(LibraryGridLayout.itemWidth(for: 1, rowWidth: 390), 390, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(LibraryGridLayout.itemWidth(for: 5, rowWidth: 0), 0, "退化输入不得为负")
    }

    // MARK: - M18 T05：hitTestLine 真布局测试（docs/38 §2/§3：线段扫掠、滑到哪选到哪）

    /// 竖向线段穿过 a3-7 至下一行：命中非空、含 a3-7，且序列按经过顺序（minY 单调不减）。
    func testHitTestLineSweepsTopToBottomInOrder() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let attrs = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 3)),
                                  "必须能取到 a3-7 的真实 attributes")
        let start = CGPoint(x: attrs.frame.midX, y: attrs.frame.minY - 1)
        let end = CGPoint(x: attrs.frame.midX, y: attrs.frame.maxY + 60)
        let hit = tester.hitTestLine(from: start, to: end)
        XCTAssertFalse(hit.isEmpty, "穿过两行的竖向线段必须命中 cell")
        XCTAssertTrue(hit.contains(IndexPath(item: 7, section: 3)), "线段穿过 a3-7 必须命中")
        var lastY: CGFloat = -.greatestFiniteMagnitude
        for path in hit {
            let frame = try XCTUnwrap(layout.layoutAttributesForItem(at: path)).frame
            XCTAssertGreaterThanOrEqual(frame.minY, lastY,
                                        "命中序列必须按经过顺序（minY 单调不减）")
            lastY = frame.minY
        }
    }

    /// 横向线段从 a3-7（第 2 行中列）中部向左穿到 a3-6（同行左列）内部：首个命中 a3-7，
    /// x 单调不增，止点格 a3-6 命中（行优先布局：a3-7 左侧同行为 a3-6，跨行不属横向线段）。
    func testHitTestLineHorizontalOrdersLeftwardFromAnchor() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let attrs7 = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 3)),
                                   "必须能取到 a3-7 的真实 attributes")
        let attrs6 = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 6, section: 3)),
                                   "必须能取到 a3-6 的真实 attributes")
        let start = CGPoint(x: attrs7.frame.midX, y: attrs7.frame.midY)
        let end = CGPoint(x: attrs6.frame.minX + 2, y: attrs7.frame.midY)
        let hit = tester.hitTestLine(from: start, to: end)
        XCTAssertEqual(hit.first, IndexPath(item: 7, section: 3),
                       "起点所在格必须是首个命中（滑到哪选到哪从锚点起）")
        XCTAssertTrue(hit.contains(IndexPath(item: 6, section: 3)),
                      "线段止点在 a3-6 内部必须命中 a3-6")
        var lastX: CGFloat = .greatestFiniteMagnitude
        for path in hit {
            let frame = try XCTUnwrap(layout.layoutAttributesForItem(at: path)).frame
            XCTAssertLessThanOrEqual(frame.minX, lastX,
                                     "向左线段的命中序列必须按经过顺序（minX 单调不增）")
            lastX = frame.minX
        }
    }

    // MARK: - M18 T07：真布局线段几何（docs/37 §4/§7，docs/38 §4）

    /// 暴力基准（口径独立复算，防「实现自证」）：全量 layoutAttributesForItem 与线段求交。
    /// 命中判据 = Liang-Barsky 进入参数 tEnter = max(tx, ty, 0) ≤ tExit；粘性头遮挡口径与
    /// 生产一致（视口顶所在段的钉住头底边以上完全遮住与已滚出屏的 cell 不命中，
    /// 跨头底边的 cell 有效顶钳到头底边）；排序 = (tEnter, 合成键 "s段-i项" 字典序)，
    /// 合成键与生产 hitTestLine 同格式（docs/38 §4 第 3 行）。
    private func bruteForceLineHit(cv: UICollectionView,
                                   layout: UICollectionViewLayout,
                                   from: CGPoint,
                                   to: CGPoint) -> [IndexPath] {
        let expand = CGFloat(SlideSelectConfig.hitExpansion)
        let eps = CGFloat(SlideSelectConfig.segmentEpsilon)
        let headerHeight = CGFloat(DSSpacing.monthHeaderHeight)
        // 视口顶所在段（段起点 = 首格 minY − 头高；M17 T01 H1：item attributes 永不被 pin 平移）
        let viewportTop = cv.contentOffset.y + cv.adjustedContentInset.top
        var hasPinnedSection = false
        for section in 0..<cv.numberOfSections {
            guard let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) else { continue }
            if first.frame.minY - headerHeight <= viewportTop { hasPinnedSection = true }
        }
        let clipTop: CGFloat? = hasPinnedSection ? viewportTop + headerHeight : nil

        let dx = to.x - from.x
        let dy = to.y - from.y
        var hits: [(t: Double, id: String, path: IndexPath)] = []
        for section in 0..<cv.numberOfSections {
            for item in 0..<cv.numberOfItems(inSection: section) {
                let path = IndexPath(item: item, section: section)
                guard let attrs = layout.layoutAttributesForItem(at: path) else { continue }
                var frame = attrs.frame
                if let clip = clipTop {
                    if frame.maxY <= clip { continue }                       // 完全被头遮住/已滚出屏
                    if frame.minY < clip {
                        frame = CGRect(x: frame.minX, y: clip,
                                       width: frame.width, height: frame.maxY - clip)
                    }
                }
                let minX = frame.minX - expand
                let maxX = frame.maxX + expand
                let minY = frame.minY - expand
                let maxY = frame.maxY + expand
                var tEnter = 0.0
                var tExit = 1.0
                var miss = false
                if abs(dx) <= eps {
                    if from.x < minX || from.x > maxX { miss = true }
                } else {
                    let t1 = Double((minX - from.x) / dx)
                    let t2 = Double((maxX - from.x) / dx)
                    tEnter = max(tEnter, min(t1, t2))
                    tExit = min(tExit, max(t1, t2))
                }
                if abs(dy) <= eps {
                    if from.y < minY || from.y > maxY { miss = true }
                } else {
                    let t1 = Double((minY - from.y) / dy)
                    let t2 = Double((maxY - from.y) / dy)
                    tEnter = max(tEnter, min(t1, t2))
                    tExit = min(tExit, max(t1, t2))
                }
                guard !miss, tEnter <= tExit else { continue }
                hits.append((tEnter, "s\(section)-i\(item)", path))
            }
        }
        return hits.sorted { $0.t != $1.t ? $0.t < $1.t : $0.id < $1.id }.map(\.path)
    }

    /// 核心矩阵（docs/38 §4 第 1 行）：2/3/4/5 列 × offset {0,2000,8000,20000}，竖向与斜线
    /// 线段的 hitTestLine 序列必须等于全量暴力基准（真实 attributes 求交 + tMin 排序）。
    func testHitTestLineMatchesBruteForceAcrossColumnsAndOffsets() throws {
        for columns in [2, 3, 4, 5] {
            let (cv, layout, gridData) = makeParamGrid(columns: columns)
            let tester = GridHitTester(collectionView: cv)
            cv.layoutIfNeeded()
            for offset in [0, 2000, 8000, 20000] {
                cv.setContentOffset(CGPoint(x: 0, y: CGFloat(offset)), animated: false)
                cv.collectionViewLayout.invalidateLayout()
                cv.layoutIfNeeded()
                // dataSource 弱引用陷阱（M17 T04 实锤）：gridData 由 makeParamGrid 返回值绑定保活，
                // 若解绑则网格退化 0 段 → 命中空对空假绿。
                let verticalStart = CGPoint(x: 30, y: CGFloat(offset) + 60)
                let verticalEnd = CGPoint(x: 30, y: CGFloat(offset) + 900)
                XCTAssertEqual(tester.hitTestLine(from: verticalStart, to: verticalEnd),
                               bruteForceLineHit(cv: cv, layout: layout,
                                                 from: verticalStart, to: verticalEnd),
                               "columns=\(columns) offset=\(offset) 竖向线段必须等于暴力基准")
                let diagonalStart = CGPoint(x: 10, y: CGFloat(offset) + 60)
                let diagonalEnd = CGPoint(x: 380, y: CGFloat(offset) + 900)
                XCTAssertEqual(tester.hitTestLine(from: diagonalStart, to: diagonalEnd),
                               bruteForceLineHit(cv: cv, layout: layout,
                                                 from: diagonalStart, to: diagonalEnd),
                               "columns=\(columns) offset=\(offset) 斜线必须等于暴力基准")
            }
        }
    }

    /// 反向线段（docs/38 §2 回滑语义）：命中集合相同、顺序精确镜像（各格进入参数互异，无并列）。
    func testHitTestLineReverseSegmentMirrorsForward() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let start = CGPoint(x: 200, y: 60)
        let end = CGPoint(x: 200, y: 700)
        let forward = tester.hitTestLine(from: start, to: end)
        let backward = tester.hitTestLine(from: end, to: start)
        XCTAssertFalse(forward.isEmpty, "竖向长线段必须命中多格")
        XCTAssertEqual(backward, forward.reversed(),
                       "反向线段 = 正向序列镜像（滑到哪选到哪、回滑取消）")
    }

    /// 斜线穿格（docs/38 §4）：x/y 同增的对角线，命中格行主序下标严格递增（不回跳、不重复）。
    func testHitTestLineDiagonalCrossesInSweepOrder() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let hit = tester.hitTestLine(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 380, y: 900))
        XCTAssertGreaterThanOrEqual(hit.count, 4, "跨两列两行的对角线必须命中 ≥4 格")
        var lastIndex = -1
        for path in hit {
            let flat = path.section * 50 + path.item
            XCTAssertGreaterThan(flat, lastIndex,
                                 "对角线命中必须按行主序严格递增（扫掠语义），发现回跳 \(flat) ≤ \(lastIndex)")
            lastIndex = flat
        }
    }

    /// 粘性头遮挡（docs/37 §4 第 4 行）：offset 8000 处线段起点在遮挡区内，
    /// 被钉住头完全遮住的 cell 不得入栈；整体序列仍等于暴力基准（同口径钳制）。
    func testHitTestLineSkipsCellsUnderStickyHeader() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(CGPoint(x: 0, y: 8000), animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let stickyBottom = CGFloat(8000) + CGFloat(DSSpacing.monthHeaderHeight)
        let start = CGPoint(x: 60, y: 8000 + 10)      // 起点在钉住头遮挡区内
        let end = CGPoint(x: 60, y: 8000 + 400)
        let hit = tester.hitTestLine(from: start, to: end)
        XCTAssertEqual(hit, bruteForceLineHit(cv: cv, layout: layout, from: start, to: end),
                       "粘性头场景命中序列必须等于暴力基准（同口径钳制）")
        let hidden = hit.filter { path in
            guard let frame = layout.layoutAttributesForItem(at: path)?.frame else { return false }
            return frame.maxY <= stickyBottom
        }
        XCTAssertTrue(hidden.isEmpty, "被钉住头完全遮住的 cell 不得命中：\(hidden)")
    }

    /// 缓存热帧查询闸（docs/31 A15）：hitTestLine 受 ≤60 次/热帧约束（O(可见行×列) 复杂度锁）。
    func testHitTestLineQueryCountBoundedAtDeepOffset() throws {
        let (cv, _, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(CGPoint(x: 0, y: 8000), animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let start = CGPoint(x: 30, y: 8060)
        let end = CGPoint(x: 30, y: 8900)
        _ = tester.hitTestLine(from: start, to: end)   // 首帧构建缓存不计入
        _ = tester.hitTestLine(from: start, to: end)   // 热帧
        XCTAssertLessThanOrEqual(tester.lastQueryCount, 60,
                                 "缓存已热帧查询数 \(tester.lastQueryCount) 必须 ≤ 60")
    }

    /// invalidateGeometry() 后重建一致性（docs/38 §4 第 4 行）：失效前后同线段结果完全一致。
    func testHitTestLineInvalidateGeometryRebuildsConsistently() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 4)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(CGPoint(x: 0, y: 2000), animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let start = CGPoint(x: 100, y: 2060)
        let end = CGPoint(x: 100, y: 2800)
        let before = tester.hitTestLine(from: start, to: end)
        tester.invalidateGeometry()
        let after = tester.hitTestLine(from: start, to: end)
        XCTAssertEqual(before, after, "缓存失效重建后命中序列必须一致")
        XCTAssertEqual(after, bruteForceLineHit(cv: cv, layout: layout, from: start, to: end))
    }

    /// 零长度线段 = 起手 cell 命中（docs/37 §4：扩展 1pt 起手语义的线段等价）。
    func testHitTestLineZeroLengthHitsAnchorCellOnly() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        cv.layoutIfNeeded()
        cv.setContentOffset(.zero, animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
        let attrs = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 3)),
                                  "必须能取到 a3-7 的真实 attributes")
        let center = CGPoint(x: attrs.frame.midX, y: attrs.frame.midY)
        let hit = tester.hitTestLine(from: center, to: center)
        XCTAssertEqual(hit, [IndexPath(item: 7, section: 3)],
                       "零长度线段只命中起手格（相邻格 0.5pt 内不得误命中）")
    }

    // MARK: - M19 T04：rowBandHitTest 行带命中（docs/42 §3.2/§4、docs/43 T04）——
    // 关键断言：右列下滑 3 行 == 3 × columns 整行，逐 id 比较（非计数）。
    // 独立口径：期望序列由 attributes 手工派生（不经 RowBandMap/命中器），锚点段用
    // sectionAtContentY 独立定位；dataSource 强持有（历史踩坑：弱引用 0 段空网格假绿）。

    /// 独立口径：内容 y 所在段（段首行 minY ≤ y < 下一段首行 minY），不经命中器。
    private func sectionAtContentY(_ y: CGFloat,
                                   layout: UICollectionViewCompositionalLayout,
                                   sectionCount: Int) -> Int {
        for s in 0..<sectionCount {
            guard let a0 = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: s)) else { continue }
            let start = a0.frame.minY
            let end: CGFloat
            if s + 1 < sectionCount,
               let next = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: s + 1)) {
                end = next.frame.minY
            } else {
                end = .greatestFiniteMagnitude
            }
            if start <= y, y < end { return s }
        }
        return sectionCount - 1
    }

    /// 行带期望：锚点 (section, fromRow) 起 rowCount 行的全部 item（行主序），按段内 item 上界截断。
    private func expectedBandItems(section: Int, fromRow: Int, rowCount: Int,
                                   columns: Int, itemsPerSection: Int = 50) -> [IndexPath] {
        var out: [IndexPath] = []
        for r in fromRow..<(fromRow + rowCount) {
            for c in 0..<columns {
                let item = r * columns + c
                if item < itemsPerSection { out.append(IndexPath(item: item, section: section)) }
            }
        }
        return out
    }

    private func warmUp(_ cv: UICollectionView, offset: CGFloat) {
        cv.layoutIfNeeded()
        cv.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        cv.collectionViewLayout.invalidateLayout()
        cv.layoutIfNeeded()
    }

    /// 最关键断言：右列起点向下 3 行 → 3 × columns 整行（行主序逐 id）。
    /// 2/3/4/5 列 × contentOffset.y ∈ {0, 2000, 8000, 20000}。
    func testRowBandHitTestRightColumnThreeRowsWholeBandsExactIDs() throws {
        for columns in [2, 3, 4, 5] {
            for offset in [CGFloat(0), 2000, 8000, 20000] {
                let (cv, layout, gridData) = makeParamGrid(columns: columns)
                let tester = GridHitTester(collectionView: cv)
                warmUp(cv, offset: offset)
                let section = sectionAtContentY(offset + 400, layout: layout, sectionCount: 40)
                let row = 2
                let anchor = IndexPath(item: row * columns + (columns - 1), section: section)
                let below = IndexPath(item: (row + 2) * columns + (columns - 1), section: section)
                let a = try XCTUnwrap(layout.layoutAttributesForItem(at: anchor),
                                      "columns=\(columns) offset=\(offset) 锚点 attributes 缺失")
                let b = try XCTUnwrap(layout.layoutAttributesForItem(at: below),
                                      "columns=\(columns) offset=\(offset) 终点 attributes 缺失")
                let hit = tester.rowBandHitTest(from: CGPoint(x: a.frame.midX, y: a.frame.midY),
                                                to: CGPoint(x: b.frame.midX, y: b.frame.midY))
                XCTAssertEqual(hit, expectedBandItems(section: section, fromRow: row, rowCount: 3, columns: columns),
                               "columns=\(columns) offset=\(offset)：右列下滑 3 行必须命中 3×\(columns) 整行（行主序逐 id）")
            }
        }
    }

    /// 左列同样整行（左右一致，docs/41 §3）。
    func testRowBandHitTestLeftColumnAlsoWholeRow() throws {
        let columns = 3
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let section = sectionAtContentY(2400, layout: layout, sectionCount: 40)
        let row = 2
        let anchor = IndexPath(item: row * columns, section: section)
        let below = IndexPath(item: (row + 2) * columns, section: section)
        let a = try XCTUnwrap(layout.layoutAttributesForItem(at: anchor))
        let b = try XCTUnwrap(layout.layoutAttributesForItem(at: below))
        let hit = tester.rowBandHitTest(from: CGPoint(x: a.frame.midX, y: a.frame.midY),
                                        to: CGPoint(x: b.frame.midX, y: b.frame.midY))
        XCTAssertEqual(hit, expectedBandItems(section: section, fromRow: row, rowCount: 3, columns: columns),
                       "左列下滑 3 行必须同样命中整行")
    }

    /// 同一行内横向拖动 → 恰好该行全列（不扩散到相邻行）。
    func testRowBandHitTestHorizontalDragExactRow() throws {
        let columns = 3
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let section = sectionAtContentY(2400, layout: layout, sectionCount: 40)
        let row = 2
        let left = IndexPath(item: row * columns, section: section)
        let right = IndexPath(item: row * columns + columns - 1, section: section)
        let a = try XCTUnwrap(layout.layoutAttributesForItem(at: left))
        let b = try XCTUnwrap(layout.layoutAttributesForItem(at: right))
        let hit = tester.rowBandHitTest(from: CGPoint(x: a.frame.midX, y: a.frame.midY),
                                        to: CGPoint(x: b.frame.midX, y: b.frame.midY))
        XCTAssertEqual(hit, expectedBandItems(section: section, fromRow: row, rowCount: 1, columns: columns),
                       "横拖必须恰好命中该行全列")
    }

    /// 斜向拖动 → 经过行带序列（含中间行）全部整行，行主序；不产生矩形外的行。
    func testRowBandHitTestDiagonalCoversBandSequence() throws {
        let columns = 3
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let section = sectionAtContentY(2400, layout: layout, sectionCount: 40)
        let a = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 2 * columns, section: section)))
        let b = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 5 * columns + columns - 1, section: section)))
        let hit = tester.rowBandHitTest(from: CGPoint(x: a.frame.midX, y: a.frame.midY),
                                        to: CGPoint(x: b.frame.midX, y: b.frame.midY))
        XCTAssertEqual(hit, expectedBandItems(section: section, fromRow: 2, rowCount: 4, columns: columns),
                       "斜拖 (row2,col0)→(row5,colLast) 必须命中 row2..row5 全部整行（行主序）")
    }

    /// 末行不满 → 只含实际 item（50 项/4 列 → 13 行，末行 2 项）。
    func testRowBandHitTestPartialLastRowRealItemsOnly() throws {
        let columns = 4
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let section = 3
        let lastRow = 12   // 50 项 / 4 列 → 行 0..12，末行 item 48..49
        let anchor = IndexPath(item: lastRow * columns, section: section)
        let a = try XCTUnwrap(layout.layoutAttributesForItem(at: anchor))
        let hit = tester.rowBandHitTest(from: CGPoint(x: a.frame.midX, y: a.frame.midY),
                                        to: CGPoint(x: a.frame.midX, y: a.frame.midY))
        XCTAssertEqual(hit, [IndexPath(item: 48, section: 3), IndexPath(item: 49, section: 3)],
                       "末行不满只展开真实 item（零长线段 = 指尖所在整行）")
    }

    /// 零长度线段返回该点所在整行（非末行）。
    func testRowBandHitTestZeroLengthReturnsWholeBand() throws {
        let columns = 3
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let a = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 3)))
        let center = CGPoint(x: a.frame.midX, y: a.frame.midY)
        let hit = tester.rowBandHitTest(from: center, to: center)
        XCTAssertEqual(hit, expectedBandItems(section: 3, fromRow: 2, rowCount: 1, columns: columns),
                       "零长度线段 = 指尖所在整行（a3-7 在 row2 → 命中 a3-6/7/8）")
    }

    /// 粘性头钉住：起点位于遮挡区 → 钳到头下缘最近可见行带；被完全遮住的行不得出现在结果。
    func testRowBandHitTestClampsToFirstVisibleRowBelowStickyHeader() throws {
        let columns = 3
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        let offset: CGFloat = 8000
        warmUp(cv, offset: offset)
        let section = sectionAtContentY(offset + 400, layout: layout, sectionCount: 40)
        let clipTop = offset + CGFloat(DSSpacing.monthHeaderHeight)
        // 独立口径：clipTop 所在可见行 k（段首行 minY 与次行 minY 派生行距）
        let a0 = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section)))
        let a1 = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: columns, section: section)))
        let firstRowMinY = a0.frame.minY
        let pitch = a1.frame.minY - a0.frame.minY
        let k = max(0, Int(((clipTop - firstRowMinY) / pitch).rounded(.down)))
        // 起点 y 在遮挡区内（= offset < clipTop），终点 = 可见首行下方第 2 行右列
        let fromY = offset
        let toRow = k + 2
        let to = IndexPath(item: toRow * columns + columns - 1, section: section)
        let b = try XCTUnwrap(layout.layoutAttributesForItem(at: to))
        let anchorX = a0.frame.midX
        let hit = tester.rowBandHitTest(from: CGPoint(x: anchorX, y: fromY),
                                        to: CGPoint(x: b.frame.midX, y: b.frame.midY))
        XCTAssertEqual(hit, expectedBandItems(section: section, fromRow: k, rowCount: 3, columns: columns),
                       "起点在遮挡区必须钳到头下缘最近可见行带 k=\(k)，且不含被完全遮住的行")
        // 零长线段完全落在遮挡区 → 同样钳到头下缘最近可见行带（非 nil、非遮挡行）
        let zero = tester.rowBandHitTest(from: CGPoint(x: anchorX, y: fromY),
                                         to: CGPoint(x: anchorX, y: fromY))
        XCTAssertEqual(zero, expectedBandItems(section: section, fromRow: k, rowCount: 1, columns: columns),
                       "遮挡区内零长线段 = 头下缘最近可见整行")
    }

    /// 跨段：中间 section 整段按平铺序入选（末行不满段也按真实 item）。
    func testRowBandHitTestCrossSectionCoversWholeIntermediateSections() throws {
        let columns = 2   // 50 项/2 列 → 25 行，末行 item 48..49
        let (cv, layout, gridData) = makeParamGrid(columns: columns)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let from = IndexPath(item: 20 * columns, section: 1)
        let to = IndexPath(item: 2 * columns + columns - 1, section: 2)
        let a = try XCTUnwrap(layout.layoutAttributesForItem(at: from))
        let b = try XCTUnwrap(layout.layoutAttributesForItem(at: to))
        let hit = tester.rowBandHitTest(from: CGPoint(x: a.frame.midX, y: a.frame.midY),
                                        to: CGPoint(x: b.frame.midX, y: b.frame.midY))
        var expected: [IndexPath] = []
        expected += expectedBandItems(section: 1, fromRow: 20, rowCount: 5, columns: columns)
        expected += expectedBandItems(section: 2, fromRow: 0, rowCount: 3, columns: columns)
        XCTAssertEqual(hit, expected, "跨段必须按平铺序覆盖中间 section 整段（含末行真实 item）")
        XCTAssertEqual(hit.count, 10 + 6, "段 1 剩余 5 行(10 item) + 段 2 前 3 行(6 item)")
    }

    /// invalidateGeometry() 后重建一致（rowBandMap 缓存随失效重建）。
    func testRowBandHitTestInvalidateGeometryRebuildsConsistently() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 4)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 2000)
        let from = CGPoint(x: 100, y: 2100)
        let to = CGPoint(x: 100, y: 2800)
        let before = tester.rowBandHitTest(from: from, to: to)
        tester.invalidateGeometry()
        let after = tester.rowBandHitTest(from: from, to: to)
        XCTAssertEqual(before, after, "缓存失效重建后行带命中序列必须一致")
        XCTAssertFalse(after.isEmpty)
    }

    /// 缓存热帧查询数 ≤ 60（行带路径热帧零 attributes 查询，全缓存命中）。
    func testRowBandHitTestQueryCountBoundedAtDeepOffset() throws {
        let (cv, layout, gridData) = makeParamGrid(columns: 3)
        let tester = GridHitTester(collectionView: cv)
        warmUp(cv, offset: 8000)
        let from = CGPoint(x: 100, y: 8100)
        let to = CGPoint(x: 100, y: 8800)
        _ = tester.rowBandHitTest(from: from, to: to)   // 冷帧建缓存
        _ = tester.rowBandHitTest(from: from, to: to)   // 热帧
        XCTAssertLessThanOrEqual(tester.lastQueryCount, 60,
                                 "缓存已热帧查询数 \(tester.lastQueryCount) 必须 ≤ 60")
    }
}
