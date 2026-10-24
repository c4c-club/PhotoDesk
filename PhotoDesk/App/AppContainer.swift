// MARK: - 职责说明：DI 容器占位（docs/03 §3 App/AppContainer）——服务装配的唯一入口。
// 装配约定（AGENTS.md §3）：Service 全部 protocol 化，ViewModel 经构造器注入，不在 View 层直取单例；
// 纯逻辑一律来自 PhotoDeskCore 本包，本容器只做类型适配，不重复实现（红线 2）。
// 依赖方向：Features → Domain(ViewModel) → Core(Service) → System（docs/03 §1），本容器是组合根。

import Foundation

final class AppContainer {
    /// TODO(P1): 装配 PhotoLibraryServiceProtocol / AssetRepositoryProtocol / ImagePipelineProtocol
    /// TODO(P2): 装配 ViewerVM 的手势管线（SwipeResolverAdapter + UndoCenter + PhotoWriter）
    /// TODO(P3): 装配 TrashBin / VaultService / PersistenceController
    /// TODO(P4): 装配 ScanCoordinator（去重扫描）
}
