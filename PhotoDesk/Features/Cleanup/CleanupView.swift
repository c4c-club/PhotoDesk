// MARK: - 职责说明：智能清理（docs/05 M4）——去重 / 相似 / 截图 / 大文件 / 模糊五类卡片 + 环形扫描进度 + 取消 +
// 「待清理清单」二次确认（docs/04 §3.3）。扫描可中断可恢复（ScanSession.cursor）。
// 红线提醒：清理执行同样只做「移到最近删除」，并先落 TrashBin 保险副本。
// TODO(P4): ScanCoordinator 接入 + 扫描 UI + 结果卡片。
