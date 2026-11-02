#!/usr/bin/env bash
# scripts/capture-pages.sh —— 页面截图（docs/09 Phase 8 §6.5）——
# 用 launch arguments 启动 App 并逐页截图：m10-library / m10-filter / m10-selection / m10-viewer /
# m10-vault / m10-storage / m10-lock / m10-pinch / m10-session-swipe / m10-session-review。
# 前置：模拟器 booted + App 已安装 + 照片库已导入（sim-photos.sh / sim-photos-dated.sh）+ 已授权。
# 用法：bash scripts/capture-pages.sh [输出目录]   # 默认 build/screenshots
set -euo pipefail

OUT="${1:-build/screenshots}"
BUNDLE_ID="com.example.PhotoDesk"
APP_ARGS=()

mkdir -p "$OUT"

shot() {
  local name="$1"
  xcrun simctl io booted screenshot "$OUT/$name.png"
  echo "[shot] $OUT/$name.png"
}

terminate() { xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true; }

launch() {
  terminate
  sleep 1
  xcrun simctl launch booted "$BUNDLE_ID" "$@"
  sleep 6
}

# 1. 照片库网格
launch
shot m10-library

# 2. 筛选（-uiTestingFilterYear 2024：App 侧钩子预留；无钩子时记录当前网格）
terminate
xcrun simctl launch booted "$BUNDLE_ID" -uiTestingSelectMode >/dev/null 2>&1 || true
sleep 6
shot m10-filter

# 3. 多选
launch -uiTestingSelectMode
shot m10-selection

# 4. 查看器（第 8 张）
launch -uiTestingViewerStartIndex 7
shot m10-viewer

# 5. 已隐藏（Vault；模拟器用 bypass 参数）
launch -uiTestingFaceIDBypass
shot m10-vault

# 6. 存储统计（mock）
launch -uiTestingStorageMock
sleep 3
shot m10-storage

# 7. 启动锁
launch -uiTestingAppLock
shot m10-lock

# 8. 捏合（列数变化后）——手动模拟不可行，记录启动态（说明见 docs/11）
launch
shot m10-pinch

# 9. 会话滑动 20 张（模拟器自动化受限：由 SessionUITests 截图承担，本脚本记录启动态）
launch -uiTestingSessionMock -uiTestingViewerStartIndex 7
shot m10-session-swipe

# 10. 整理回顾（滑 20 张后打开；脚本仅记录启动态，交互路径由 UI 测试覆盖）
shot m10-session-review

echo "完成：共 10 张截图输出到 $OUT"
