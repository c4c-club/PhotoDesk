# M15 批次4 页面档案（2026-11-09）

## 12. 外观与网格 AppearanceSettingsView（PhotoDesk/Features/Settings/）
- 现状：位置记忆文案已改「本机文件（Application Support）」（Phase 2 完成）；列数 Stepper 即时生效（@AppStorage grid.columns 双向绑定）。
- 缺口：列数无即时预览；无恢复默认。
- 改动：新增 GridColumnsPreview（3 行 × N 列示意块，跟随 Stepper 变化，AX label）；「恢复默认网格」按钮（Settings-Grid-Reset，columns=3 + sortAsc=false + selection 触感）。
- 验收：2–5 列预览即时刷新、重启保持（@AppStorage）；恢复默认一键回位。

## 18. 信息面板 MetadataView（PhotoDesk/Features/Metadata/MetadataView.swift）
- 现状：尺寸/大小/格式/EXIF（设备/镜头/光圈/快门/ISO/焦距/闪光灯）/GPS 小地图/复制全部/textSelection 已有；格式 "—"、大小「未知」空态文案已有。
- 缺口：文件名未展示；无分享；EXIF 解析无加载态。
- 改动：新增 filename 状态（PHAssetResource.originalFilename）+ 基本信息「文件名」行；新增 isLoadingEXIF（相机 Section 加载中显示 ProgressView「正在读取 EXIF…」，完成后展示或无 EXIF 文案）；复制/分享统一 allInfoText（含文件名），toolbar 加 ShareLink（iOS 16 API，Metadata-Share）。
- 验收：文件名可见；EXIF 加载态不闪烁；坏图/无 EXIF 显示占位不崩（既有 + defer 复位）。

## 19. 编辑器 EditorViewController / EditorViewModel（PhotoDesk/Features/Editor/）
- 现状：裁剪比例 chips（CropAspectRatio.presets）、旋转/翻转/重置（geometryBar）、保存防连点（isSaving 门禁 + setSaving 禁用双按钮）、覆盖确认、还原确认、失败中文提示均已具备。
- 缺口：未保存离开无二次确认。
- 改动：EditorViewModel 新增 hasEdits（transform != EditorTransform() || adjustments != .neutral，两者均 Equatable）；EditorViewController closeTapped 拦截：hasEdits 且未保存成功 → UIAlertController「放弃未保存的编辑？」（继续编辑/放弃并关闭）；suppressCloseConfirm 标记（另存/覆盖成功后自动关闭跳过确认）。
- 验收：改过任意调整后关闭弹确认；保存成功后关闭不重复弹；未改动直接关。
