// MARK: - 职责说明：照片库变更监听（docs/05 M1 任务 1.6 / docs/03 §5.3）——
// PHPhotoLibraryChangeObserver 回调在后台线程：在此计算 insert/remove/change 的索引，
// 派发主线程交 ViewModel 做 Diffable 增量更新（禁止整库 reload，AGENTS.md §4.6）。
// 变更后须以 objectAfterChanges 重新 startMonitoring（旧 result 不再推送后续变更）。

import Photos

final class PhotoChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    /// 已解析的增量（主线程回调）
    struct ChangeSet {
        /// 旧索引（含 moved 处理：视作移除）
        let removedIndexes: IndexSet
        /// 旧索引：内容变化（收藏/隐藏标志等），原位替换
        let changedIndexes: IndexSet
        /// 新索引：新插入条目（配 objectAfterChanges 取 PHAsset）
        let insertedIndexes: IndexSet
        let changedObjects: [PHAsset]
        let resultAfterChanges: PHFetchResult<PHAsset>?
    }

    private var monitoredResult: PHFetchResult<PHAsset>?
    private let onChange: (ChangeSet) -> Void

    /// - Parameter onChange: 主线程回调
    init(onChange: @escaping (ChangeSet) -> Void) {
        self.onChange = onChange
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// 开始监听（变更后用新的 result 重新调用即可续听）
    func startMonitoring(result: PHFetchResult<PHAsset>) {
        if monitoredResult == nil {
            PHPhotoLibrary.shared().register(self)
        }
        monitoredResult = result
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let result = monitoredResult,
              let details = changeInstance.changeDetails(for: result) else { return }

        let changeSet = ChangeSet(
            removedIndexes: details.removedIndexes.union(details.movedIndexes),
            changedIndexes: details.changedIndexes,
            insertedIndexes: details.insertedIndexes,
            changedObjects: details.changedObjects,
            resultAfterChanges: details.objectAfterChanges
        )
        DispatchQueue.main.async { [onChange] in
            onChange(changeSet)
        }
    }
}
