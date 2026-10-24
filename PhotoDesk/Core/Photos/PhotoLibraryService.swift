// MARK: - 职责说明：照片库授权与状态机（docs/05 M1 任务 1.1 / docs/03 §5.6）——
// PHPhotoLibrary.requestAuthorization(for: .readWrite)；.limited 必须支持（presentLimitedLibraryPicker 入口），
// .denied 引导前往系统设置。@Published access 驱动根视图状态切换（PermissionIntroView / 网格）。

import Photos
import UIKit

/// 库访问状态（docs/03 §5.6）
enum LibraryAccess: Equatable {
    case notDetermined
    case denied
    case restricted
    case limited
    case authorized
}

final class PhotoLibraryService: ObservableObject {
    /// 当前授权状态（主线程更新）
    @Published private(set) var access: LibraryAccess

    init() {
        access = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// 触发系统授权弹窗（首次）或返回既有状态；结果发布到 access
    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            access = Self.map(status)
        }
    }

    /// .limited：调起系统「管理选中照片」选择器（docs/03 §5.6）；新增/移除经 PhotoChangeObserver 同步
    func presentLimitedLibraryPicker(from viewController: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }

    static func map(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .limited:       return .limited
        case .authorized:    return .authorized
        @unknown default:    return .denied
        }
    }
}
