// MARK: - 职责说明：网格缩略图 cell（docs/04 §3.1）——aspectFill + 圆角 4pt（DSSpacing token）；
// 角标：视频时长（右下）、Live（左上）、截图（右下图标）；经 ImagePipeline 取图（禁止直接 requestImage），
// 离屏由 VC 调 cancelLoad()；复用竞态用 token 防过期回填。

import UIKit
import Photos

final class PhotoGridCell: UICollectionViewCell {
    private enum ReuseToken {
        static let photo = "PhotoGridCell.photo"
    }

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    /// iCloud-only 占位（docs/04 §4.13：云图标 + 下载按钮 M2 接线）
    private let cloudBadge: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "icloud"))
        view.tintColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = DSTypography.font(.badge)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    private let liveBadge: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "livephoto"))
        view.tintColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    private let screenshotBadge: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "camera.viewfinder"))
        view.tintColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private var loadTask: Task<Void, Never>?
    private var configureToken = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = DSSpacing.gridCornerRadius
        contentView.backgroundColor = DSColor.bgSecondary
        contentView.addSubview(imageView)
        contentView.addSubview(cloudBadge)
        contentView.addSubview(liveBadge)
        contentView.addSubview(screenshotBadge)
        contentView.addSubview(durationLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            cloudBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cloudBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),

            liveBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            liveBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),

            screenshotBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            screenshotBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            durationLabel.heightAnchor.constraint(equalToConstant: 14),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
        ])
        isAccessibilityElement = true
        accessibilityTraits = [.image, .button]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用（纯代码 cell）")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad()
        imageView.image = nil
        updateBadges(item: nil)
    }

    /// VC 在 didEndDisplaying 调用：取消在途加载（AGENTS.md §3.6 cell 离屏取消）
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        configureToken += 1
    }

    // MARK: - 配置

    func configure(item: PhotoItem, pipeline: ImagePipelineProtocol, pixelSize: CGSize) {
        configureToken += 1
        let token = configureToken
        updateBadges(item: item)
        accessibilityLabel = Self.accessibilityLabel(for: item)

        imageView.image = nil
        let id = item.id
        loadTask = Task { [weak self] in
            // pixelSize 已是像素尺寸：以 scale=1 传入，保证缓存键与预取一致
            let image = await pipeline.thumbnail(for: id, size: pixelSize, scale: 1)
            guard !Task.isCancelled, let self, token == self.configureToken else { return }
            self.imageView.image = image
            self.cloudBadge.isHidden = !(image == nil && item.isCloudOnly)
        }
    }

    private func updateBadges(item: PhotoItem?) {
        guard let item else {
            [durationLabel, liveBadge, screenshotBadge, cloudBadge].forEach { $0.isHidden = true }
            return
        }
        if item.mediaType == .video {
            durationLabel.isHidden = false
            durationLabel.text = Self.durationText(item.duration)
        } else {
            durationLabel.isHidden = true
        }
        liveBadge.isHidden = !item.mediaSubtypes.contains(.photoLive)
        screenshotBadge.isHidden = !(item.mediaType == .image && item.mediaSubtypes.contains(.photoScreenshot))
    }

    // MARK: - helpers

    static func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// VoiceOver（docs/04 §6）：「照片，2026年10月3日，已收藏」
    static func accessibilityLabel(for item: PhotoItem) -> String {
        var parts: [String] = [item.mediaType == .video ? "视频" : "照片"]
        if let date = item.creationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年M月d日"
            parts.append(formatter.string(from: date))
        }
        if item.isFavorite { parts.append("已收藏") }
        return parts.joined(separator: "，")
    }
}
