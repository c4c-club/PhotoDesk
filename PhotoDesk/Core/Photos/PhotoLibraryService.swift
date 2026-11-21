// MARK: - 职责说明：照片库授权与状态机（docs/05 M1 任务 1.1 / docs/03 §5.6；docs/49 T02 重构）——
// PHPhotoLibrary.requestAuthorization(for: .readWrite)；.limited 必须支持（presentLimitedLibraryPicker 入口），
// .denied 引导前往系统设置。@Published access 驱动根视图状态切换（PermissionIntroView / 网格）。
// T02：statusProvider/requestProvider 构造注入（测试不触真实 PhotoKit）+ refreshAccess 可刷新状态。

import Photos
import PhotosUI   // presentLimitedLibraryPicker(from:) 声明在 PhotosUI 对 PHPhotoLibrary 的扩展里
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
    /// 授权探测（默认读真实 PHPhotoLibrary；测试注入固定值/序列）
    private let statusProvider: () -> PHAuthorizationStatus
    /// 授权请求（默认走真实 requestAuthorization；测试注入固定结果）
    private let requestProvider: () async -> PHAuthorizationStatus

    /// - Parameters:
    ///   - initialAccess: 测试注入固定状态（nil = 读 statusProvider；生产路径不受影响）
    ///   - statusProvider/requestProvider: docs/49 T02 注入点（nil = 真实 PhotoKit）
    init(initialAccess: LibraryAccess? = nil,
         statusProvider: (() -> PHAuthorizationStatus)? = nil,
         requestProvider: (() async -> PHAuthorizationStatus)? = nil) {
        self.statusProvider = statusProvider ?? { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
        self.requestProvider = requestProvider ?? { await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        access = initialAccess ?? Self.map(self.statusProvider())
    }

    /// 触发系统授权弹窗（首次）或返回既有状态；结果发布到 access
    func requestAccess() async {
        let status = await requestProvider()
        await MainActor.run {
            access = Self.map(status)
        }
    }

    /// docs/49 T02 §2.1：重读授权状态；与当前不同则更新并返回最新值（主线程调用）
    @discardableResult
    @MainActor
    func refreshAccess() -> LibraryAccess {
        let latest = Self.map(statusProvider())
        if latest != access {
            access = latest
        }
        return latest
    }

    /// docs/49 T02 §2.1：仅 notDetermined 才触发系统弹窗；其余状态只刷新（denied 不假装成功）
    @MainActor
    func requestAccessIfNeeded() async {
        if access == .notDetermined {
            await requestAccess()
        } else {
            refreshAccess()
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
