#!/usr/bin/env bash
# scripts/build-sim.sh —— 模拟器构建与运行（docs/06 §3）。在 macOS / CI 上执行（Windows 本机无 Xcode，不走此脚本）。
# 用法：bash scripts/build-sim.sh [设备名] [运行时]
set -euo pipefail
SCHEME=PhotoDesk
DEVICE_NAME="${1:-iPhone 13}"
RUNTIME="${2:-iOS-15-5}"

xcrun simctl list runtimes                       # 确认 iOS 15.5 runtime 已下载
xcodebuild \
  -project PhotoDesk.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=15.5" \
  -derivedDataPath build/DerivedData \
  build

APP=$(find build/DerivedData/Build/Products -name "*.app" -maxdepth 3 | head -1)
xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.example.PhotoDesk
