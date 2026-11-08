# M15 批次5 页面档案（2026-11-09）

## 5. 搜索/筛选 SearchView / SearchViewModel（PhotoDesk/Features/Search/）
- 现状核对：结果计数（resultCount「共 N 项」）✓；空结果「清除筛选」（Search-ClearFilters）✓；应用/重置/回退 ✓。
- 缺口：历史无单条删除。
- 改动：SearchViewModel.removeHistory(at:)（持久化同步）；历史 chip 改为「文本（点按应用）+ ×（单条删除）」复合行。
- 不适用说明：「250ms 防抖」针对文本输入型搜索；本页为 chips/菜单交互（点击即算），无文本输入框，防抖无对象。
- 验收：单条删除后历史持久化正确；其余既有。

## 6. 智能清理 CleanupView（PhotoDesk/Features/Cleanup/CleanupView.swift）
- 现状核对：结果「重新扫描」（Cleanup-Rescan + refreshable）✓；环形进度 ✓。
- 缺口：扫描取消无二次确认；失败原因不可复制。
- 改动：取消按钮改弹 confirmationDialog「取消本次扫描？」（取消扫描/继续扫描）；failed 态加「复制失败原因」（Cleanup-Copy-Failure，UIPasteboard）。
- 验收：取消 <1s 停（既有 cancelScan）；失败可重试可复制。

## 7/24. 整理回顾 SessionReviewView + SessionBadgeView
- SessionReviewView 现状核对：空态 ✓（emptyContent）；计数刷新 ✓（@ObservedObject session）；恢复零 PhotoKit 写 ✓。
- 缺口：全部恢复无二次确认；结果信息不可复制。
- 改动：「全部恢复」弹 confirmationDialog（含张数说明，全部恢复/取消）；resultMessage 行加复制按钮（SessionReview-Copy-Result，复制含失败原因的完整文本）。
- SessionBadgeView：已具备（Button + 待删除/待隐藏计数 + 0 隐藏 + 点击进整理回顾），零改动。

## 13. 手势设置 GestureSettingsView
- 现状核对：动作选择（ActionPickerView up/down）、灵敏度三档 + pt 说明、触觉、撤销窗口、自动前进、恢复默认（带确认）、教学链接、副本开关 ✓。
- 缺口：动作冲突提示；动作预览。
- 改动：两方向动作相同时显示冲突警告（Gesture-Conflict-Hint）；新增「动作预览」Section（↑/↓ 图标 + 动作名 + 即时生效说明）。
- 验收：改动作后查看器立即生效（@AppStorage 实时读取，既有）。

## 14. 隐私与锁定 PrivacyView
- 现状核对：零上传/零分析/零 SDK/删除语义/副本五条声明原文 ✓。
- 缺口：照片权限状态展示与去系统设置入口。
- 改动：新增「照片权限」Section（onAppear 读 PHPhotoLibrary.authorizationStatus(for: .readWrite)，LabeledRow 显示五态中文；.limited 时给「管理可见照片」指引；「去系统设置」按钮 Privacy-Open-Settings）。
- 验收：.limited 用户有明确管理路径；零上传口径未动。

## 21. 引导/权限 PermissionIntroView
- 现状核对：三态文案零上传口径原文 ✓；restricted 已含「管理可见照片」路径说明。
- 缺口：denied 态无直达系统设置按钮。
- 改动：denied 态加「去系统设置」次级按钮（Permission-Open-Settings，openSettingsURLString），主按钮「重新检查授权」保留。
- 验收：拒绝态一键去设置；三态口径未改。

## 22. 最近删除 RecentlyDeletedView
- 现状核对：30 天说明 ✓；photos-redirect 跳系统相册 ✓；无任何删除/清空入口（红线 1 静态检查 0 违规）✓。
- 缺口：无 FAQ。
- 改动：改 ScrollView 布局 + 新增「常见问题」四条（看不到最近删除的原因 / 30 天恢复方法 / 应用内撤销区别 / 不提供彻底删除）。
- 验收：红线 1 不变；FAQ 可滚动不溢出。

## 23. 手势教学 GestureTutorialView
- 现状核对：循环动画 ✓；减弱动态效果 ✓（isReduceMotionEnabled + respectReduceMotion 双闸）。
- 缺口：无可交互练习；「去设置」在未注入 presentSettings 时永久置灰。
- 改动：新增「试一试」练习卡（Tutorial-Practice，DragGesture onEnded 判上/下滑 → 「上滑 → 收藏 ✓ / 下滑 → 隐藏 ✓」反馈 2s 自动消退 + selection 触感）；去设置改 @ViewBuilder（回调注入优先，否则 NavigationLink → GestureSettingsView，工具页/设置页均在 NavigationView 栈内）。
- 验收：练习卡可触发；去设置必可达；循环动画与减弱动效不变。

# 已具备核对记录（零改动）
- 1 照片库网格 / 2 全屏查看器：P0-B/C/D 重做覆盖（Phase 1–3）；复用 cell 选中态复位（PhotoGridCell.prepareForReuse）✓。
- 8 已隐藏 VaultGridView：网格复用 VaultGridView + viewerContext，Phase 批次2 已补门禁页缺口。
- 10 存储统计 StorageStatsView：idle/computing/done(partial)/cancelled 状态机 + 90s 软超时 watchdog + 取消 + unknownCount 脚注 + byYear 柱状图 ✓。
- 15 安全与锁定 SecuritySettingsView：启动锁/保险箱锁/立即锁定/后台宽限 Picker ✓。
- 24 会话徽标 SessionBadgeView：计数实时 + 0 隐藏 + 点击进回顾 ✓。
