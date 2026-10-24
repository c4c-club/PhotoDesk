# scripts/test-core.ps1
# 职责说明：本机一键跑完 PhotoDeskCore 的 swift test —— 唯一容器 swift:6.0-noble，用完即弃，不引入任何 Linux 系统（docs/06 §7.2）。
# 用法（PowerShell 或 Git Bash 均可，任意工作目录）：
#   powershell -ExecutionPolicy Bypass -File scripts/test-core.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/test-core.ps1 -Image swift:6.0-noble
# 约定：daemon 不可用时给出明确中文提示；任何失败都以非 0 退出码结束（供本地与 CI 共用）。
param(
    [string]$Image = "swift:6.0-noble"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$coreDir  = Join-Path $repoRoot "PhotoDeskCore"

if (-not (Test-Path (Join-Path $coreDir "Package.swift"))) {
    Write-Host "[X] 未找到 $coreDir\Package.swift —— 请确认在 PhotoDesk 仓库内运行本脚本。" -ForegroundColor Red
    exit 1
}

# 1. docker CLI 可用性
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[X] 未找到 docker 命令。请先安装 Docker Desktop：https://www.docker.com/products/docker-desktop/" -ForegroundColor Red
    exit 1
}

# 2. daemon 可用性（Docker Desktop 应用未启动时 Server 无响应）
$ErrorActionPreference = "Continue"
$serverVersion = docker version --format '{{.Server.Version}}' 2>$null
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($serverVersion)) {
    Write-Host "[X] Docker daemon 不可用（CLI 在但引擎没跑）。" -ForegroundColor Red
    Write-Host "    请先启动 Docker Desktop：开始菜单 -> Docker Desktop，等右下角鲸鱼图标稳定后重试。" -ForegroundColor Yellow
    Write-Host "    验证命令：docker version（Server 部分应有版本号输出）" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Docker daemon 就绪（Server $serverVersion）"

# 3. 镜像就绪（首次运行自动拉取，约 1-2 GB）
docker image inspect $Image *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "..  首次运行：拉取镜像 $Image（视网络需数分钟）..."
    docker pull $Image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] 镜像拉取失败：请检查网络或 Docker 镜像加速配置后重试。" -ForegroundColor Red
        exit 1
    }
}

# 4. 跑测试（--rm 用完即弃；.build 留在宿主机可加速下次构建）
Write-Host "..  运行 swift test（PhotoDeskCore，容器 $Image）..."
docker run --rm -v "${coreDir}:/workspace" -w /workspace $Image swift test
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "[OK] PhotoDeskCore swift test 通过" -ForegroundColor Green
} else {
    Write-Host "[X] swift test 失败（exit $exitCode）" -ForegroundColor Red
}
exit $exitCode
