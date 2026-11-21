T08 验收证据：模拟器 iOS 16.4 + minos=16.0

- project.yml:16 `IPHONEOS_DEPLOYMENT_TARGET: 16.0`（T01 审查存档；未改动）
- CI（macos-15 + Xcode 16.4）build log 显示 IPHONEOS_DEPLOYMENT_TARGET = 16.0、
  `-destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=16.4'`（ios.yml 常量，
  见各 run 的 mig-build.log 构建行）
- 本机无 macOS/otool（AGENTS.md §1 构建方案锁定），LC_BUILD_VERSION 校验由 CI 的
  Verify deployment target 步骤执行（ios.yml `Verify deployment target`：echo minos 校验）
- 证据文件：artifacts/ci-evidence/m19-t08/<run-id>/mig-build.log 中
  `Verify deployment target` 步骤输出
