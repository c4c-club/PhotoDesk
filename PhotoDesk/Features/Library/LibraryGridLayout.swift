// MARK: - 职责说明：库网格组合布局工厂（M17 T04 自 LibraryViewController.makeLayout 原样搬出，
// 行为零变化）——2..5 列方形网格 + 48pt pinToVisibleBounds 粘性月头（docs/04 §3.1）。
// 命中几何一律由 GridHitTester 读真实 layoutAttributes（docs/32 §2.4），本文件不做参数推算。

import UIKit

enum LibraryGridLayout {
    /// X08（M17 T08，docs/31 §3）：单元格点宽与 make() 同源——(行宽 − (c−1)×gridSpacing) / c。
    /// 行宽 = collectionView 行宽（fractionalWidth 布局减去列间距后的实际 item 宽）。
    static func itemWidth(for columns: Int, rowWidth: CGFloat) -> CGFloat {
        guard columns > 0 else { return 0 }
        return max(0, (rowWidth - CGFloat(columns - 1) * DSSpacing.gridSpacing) / CGFloat(columns))
    }

    static func make(columns: Int) -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .fractionalWidth(1.0 / CGFloat(columns)))
        // subitem:count: 把单个 item 复制为 columns 列
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
        group.interItemSpacing = .fixed(DSSpacing.gridSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = DSSpacing.gridSpacing
        section.contentInsets = .zero

        // 粘性月份分组头（docs/04 §3.1：2026年10月 · 128 张）
        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                heightDimension: .absolute(48))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                 elementKind: UICollectionView.elementKindSectionHeader,
                                                                 alignment: .top)
        header.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [header]
        return UICollectionViewCompositionalLayout(section: section)
    }
}
