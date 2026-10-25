// MARK: - 职责说明：视频 cell（docs/05 M2 任务 2.8）——
// 静音循环自动播放：进入即起播（automaticallyWaitsToMinimizeStalling = false，300ms 内），
// AVQueuePlayer + AVPlayerLooper 循环；离屏 stopPlayback。资产经 ImagePipeline.videoAsset 提供。

import AVFoundation
import UIKit

final class VideoCell: UICollectionViewCell {
    static let reuseID = "VideoCell"

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var loadToken = 0
    private(set) var itemID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DSColor.bgViewer
        playerLayer.videoGravity = .resizeAspect
        contentView.layer.addSublayer(playerLayer)
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = contentView.bounds
        CATransaction.commit()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken += 1
        stopPlayback()
        itemID = nil
        activityIndicator.stopAnimating()
    }

    /// 拉取资产并起播（provider 由 VM/VC 注入，自管 token 防复用竞态）
    func loadVideo(item: PhotoItem, provider: @escaping () async -> AVAsset?) {
        itemID = item.id
        loadToken += 1
        let token = loadToken
        activityIndicator.startAnimating()
        Task { @MainActor [weak self] in
            guard let self, token == self.loadToken else { return }
            guard let asset = await provider() else {
                self.activityIndicator.stopAnimating()
                return
            }
            guard token == self.loadToken else { return }
            self.startPlayback(asset: asset)
        }
    }

    private func startPlayback(asset: AVAsset) {
        let playerItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true                                  // 静音循环（docs/04 §4.12）
        queuePlayer.automaticallyWaitsToMinimizeStalling = false    // 300ms 内起播
        looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        player = queuePlayer
        playerLayer.player = queuePlayer
        activityIndicator.stopAnimating()
        queuePlayer.play()
    }

    func stopPlayback() {
        player?.pause()
        playerLayer.player = nil
        looper?.disableLooping()
        looper = nil
        player = nil
    }
}
