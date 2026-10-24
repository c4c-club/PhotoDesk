// MARK: - 职责说明：Core Data 栈（docs/03 §4.2 实体：Fingerprint / DuplicateGroup / ActionLog / TrashItem / ScanSession / OCRText）。
// 写走 performBackgroundTask、主线程只读 viewContext（AGENTS.md §3.5）；无 App Groups，库放默认沙盒（docs/06 §4.1）。
// 索引：Fingerprint.createdAt / ActionLog.expiresAt / TrashItem.createdAt；首版轻量迁移。
// TODO(P3): NSPersistentContainer 装配 + PhotoDesk.xcdatamodeld + Repositories。
