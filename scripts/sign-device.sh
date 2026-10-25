#!/usr/bin/env bash
# scripts/sign-device.sh —— 真机自签名出包（docs/06 §4.3；在 macOS 上运行——本机为 Windows 时
# 由 GitHub Actions macos runner 或未来云 Mac 执行；Windows 主路径仍是「CI 未签名 ipa + AltServer」docs/06 §7.3 路径 A）。
# 用法：
#   TEAM_ID=你的TeamID bash scripts/sign-device.sh     # Team ID 从环境变量注入，不入库（AGENTS.md §1）
# 输出：build/ipa/PhotoDesk.ipa（已签名 development 包）

set -euo pipefail

TEAM="${TEAM_ID:?请先 export TEAM_ID=你的TeamID（Apple 开发者账号 Membership 页可查）}"
BUNDLE="com.example.PhotoDesk"
SCHEME="PhotoDesk"
DEVICE_DEST='generic/platform=iOS'

command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate

mkdir -p build
xcodebuild \
  -project PhotoDesk.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DEVICE_DEST" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
  -derivedDataPath build/DerivedData \
  -archivePath build/PhotoDesk.xcarchive \
  archive

cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>TEAM_PLACEHOLDER</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
PLIST
sed -i '' "s/TEAM_PLACEHOLDER/$TEAM/" build/ExportOptions.plist

xcodebuild -exportArchive \
  -archivePath build/PhotoDesk.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist build/ExportOptions.plist

echo "已签名 ipa：build/ipa/PhotoDesk.ipa（7 天有效期，付费账号可走 docs/06 §7.3 路径 B 全自动签名）"
