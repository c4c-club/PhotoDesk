# M15 批次1 页面档案（2026-11-09）

## 20. 工具页 ToolsView（PhotoDesk/App/ToolsView.swift）
- 现状：入口齐（清理/已隐藏/相簿/最近删除/存储统计/手势教学/设置/诊断）+ Tools-Close/Tools-Close-Bar 关闭按钮已具备。
- 缺口：`.navigationViewStyle(.stack)` 错挂在 List 上（iPad split 隐患，docs/04/AGENTS.md §7）。
- 改动：样式修饰符从 List 移到 NavigationView 链尾（行 90→97 区域）。
- 验收：静态检查 .stack 挂在 NavigationView；Tools-Close 保留；iPad 不 split（UI smoke 手测项）。

## 3. 相簿列表 AlbumsView（PhotoDesk/Features/Albums/AlbumsView.swift）
- 现状：分组列表 + 新建/重命名/删除 + 失败 alert（重试）已有；无封面；计数同步枚举。
- 缺口：FR-D1 封面缺失；无下拉刷新。
- 改动：AlbumSummary 加 coverAssetID（首张 PHAsset，fetchLimit=1 + wantsIncrementalChangeDetails=false 防大相簿全量枚举）；albumRow 改 56x56 AlbumCoverThumb（ImagePipeline.thumbnail，task(id: assetID) 异步加载，空相簿 photo 占位）；标题+计数纵向排版；加 .refreshable。
- 验收：封面可见（UI smoke）；10 个相簿列表不卡主线程（封面 fetchLimit=1）；空态与失败重试保留。

## 4. 相簿详情 AlbumDetailView（PhotoDesk/Features/Albums/AlbumDetailView.swift）
- 现状：一次性 `limit: total` 拉全相簿；空态文案已有；移出失败已有中文原因（message）。
- 缺口：大相簿首屏慢/内存峰值；无分页。
- 改动：pageSize=200；.task 首页加载（total 由 prepare 返回）；ForEach 末项 onAppear 触发 loadMore()（去重 append）；底部「正在加载… N/total」进度行。
- 验收：1000+ 相簿首屏 <1s（200 张首屏）；滚动触底续拉不崩；移出失败原因保留。
