// MARK: - 职责说明：指纹计算编排（docs/05 M4 任务 4.1）——取 256px 缩略图 → 灰度 → 调 PhotoDeskCore 的 DHash/PHash
// 并写入 Core Data 指纹缓存（algoVersion 变化时标记重算）。纯计算在 PhotoDeskCore（红线 2），本文件只做 Apple 框架适配。
// TODO(P4): 批量指纹计算（TaskGroup maxConcurrent 4 + qos .utility，docs/03 §6）+ 结果持久化。
