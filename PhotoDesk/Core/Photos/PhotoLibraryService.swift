// MARK: - 职责说明：照片库授权与状态机（docs/05 M1 任务 1.1）——
// PHPhotoLibrary.requestAuthorization(for: .readWrite)；.limited 必须支持（presentLimitedLibraryPicker 入口），
// .denied 引导前往系统设置（docs/03 §5.6）。协议化供 Mock（AGENTS.md §3.2）。
// TODO(P1): LibraryAccess 状态枚举 + async requestAccess() + 授权状态发布。
