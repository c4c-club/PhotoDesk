// MARK: - 职责说明：相簿内容页（docs/05 M3 任务 3.6；docs/09 D15 补齐）——
// 缩略图可点开全屏查看器（ViewerContainer）；上下文菜单支持移出相簿（只移引用，不删照片）；
// 收藏即时写。隐藏/相簿页量级小，LazyVGrid 展示（主库网格管线约束不在此页）。

import SwiftUI
import Photos

struct AlbumDetailView: View {
    let album: AlbumsView.AlbumSummary
    @State private var items: [PhotoItem] = []
    @State private var viewerContext: ViewerContext?
    @State private var message: String?
    @State private var isLoading = true
    /// 分页加载：每页 200，触底续拉（docs/25 §7 #4：禁一次性 limit: total）
    @State private var total = 0
    @State private var isLoadingMore = false

    private static let pageSize = 200

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在加载相簿…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                    Text("这个相簿还没有照片")
                        .font(.headline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Text("在照片库中长按选择照片，用「加入相簿」添加")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DSSpacing.screenPadding)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: DSSpacing.gridSpacing)],
                              spacing: DSSpacing.gridSpacing) {
                        ForEach(items) { item in
                            Button {
                                viewerContext = ViewerContext(items: items,
                                                              startItemID: item.id,
                                                              queryKey: "album:\(album.id)")
                            } label: {
                                AlbumThumb(item: item)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeFromAlbum(item)
                                } label: {
                                    Label("移出相簿", systemImage: "rectangle.stack.badge.minus")
                                }
                            }
                            .onAppear {
                                if item.id == items.last?.id { loadMore() }
                            }
                        }
                    }
                    .padding(DSSpacing.gridSpacing)
                    if items.count < total || isLoadingMore {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在加载… \(items.count)/\(total)")
                                .font(.caption)
                                .foregroundColor(Color(ds: DSColor.textSecondary))
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            let repository = AppContainer.shared.assetRepository
            total = await repository.prepare(scope: .album(localIdentifier: album.id))
            guard total > 0 else { return }
            items = await repository.fetch(scope: .album(localIdentifier: album.id),
                                           offset: 0,
                                           limit: Self.pageSize)
        }
        .fullScreenCover(item: $viewerContext) { context in
            ViewerContainer(viewModel: AppContainer.shared.makeViewerViewModel(context: context))
        }
        .overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(ds: DSColor.bgSecondary))
                    .cornerRadius(DSSpacing.cardCornerRadius)
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        self.message = nil
                    }
            }
        }
    }

    /// 触底续拉下一页；去重防重复插入
    private func loadMore() {
        guard !isLoadingMore, !isLoading, items.count < total else { return }
        isLoadingMore = true
        Task { @MainActor in
            defer { isLoadingMore = false }
            let repository = AppContainer.shared.assetRepository
            let next = await repository.fetch(scope: .album(localIdentifier: album.id),
                                              offset: items.count,
                                              limit: Self.pageSize)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: next.filter { !existing.contains($0.id) })
        }
    }

    /// 移出相簿：只移除引用，照片仍在照片库（docs/09 D15）
    private func removeFromAlbum(_ item: PhotoItem) {
        Task { @MainActor in
            do {
                try await AppContainer.shared.photoWriter.remove(ids: [item.id], fromAlbum: album.id)
                items.removeAll { $0.id == item.id }
                message = "已移出相簿"
            } catch {
                message = "移出失败：\(error.localizedDescription)"
            }
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
