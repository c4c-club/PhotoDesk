# PhotoDesk 1.4.0 基线审查（2026-11-08T08:44:42+08:00）

## 1. 基线

| 项 | 值 |
|---|---|
| 分支 | fix/p0-20261108 |
| HEAD | bbb94fa9e604f0a978daf61ea70cb0c285062180 |
| 最后提交 | bbb94fa9e604f0a978daf61ea70cb0c285062180 2026-11-08 03:50:29 +0800 docs(m13): docs/21 回填产物 SHA256 双端核对与 26 张截图目视结论 |
| 远端 | https://github.com/c4c-club/PhotoDesk.git |
| 工作树 | 3 个未提交项 |

### 代码规模

| 目录 | Swift 文件 | 行数 |
|---|---:|---:|
| PhotoDesk | 106 | 17270 |
| PhotoDeskCoreSources | 26 | 2130 |
| PhotoDeskTests | 27 | 3794 |
| PhotoDeskUITests | 6 | 2008 |
| PhotoDeskCoreTests | 21 | 2357 |

### 版本

| 键 | 值 |
|---|---|
| MARKETING_VERSION | 1.3.0 |
| CURRENT_PROJECT_VERSION | 4 |
| IPHONEOS_DEPLOYMENT_TARGET | 16.0 |

## 2. 四项 P0 静态取证

### P0-1 捏合崩溃

- 文件：PhotoDesk/Features/Viewer/ZoomableImageCell.swift:510-523
- 结论：**FAIL: 委托回调内仍有几何读取/日志插值**

| 行 | 命中内容 |
|---:|---|
| 511 | `// M12 B2：零 contentSize 时返回 nil——旧版返回零尺寸 view 却允许捏合 →` |
| 513 | `// M13：nil 时写含 contentSize / frame / zoomScale 的 Release 面包屑，便于真机 .ips 还原时序。` |
| 514 | `// 注意：本方法内禁止读 scrollView.zoomScale——UIScrollView 在 delegate 回调内经` |
| 515 | `// _getDelegateZoomView 重入计算 zoomScale，读它会无限递归（绿5 SIGSEGV 实证）；` |
| 517 | `guard scrollView.contentSize.width > 0, scrollView.contentSize.height > 0,` |
| 518 | `zoomContentView.frame.width > 0, zoomContentView.frame.height > 0 else {` |
| 519 | `ViewerTrace.log("viewForZooming nil contentSize=\(scrollView.contentSize) zoomContentView=\(zoomContentView.frame) imageView=\(imageView.frame) zoomScale=\(zoomContentView.transform.a) state=\(zoomTransactionState)")` |

### P0-2 位置记忆

- `positionStore.save(` 调用点：2 处
  - PhotoDesk/Features/Library/LibraryViewController.swift:1180 — `positionStore.save(LibraryPosition(anchorAssetID: item.id,`
  - PhotoDesk/Features/Library/LibraryViewController.swift:1352 — `positionStore.save(LibraryPosition(anchorAssetID: item.id,`
- `viewDidLayoutSubviews` 是否调用恢复入口：**False**
- 结论：**FAIL: 多写入源且布局期无恢复重试**

### P0-3/P0-4 滑动多选

- 结论：**FAIL: 单点命中/依赖 selectedItems**

| 文件:行 | 命中内容 |
|---|---|
| PhotoDesk/Features/Library/SlideSelectGestureController.swift:5 | `// ④ indexPathForItem(at:) + lastProcessedIndexPath 去重；` |
| PhotoDesk/Features/Library/SlideSelectGestureController.swift:114 | `guard let collectionView, let ip = collectionView.indexPathForItem(at: location) else { return }` |
| PhotoDesk/Features/Library/LibraryViewController.swift:675 | `return self.collectionView.indexPathsForSelectedItems ?? []` |

## 3. 测试清单

| 层 | 类数 | 测试函数数 |
|---|---:|---:|
| Core | 22 | 245 |
| iOS | 27 | 187 |
| UI | 6 | 53 |

## 4. 最近 CI

| run id | workflow | status | conclusion | headSha |
|---|---|---|---|---|
| 42402103413 | Build & Test | completed | success | b98931e166d0fc9ee4d2399237145403cbc74425 |
| 42397460320 | Build & Test | completed | failure | 1404211d739a115646c6e2d2a4d36e815d91ad48 |
| 42392672841 | Build & Test | completed | failure | 9d082732e99fe791fc151fee878dbeb984686c6a |
| 42387664152 | Build & Test | completed | failure | 68a4e48cce4f91c13d67db8f7cc47d1742491876 |
| 42386292543 | Build & Test | completed | failure | 9cd15f4bbdaee32d682317eabe0497e2ce0f6054 |

