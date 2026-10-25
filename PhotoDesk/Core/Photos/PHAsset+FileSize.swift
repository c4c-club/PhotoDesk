// MARK: - 职责说明：PHAsset 文件字节获取（docs/05 M4 任务 4.5 大文件检测）——
// 经 PHAssetResource.value(forKey: "fileSize") 读取（社区标准做法，非公开键）。
// 教训：M1 中 PHAsset 的私有 KVC 在 iOS 17.5 直接 crash——此处包 try? 降级为 0，
// 调用方对 size == 0 视为「未知大小」不计入大文件清理。

import Photos

extension PHAsset {
    /// 文件字节数（获取失败返回 0 = 未知）
    var fileSizeBytes: Int64 {
        let resources = PHAssetResource.assetResources(for: self)
        // 视频优先取最高码率资源，图片取原稿
        let resource = resources.first { $0.type == .fullSizePhoto }
            ?? resources.first { $0.type == .photo }
            ?? resources.first { $0.type == .video }
            ?? resources.first
        guard let resource else { return 0 }
        return (try? resource.value(forKey: "fileSize") as? Int64) ?? 0
    }
}
