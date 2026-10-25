// MARK: - 职责说明：相簿内容页（docs/05 M3 任务 3.6）——
// 展示单个相簿内的资源（AssetRepository scope .album）；M3 只读，M6 编辑入口随后接入。

import SwiftUI
import Photos

struct AlbumDetailView: View {
    let album: AlbumsView.AlbumSummary
    @State private var items: [PhotoItem] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: DSSpacing.gridSpacing)],
                      spacing: DSSpacing.gridSpacing) {
                ForEach(items) { item in
                    AlbumThumb(item: item)
                }
            }
            .padding(DSSpacing.gridSpacing)
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let repository = AppContainer.shared.assetRepository
            let total = await repository.prepare(scope: .album(localIdentifier: album.id))
            guard total > 0 else { return }
            items = await repository.fetch(scope: .album(localIdentifier: album.id),
                                           offset: 0,
                                           limit: total)
        }
    }
}

/// 相簿缩略图（与 VaultThumb 同构：独立页面组件）
private struct AlbumThumb: View {
    let item: PhotoItem
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(ds: DSColor.bgSecondary))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .cornerRadius(DSSpacing.gridCornerRadius)
        .task {
            image = await AppContainer.shared.imagePipeline.thumbnail(
                for: item.id,
                size: CGSize(width: 110, height: 110),
                scale: UIScreen.main.scale)
        }
    }
}
