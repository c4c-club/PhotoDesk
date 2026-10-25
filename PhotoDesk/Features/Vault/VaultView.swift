// MARK: - 职责说明：保险箱页（docs/05 M3 任务 3.4）——
// 「已隐藏」入口：Face ID / 设备密码门禁（5 分钟宽限；模拟器跳过），解锁后展示 isHidden 资源网格。
// 隐藏资源量级远小于主库，用 SwiftUI LazyVGrid（主网格的 UIKit 管线约束不适用于本页，注释留档）。

import SwiftUI
import PhotoDeskCore

struct VaultView: View {
    @ObservedObject var vault: VaultService
    let repository: AssetRepositoryProtocol
    let pipeline: ImagePipelineProtocol

    @State private var items: [PhotoItem] = []
    @State private var loadFailed = false

    var body: some View {
        Group {
            if vault.isUnlocked {
                gridView
            } else {
                lockView
            }
        }
        .background(Color(ds: DSColor.bgPrimary))
        .navigationTitle("已隐藏")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vault.lock() }
    }

    // MARK: - 门禁页

    private var lockView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(ds: DSColor.textSecondary))
            Text("「已隐藏」相册已锁定")
                .font(.headline)
                .foregroundColor(Color(ds: DSColor.textPrimary))
            Button {
                Task {
                    if await vault.unlock() { await loadHidden() }
                }
            } label: {
                Label("使用 Face ID / 密码解锁", systemImage: "faceid")
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(ds: DSColor.tint))
                    .foregroundColor(.white)
                    .cornerRadius(DSSpacing.buttonCornerRadius)
            }
            if loadFailed {
                Text("无法访问照片，请检查授权")
                    .font(.caption)
                    .foregroundColor(Color(ds: DSColor.accentDelete))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 已隐藏网格

    private var gridView: some View {
        ScrollView {
            if items.isEmpty {
                // docs/04 §7 空态（已隐藏为空）
                VStack(spacing: 8) {
                    Text("这里空空如也")
                        .font(.headline)
                        .foregroundColor(Color(ds: DSColor.textPrimary))
                    Text("在浏览页下滑即可隐藏照片")
                        .font(.subheadline)
                        .foregroundColor(Color(ds: DSColor.textSecondary))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: DSSpacing.gridSpacing)],
                          spacing: DSSpacing.gridSpacing) {
                    ForEach(items) { item in
                        VaultThumb(item: item, pipeline: pipeline)
                    }
                }
                .padding(DSSpacing.gridSpacing)
            }
        }
    }

    private func loadHidden() async {
        do {
            let total = await repository.prepare(scope: .hidden)
            guard total > 0 else { items = []; return }
            items = await repository.fetch(scope: .hidden, offset: 0, limit: total)
        } catch {
            loadFailed = true
        }
    }
}

/// 已隐藏缩略图（进入时异步加载）
private struct VaultThumb: View {
    let item: PhotoItem
    let pipeline: ImagePipelineProtocol
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
            image = await pipeline.thumbnail(for: item.id,
                                             size: CGSize(width: 110, height: 110),
                                             scale: UIScreen.main.scale)
        }
    }
}
