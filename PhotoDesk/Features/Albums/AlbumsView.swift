// MARK: - 职责说明：相簿列表（docs/05 M3 任务 3.6 / docs/04 §2 工具页）——
// 系统相簿分组浏览（用户相簿 / 智能相簿）+ 新建 / 重命名 / 删除（写操作经 PhotoWriter.performChanges）。
// M17 T08 X01/X02：查询/计数/封面下沉 AlbumService，列表增量刷新；本页只消费 [AlbumSummary]。
// 相簿内容页复用缩略图组件展示（隐藏资源量级小，LazyVGrid 足够；主库网格管线约束不在此页）。

import SwiftUI

struct AlbumsView: View {
    @StateObject private var viewModel: AlbumsViewModel
    @State private var showEditor = false
    @State private var editorTitle = ""
    /// 非 nil = 重命名该相簿；nil = 新建
    @State private var renamingAlbum: AlbumSummary?

    init() {
        _viewModel = StateObject(wrappedValue: AlbumsViewModel(service: AppContainer.shared.albumService))
    }

    var body: some View {
        List {
            Section("我的相簿") {
                if viewModel.userAlbums.isEmpty {
                    Text("暂无相簿，点右上角 + 新建")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                ForEach(viewModel.userAlbums) { album in
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
                ForEach(viewModel.smartAlbums) { album in
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
        .refreshable { await viewModel.reload() }
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
        .onAppear { Task { await viewModel.reload() } }
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("重试", role: .cancel) { Task { await viewModel.reload() } }
            Button("好", role: .destructive) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                await viewModel.reload()
            } catch {
                viewModel.errorMessage = "保存相簿失败：\(error.localizedDescription)"
            }
        }
    }

    private func deleteAlbum(_ album: AlbumSummary) {
        Task { @MainActor in
            do {
                try await AppContainer.shared.photoWriter.deleteAlbum(localID: album.id)
                await viewModel.reload()
            } catch {
                viewModel.errorMessage = "删除相簿失败：\(error.localizedDescription)"
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
