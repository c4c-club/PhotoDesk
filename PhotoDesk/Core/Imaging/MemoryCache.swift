// MARK: - 职责说明：一级缓存——内存 NSCache（docs/03 §5.2：totalCostLimit 60MB、countLimit 500）。
// 收到 didReceiveMemoryWarning 清空；cost 按解码后字节数估算，供 NSCache 淘汰策略使用。

import UIKit

final class MemoryCache {
    static let totalCostLimit = 60 * 1024 * 1024
    static let countLimit = 500

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = Self.totalCostLimit
        cache.countLimit = Self.countLimit
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.clear()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        cache.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    func clear() {
        cache.removeAllObjects()
    }
}
