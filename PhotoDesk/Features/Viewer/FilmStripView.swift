// MARK: - 职责说明：底部胶片条（docs/05 M2 任务 2.10 / docs/04 §3.2）——
// 横向缩略图 UICollectionView，当前页居中高亮（白描边），点击跳页；显隐随 Viewer chrome 淡出。
// 缩略图经 ImagePipeline（AGENTS.md §3.6：禁止直接 requestImage）。

import UIKit

final class FilmStripView: UIView {
    private var ids: [String] = []
    private var pipeline: ImagePipelineProtocol?
    private var onTap: ((Int) -> Void)?
    private(set) var currentIndex = 0

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = DSSpacing.gridSpacing
        layout.itemSize = CGSize(width: 44, height: 44)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.delegate = self
        view.dataSource = self
        view.register(FilmCell.self, forCellWithReuseIdentifier: FilmCell.reuseID)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    func reload(ids: [String], currentIndex: Int, pipeline: ImagePipelineProtocol, onTap: @escaping (Int) -> Void) {
        self.ids = ids
        self.pipeline = pipeline
        self.onTap = onTap
        self.currentIndex = currentIndex
        collectionView.reloadData()
        highlight(index: currentIndex, centerIfNeeded: true)
    }

    func highlight(index: Int, centerIfNeeded: Bool) {
        guard index != currentIndex || centerIfNeeded else { return }
        currentIndex = index
        collectionView.reloadData()   // 条目小（44pt cell），重载刷新描边最简单；M3 可改 snapshot
        guard centerIfNeeded, index < ids.count else { return }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0),
                                    at: .centeredHorizontally,
                                    animated: true)
    }

    func setThumbnailsHidden(_ hidden: Bool) {
        isHidden = hidden
    }
}

extension FilmStripView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ids.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FilmCell.reuseID,
                                                            for: indexPath) as? FilmCell else {
            return UICollectionViewCell()
        }
        let index = indexPath.item
        cell.isCurrent = (index == currentIndex)
        let id = ids[index]
        cell.load(id: id) { [weak self] completion in
            guard let self else { return }
            Task {
                let image = await self.pipeline?.thumbnail(for: id,
                                                           size: CGSize(width: 44, height: 44),
                                                           scale: UIScreen.main.scale)
                completion(image)
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onTap?(indexPath.item)
    }
}

/// 胶片条小 cell：缩略图 + 当前页白描边
private final class FilmCell: UICollectionViewCell {
    static let reuseID = "FilmCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private var loadToken = 0
    var isCurrent: Bool = false {
        didSet {
            layer.borderWidth = isCurrent ? 2 : 0
            layer.borderColor = UIColor.white.cgColor
            layer.cornerRadius = 4
            layer.masksToBounds = true
            alpha = isCurrent ? 1 : 0.65
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未使用")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken += 1
        imageView.image = nil
    }

    func load(id: String, fetch: @escaping (@escaping (UIImage?) -> Void) -> Void) {
        loadToken += 1
        let token = loadToken
        fetch { [weak self] image in
            guard let self, token == self.loadToken else { return }
            self.imageView.image = image
        }
    }
}
