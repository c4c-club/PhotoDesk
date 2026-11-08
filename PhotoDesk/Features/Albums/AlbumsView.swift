// MARK: - 职责说明：相簿列表（docs/05 M3 任务 3.6 / docs/04 §2 工具页）——
// 系统相簿分组浏览（用户相簿 / 智能相簿）+ 新建 / 重命名 / 删除（写操作经 PhotoWriter.performChanges）。
// 相簿内容页复用缩略图组件展示（隐藏资源量级小，LazyVGrid 足够；主库网格管线约束不在此页）。

import SwiftUI
import Photos

struct AlbumsView: View {
    @State private var userAlbums: [AlbumSummary] = []
    @State private var smartAlbums: [AlbumSummary] = []
    @State private var showEditor = false
    @State private var editorTitle = ""
    /// 非 nil = 重命名该相簿；nil = 新建
    @State private var renamingAlbum: AlbumSummary?
    /// 新建/重命名/删除失败的中文提示（禁止 try? 静默吞掉写操作错误）
    @State private var errorMessage: String?

    struct AlbumSummary: Identifiable {
        let id: String       // localIdentifier
        let title: String
        let count: Int
        /// 相簿首张照片的 assetID（封面缩略图；空相簿为 nil）
        var coverAssetID: String?
    }

    var body: some View {
        List {
            Section("我的相簿") {
                if userAlbums.isEmpty {
                    Text("暂无相簿，点右上角 + 新建")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                ForEach(userAlbums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        albumRow(album)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteAlbum(album)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            renamingAlbum = album
                            editorTitle = album.title
                            showEditor = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(Color(ds: DSColor.tint))
                    }
                }
            }
            Section("智能相簿") {
                ForEach(smartAlbums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        albumRow(album)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("相簿")
        .refreshable { reload() }
        .toolbar {
            Button {
                renamingAlbum = nil
                editorTitle = ""
                showEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建相簿")
        }
        .background(
            AlertWithTextField(isPresented: $showEditor,
                               title: renamingAlbum == nil ? "新建相簿" : "重命名相簿",
                               placeholder: "相簿名称",
                               initialText: renamingAlbum?.title ?? editorTitle,
                               actionTitle: renamingAlbum == nil ? "创建" : "完成") { title in
                editorTitle = title
                commitEditor()
            }
        )
        .onAppear(perform: reload)
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("重试", role: .cancel) { reload() }
            Button("好", role: .destructive) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func albumRow(_ album: AlbumSummary) -> some View {
        HStack(spacing: 12) {
            AlbumCoverThumb(assetID: album.coverAssetID)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .foregroundColor(Color(ds: DSColor.textPrimary))
                Text("\(album.count) 张")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.textSecondary))
            }
            Spacer()
        }
    }

    // MARK: - 数据

    private func reload() {
        userAlbums = fetchSummaries(type: .album)
        smartAlbums = fetchSummaries(type: .smartAlbum)
            .filter { $0.count > 0 && $0.title != "Recently Deleted" && $0.title != "最近删除" }
    }

    private func fetchSummaries(type: PHAssetCollectionType) -> [AlbumSummary] {
        let result = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
        var summaries: [AlbumSummary] = []
        result.enumerateObjects { collection, _, _ in
            // 系统空智能相簿（如「个人收藏」空时）PhotoKit 仍返回——count 为 0 的过滤掉
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            // 封面取首张；fetchLimit 1 避免大相簿全量枚举
            let firstOptions = PHFetchOptions()
            firstOptions.fetchLimit = 1
            firstOptions.wantsIncrementalChangeDetails = false
            let cover = PHAsset.fetchAssets(in: collection, options: firstOptions).firstObject
            summaries.append(AlbumSummary(id: collection.localIdentifier,
                                          title: collection.localizedTitle ?? "未命名",
                                          count: assets.count,
                                          coverAssetID: cover?.localIdentifier))
        }
        return summaries
    }

    // MARK: - 写操作

    private func commitEditor() {
        let title = editorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task { @MainActor in
            let writer = AppContainer.shared.photoWriter
            do {
                if let target = renamingAlbum {
                    try await writer.renameAlbum(localID: target.id, to: title)
                } else {
                    _ = try await writer.createAlbum(title: title)
                }
                renamingAlbum = nil
                reload()
            } catch {
                errorMessage = "保存相簿失败：\(error.localizedDescription)"
            }
        }
    }

    private func deleteAlbum(_ album: AlbumSummary) {
        Task { @MainActor in
            do {
                try await AppContainer.shared.photoWriter.deleteAlbum(localID: album.id)
                reload()
            } catch {
                errorMessage = "删除相簿失败：\(error.localizedDescription)"
            }
        }
    }
}

/// 相簿封面缩略图（首张照片，走 ImagePipeline；空相簿显示占位图标）
private struct AlbumCoverThumb: View {
    let assetID: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(ds: DSColor.bgSecondary))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(Color(ds: DSColor.textSecondary))
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: DSSpacing.gridCornerRadius))
        .task(id: assetID) {
            image = nil
            guard let assetID else { return }
            image = await AppContainer.shared.imagePipeline.thumbnail(
                for: assetID,
                size: CGSize(width: 56, height: 56),
                scale: UIScreen.main.scale)
        }
    }
}
