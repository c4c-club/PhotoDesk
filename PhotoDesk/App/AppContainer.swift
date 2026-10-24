// MARK: - 职责说明：DI 组合根（docs/03 §3 App/AppContainer）——服务装配唯一入口。
// 装配约定（AGENTS.md §3）：Service 全部 protocol 化，ViewModel 经构造器注入；纯逻辑来自 PhotoDeskCore（红线 2）。
// 依赖方向：Features → Domain(ViewModel) → Core(Service) → System（docs/03 §1），本容器是组合根。
// @MainActor：App/UI 侧组合发生在主线程。

import Foundation

@MainActor
final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    let settings = SettingsStore()
    let libraryService = PhotoLibraryService()
    let assetRepository: AssetRepositoryProtocol
    let imagePipeline: ImagePipelineProtocol

    lazy var libraryViewModel = LibraryViewModel(service: libraryService,
                                                 repository: assetRepository,
                                                 pipeline: imagePipeline)

    private init() {
        assetRepository = AssetRepository()
        // 捕获 settings 实例本身（不能引用 AppContainer.shared：静态 let 初始化进行中会死锁）
        let settingsRef = settings
        imagePipeline = ImagePipeline(allowsNetworkAccess: { settingsRef.autoDownloadOriginal })
    }
}
