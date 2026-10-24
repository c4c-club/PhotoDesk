// MARK: - 职责说明：沙盒撤销保险副本（docs/03 §5.1，红线 1）——
// 「移到最近删除」执行前必先落盘 ApplicationSupport/_Trash（requestContentEditingInput 取原件，视频走导出），
// 撤销窗口内用 PHAssetCreationRequest.fromImage/fromVideo 重建并恢复 creationDate / location；
// iCloud-only 未下载 → 拒绝执行并提示先下载。副本上限 2GB 按时间淘汰、设置可关闭。
// 定位澄清：它是「撤销保险」不是备份——真正兜底是系统「最近删除」30 天；App 不提供任何永久删除入口。
// TODO(P3): 落盘 / 重建 / 索引（TrashItem）/ 容量淘汰（调 PhotoDeskCore.TrashPolicy）/ 副本清理。
