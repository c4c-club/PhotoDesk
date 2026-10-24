// MARK: - 职责说明：照片库网格（docs/05 M1 任务 1.4）——UIKit：UICollectionView + Compositional Layout +
// Diffable DataSource + Prefetching（不用 SwiftUI LazyVGrid，iOS 15 万级滚动性能不达标，docs/02 §3.1）。
// 主网格 PHFetchOptions.includeHiddenAssets = false；月份分组粘性头 + 右侧月份索引条（docs/04 §3.1）。
// TODO(P1): LibraryView（UIViewControllerRepresentable 包装）+ LibraryViewModel（分批 fetch 每批 500）。
