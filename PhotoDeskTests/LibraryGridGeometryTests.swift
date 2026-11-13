// MARK: - 职责说明：真实 UICollectionViewCompositionalLayout 网格几何红测试（M17 T01，docs/31 §2.2 G8/H1）——
// 用与 LibraryViewController.makeLayout 同参的真实布局（3 列 / 48pt 粘性头 / pinToVisibleBounds）
// + contentOffset.y = 5000 实测：可视段头的 supplementary attributes.minY 必须等于该段首格
// minY - 头高。pinToVisibleBounds 把钉住的头的 minY 平移到视口顶时差值达数百 pt → H1 实锤；
// 若差值为 0 则 H1 被证伪（supplementary attributes 未被 pin 污染）。T04 真几何改造的验收锚点。

import XCTest
@testable import PhotoDesk

@MainActor
final class LibraryGridGeometryTests: XCTestCase, UICollectionViewDataSource {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // 与 LibraryViewController.makeLayout(:1727-1751) 同参，改布局必须两边同步
    private let columns = 3
    private let headerHeight: CGFloat = DSSpacing.monthHeaderHeight
    private let sectionCount = 10
    private let itemsPerSection = 30

    private func makeRealGrid() -> (collectionView: UICollectionView, layout: UICollectionViewCompositionalLayout) {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .fractionalWidth(1.0 / CGFloat(columns)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
        group.interItemSpacing = .fixed(DSSpacing.gridSpacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = DSSpacing.gridSpacing
        section.contentInsets = .zero
        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                heightDimension: .absolute(headerHeight))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                 elementKind: UICollectionView.elementKindSectionHeader,
                                                                 alignment: .top)
        header.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [header]
        let layout = UICollectionViewCompositionalLayout(section: section)
        let cv = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                  collectionViewLayout: layout)
        cv.dataSource = self
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "geometry-cell")
        cv.register(UICollectionReusableView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: "geometry-header")
        return (cv, layout)
    }

    /// H1 判定：滚动 5000pt 后，被钉住段的头 attributes.minY == 首格 minY - 48
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
        // 差值 ≤ 0.5pt 视为未钉住（浮点容差）；被 pin 平移时差值是数百 pt 量级
        XCTAssertEqual(diff, 0, accuracy: 0.5,
                       "可视段头的 supplementary attributes 不得被 pinToVisibleBounds 平移（docs/31 G8/H1）")
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
}
