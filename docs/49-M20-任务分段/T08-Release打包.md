# T08 — Release 打包

> 依赖：T07。状态：⬜。预计：0.5d。
> 只读：00-索引、本卡；可读 T07 的 CI 结果、project.yml、docs/05、已有 release 目录。不要读其他卡。

## 1. 目标

产出 PhotoDesk 1.9.0 (10) 未签名 IPA，校验路径/SHA256/结构，写发布记录，并向用户报告绝对路径、SHA256、CI run id。真机安装若不可用，明确 BLOCKED。

## 2. 版本与产物

- project.yml：
  - MARKETING_VERSION: 1.9.0
  - CURRENT_PROJECT_VERSION: 10
- 目标产物：
  - artifacts/release/1.9.0/PhotoDesk-1.9.0-build10-unsigned.ipa
- 同时保留：
  - PhotoDesk-1.9.0-build10-unsigned.ipa.sha256
  - artifacts/release/1.9.0/RELEASE.md（发布记录）

## 3. 执行步骤

1. 修改 project.yml 版本号；确认 Info.plist 权限文案未变。
2. commit：chore(release): 1.9.0 (10)。
3. 推送并触发 GitHub Actions 全量 run（workflow_dispatch 或 push）。
4. 等待 build job 完成；记录 run id。
5. 下载 artifact（未签名 ipa 与 sha256）：
   - 优先 gh run download <run-id> -n PhotoDesk-unsigned-ipa；
   - 无 gh 时用 GitHub UI/API 下载，记录使用的通道；
   - 不要从旧 run 拿错包。
6. 解压/复制到 artifacts/release/1.9.0/，重命名为 PhotoDesk-1.9.0-build10-unsigned.ipa。
7. 校验：
   - 文件存在、字节数 > 0；
   - Get-FileHash -Algorithm SHA256 与 CI .sha256 一致；
   - unzip -l 包含 Payload/PhotoDesk.app/PhotoDesk；
   - Info.plist MinimumOSVersion = 16.0；
   - otool minos = 16.0（CI 已校验，记录输出）；
   - codesign 确认未签名。
8. 写 artifacts/release/1.9.0/RELEASE.md：
   - 版本/build、commit、CI run id、artifact 名；
   - 绝对路径、字节数、SHA256；
   - 修复内容三条；
   - 测试结果（Core / iOS / UI 矩阵）；
   - 已知 BLOCKED（真机安装/性能）。
9. 更新 docs/05 变更日志与 progress-m20 T08。
10. 最终报告给用户：
    - IPA 绝对路径；
    - SHA256；
    - CI run id；
    - 是否真机安装（BLOCKED 原因）；
    - 不夸大：未真机验证就写未验证。

## 4. 验收

- IPA 路径固定为 artifacts/release/1.9.0/PhotoDesk-1.9.0-build10-unsigned.ipa。
- SHA256 与 CI 一致，字节数记录。
- 包内 MinimumOSVersion / minos = 16.0。
- 未签名；无第三方依赖；无永久删除。
- RELEASE.md 与 docs/05 更新。
- 用户能在 Windows 上用 AltServer 找到该文件。

## 5. BLOCKED 处理

- 无 GitHub 凭据 / 无 gh：记录下载通道与限制，不伪造 run id。
- 无 iPhone/AltServer：标注「真机安装 BLOCKED（设备不可用）」，不要写「已安装」。
- CI 失败：不得发布；回到 T07 修复后重跑。

## 6. 完成

M20 完成。最终回复必须包含短启动提示词的用途说明（见 docs/50）与本轮规划未产出 IPA 的事实。
