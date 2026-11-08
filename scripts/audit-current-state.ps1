# scripts/audit-current-state.ps1
# 职责说明：PhotoDesk 1.4.0 P0 审查（docs/22 §1.3 / §2）——只读扫描仓库真实基线，
# 输出 artifacts/audit/<date>/audit.md + audit.json；任何被引用文件缺失即非 0 退出，
# 禁止静默跳过（旧审查脚本引用了不存在的路径一律不复用）。

param(
    [string]$OutDir = "artifacts/audit/2026-11-08"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

# ---- 0. 必需文件清单（缺失即过期） ----
$required = @(
    "PhotoDesk/Features/Viewer/ZoomableImageCell.swift",
    "PhotoDesk/Features/Viewer/ViewerViewController.swift",
    "PhotoDesk/Features/Library/LibraryViewController.swift",
    "PhotoDesk/Features/Library/LibraryContainer.swift",
    "PhotoDesk/Features/Library/LibraryViewModel.swift",
    "PhotoDesk/Features/Library/SlideSelectGestureController.swift",
    "PhotoDesk/Core/Support/LibraryPositionStore.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/SelectionPolicy.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/SlideSelectPolicy.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/PositionAnchorV3.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/ZoomGeometry.swift",
    "PhotoDeskTests",
    "PhotoDeskUITests",
    "PhotoDeskCore/Tests",
    "project.yml",
    ".github/workflows/ios.yml"
)
$missing = @($required | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) {
    Write-Host "[X] 审查脚本已过期，请先重写：以下路径不存在：" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    exit 2
}

# ---- 1. 仓库基线 ----
$branch = (git branch --show-current).Trim()
$head = (git rev-parse HEAD).Trim()
$status = @(git status --porcelain)
$remote = (git remote get-url origin).Trim()
$lastCommit = (git log -1 --format='%H %ci %s').Trim()

foreach ($cmd in @("git branch --show-current", "git rev-parse HEAD", "git remote get-url origin")) {
    if ($LASTEXITCODE -ne 0) { Write-Host "[X] 命令失败：$cmd" -ForegroundColor Red; exit 3 }
}

# ---- 2. 代码规模 ----
function Count-Swift([string]$path) {
    if (-not (Test-Path $path)) { return [pscustomobject]@{ files = 0; lines = 0 } }
    $files = @(Get-ChildItem $path -Recurse -Filter *.swift -File)
    $lines = 0
    foreach ($f in $files) { $lines += @(Get-Content $f.FullName).Count }
    return [pscustomobject]@{ files = $files.Count; lines = $lines }
}
$scale = [ordered]@{
    PhotoDesk            = Count-Swift "PhotoDesk"
    PhotoDeskCoreSources = Count-Swift "PhotoDeskCore/Sources"
    PhotoDeskTests       = Count-Swift "PhotoDeskTests"
    PhotoDeskUITests     = Count-Swift "PhotoDeskUITests"
    PhotoDeskCoreTests   = Count-Swift "PhotoDeskCore/Tests"
}

# ---- 3. P0-1：viewForZooming 方法体 ----
$zoomFile = "PhotoDesk/Features/Viewer/ZoomableImageCell.swift"
$zoomLines = @(Get-Content $zoomFile)
$zoomStart = -1; $zoomEnd = -1
for ($i = 0; $i -lt $zoomLines.Count; $i++) {
    if ($zoomLines[$i] -match 'func\s+viewForZooming\s*\(') { $zoomStart = $i; break }
}
if ($zoomStart -ge 0) {
    $depth = 0; $opened = $false
    for ($i = $zoomStart; $i -lt $zoomLines.Count; $i++) {
        $line = $zoomLines[$i]
        $depth += ([regex]::Matches($line, '\{')).Count
        $depth -= ([regex]::Matches($line, '\}')).Count
        if ($depth -gt 0) { $opened = $true }
        if ($opened -and $depth -le 0) { $zoomEnd = $i; break }
    }
}
$zoomBody = if ($zoomStart -ge 0 -and $zoomEnd -ge $zoomStart) {
    $zoomLines[$zoomStart..$zoomEnd] -join "`n"
} else { "" }
$zoomHits = @()
if ($zoomBody) {
    $offset = $zoomStart
    foreach ($line in $zoomLines[$zoomStart..$zoomEnd]) {
        $offset++
        if ($line -match 'contentSize|\.frame|zoomScale|ViewerTrace|\\\(') {
            $zoomHits += [pscustomobject]@{ line = $offset; text = $line.Trim() }
        }
    }
}

# ---- 4. P0-2：位置保存调用点 / 恢复入口 ----
$libraryFile = "PhotoDesk/Features/Library/LibraryViewController.swift"
$libraryLines = @(Get-Content $libraryFile)
$saveCalls = @()
for ($i = 0; $i -lt $libraryLines.Count; $i++) {
    if ($libraryLines[$i] -match 'positionStore\.save\(') {
        $saveCalls += [pscustomobject]@{ line = $i + 1; text = $libraryLines[$i].Trim() }
    }
}
$layoutStart = -1; $layoutEnd = -1
for ($i = 0; $i -lt $libraryLines.Count; $i++) {
    if ($libraryLines[$i] -match 'override\s+func\s+viewDidLayoutSubviews') { $layoutStart = $i; break }
}
if ($layoutStart -ge 0) {
    $depth = 0; $opened = $false
    for ($i = $layoutStart; $i -lt $libraryLines.Count; $i++) {
        $depth += ([regex]::Matches($libraryLines[$i], '\{')).Count
        $depth -= ([regex]::Matches($libraryLines[$i], '\}')).Count
        if ($depth -gt 0) { $opened = $true }
        if ($opened -and $depth -le 0) { $layoutEnd = $i; break }
    }
}
$layoutBody = if ($layoutStart -ge 0 -and $layoutEnd -ge $layoutStart) {
    $libraryLines[$layoutStart..$layoutEnd] -join "`n"
} else { "" }
$layoutCallsRestore = $layoutBody -match 'restorePositionIfNeeded|attemptRestore'

# ---- 5. P0-3：滑选单点命中 ----
$slideFile = "PhotoDesk/Features/Library/SlideSelectGestureController.swift"
$slideLines = @(Get-Content $slideFile)
$slideSinglePoint = @()
for ($i = 0; $i -lt $slideLines.Count; $i++) {
    if ($slideLines[$i] -match 'indexPathForItem\(at:|indexPathsForSelectedItems') {
        $slideSinglePoint += [pscustomobject]@{ file = $slideFile; line = $i + 1; text = $slideLines[$i].Trim() }
    }
}
$libSelectedItems = @()
for ($i = 0; $i -lt $libraryLines.Count; $i++) {
    if ($libraryLines[$i] -match 'indexPathsForSelectedItems') {
        $libSelectedItems += [pscustomobject]@{ file = $libraryFile; line = $i + 1; text = $libraryLines[$i].Trim() }
    }
}

# ---- 6. 测试函数枚举 ----
function Get-TestInventory([string]$path) {
    $files = @(Get-ChildItem $path -Recurse -Filter *.swift -File -ErrorAction SilentlyContinue)
    $classes = @(); $tests = @()
    foreach ($f in $files) {
        $lines = Get-Content $f.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'class\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase') {
                $classes += [pscustomobject]@{ file = $f.FullName.Replace($RepoRoot + '\', ''); line = $i + 1; name = $Matches[1] }
            }
            if ($lines[$i] -match 'func\s+(test[A-Za-z0-9_]+)\s*\(') {
                $tests += [pscustomobject]@{ file = $f.FullName.Replace($RepoRoot + '\', ''); line = $i + 1; name = $Matches[1] }
            }
        }
    }
    return [pscustomobject]@{ classes = $classes; tests = $tests }
}
$coreTests = Get-TestInventory "PhotoDeskCore/Tests"
$iosTests = Get-TestInventory "PhotoDeskTests"
$uiTests = Get-TestInventory "PhotoDeskUITests"

# ---- 7. project.yml ----
$projectText = Get-Content "project.yml" -Raw
function Get-YamlValue([string]$key) {
    $m = [regex]::Match($projectText, "(?m)^\s*$key\s*:\s*`"?([^`"\r\n]+)`"?")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}
$versions = [ordered]@{
    MARKETING_VERSION       = Get-YamlValue "MARKETING_VERSION"
    CURRENT_PROJECT_VERSION = Get-YamlValue "CURRENT_PROJECT_VERSION"
    IPHONEOS_DEPLOYMENT_TARGET = Get-YamlValue "IPHONEOS_DEPLOYMENT_TARGET"
}

# ---- 8. 最近 CI ----
$runs = @()
try {
    $json = gh run list --limit 5 --json databaseId,conclusion,headSha,status,workflowName,createdAt 2>$null
    if ($LASTEXITCODE -eq 0 -and $json) { $runs = @($json | ConvertFrom-Json) }
} catch { $runs = @() }

# ---- 9. 汇总 ----
$p0 = [ordered]@{
    P0_1_viewForZooming = [ordered]@{
        file = $zoomFile; startLine = if ($zoomStart -ge 0) { $zoomStart + 1 } else { $null }
        endLine = if ($zoomEnd -ge 0) { $zoomEnd + 1 } else { $null }
        forbiddenHits = $zoomHits
        verdict = if ($zoomHits.Count -gt 0) { "FAIL: 委托回调内仍有几何读取/日志插值" } else { "PASS" }
    }
    P0_2_position = [ordered]@{
        positionStoreSaveCalls = $saveCalls
        viewDidLayoutSubviewsCallsRestore = $layoutCallsRestore
        verdict = if ($saveCalls.Count -gt 1 -and -not $layoutCallsRestore) { "FAIL: 多写入源且布局期无恢复重试" } else { "CHECK" }
    }
    P0_3_slideSelect = [ordered]@{
        singlePointHits = @($slideSinglePoint + $libSelectedItems)
        verdict = if (@($slideSinglePoint).Count -gt 0 -or @($libSelectedItems).Count -gt 0) { "FAIL: 单点命中/依赖 selectedItems" } else { "PASS" }
    }
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    repo = $RepoRoot
    branch = $branch
    head = $head
    lastCommit = $lastCommit
    remote = $remote
    status = $status
    scale = $scale
    versions = $versions
    p0 = $p0
    tests = [ordered]@{
        coreClasses = $coreTests.classes.Count; coreTests = $coreTests.tests.Count
        iosClasses = $iosTests.classes.Count; iosTests = $iosTests.tests.Count
        uiClasses = $uiTests.classes.Count; uiTests = $uiTests.tests.Count
        coreTestNames = @($coreTests.tests | ForEach-Object { $_.name })
        iosTestNames = @($iosTests.tests | ForEach-Object { $_.name })
        uiTestNames = @($uiTests.tests | ForEach-Object { $_.name })
    }
    recentRuns = $runs
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$jsonPath = Join-Path $OutDir "audit.json"
$mdPath = Join-Path $OutDir "audit.md"
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

# Markdown
$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("# PhotoDesk 1.4.0 基线审查（$($report.generatedAt)）")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 1. 基线")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 项 | 值 |")
[void]$md.AppendLine("|---|---|")
[void]$md.AppendLine("| 分支 | $branch |")
[void]$md.AppendLine("| HEAD | $head |")
[void]$md.AppendLine("| 最后提交 | $lastCommit |")
[void]$md.AppendLine("| 远端 | $remote |")
[void]$md.AppendLine("| 工作树 | $($status.Count) 个未提交项 |")
[void]$md.AppendLine("")
[void]$md.AppendLine("### 代码规模")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 目录 | Swift 文件 | 行数 |")
[void]$md.AppendLine("|---|---:|---:|")
foreach ($k in $scale.Keys) { [void]$md.AppendLine("| $k | $($scale[$k].files) | $($scale[$k].lines) |") }
[void]$md.AppendLine("")
[void]$md.AppendLine("### 版本")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 键 | 值 |")
[void]$md.AppendLine("|---|---|")
foreach ($k in $versions.Keys) { [void]$md.AppendLine("| $k | $($versions[$k]) |") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## 2. 四项 P0 静态取证")
[void]$md.AppendLine("")
[void]$md.AppendLine("### P0-1 捏合崩溃")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 文件：${zoomFile}:$($p0.P0_1_viewForZooming.startLine)-$($p0.P0_1_viewForZooming.endLine)")
[void]$md.AppendLine("- 结论：**$($p0.P0_1_viewForZooming.verdict)**")
if ($zoomHits.Count -gt 0) {
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| 行 | 命中内容 |")
    [void]$md.AppendLine("|---:|---|")
    foreach ($h in $zoomHits) { [void]$md.AppendLine("| $($h.line) | ``$($h.text.Replace('|','\|'))`` |") }
}
[void]$md.AppendLine("")
[void]$md.AppendLine("### P0-2 位置记忆")
[void]$md.AppendLine("")
[void]$md.AppendLine("- ``positionStore.save(`` 调用点：$($saveCalls.Count) 处")
foreach ($c in $saveCalls) { [void]$md.AppendLine("  - ${libraryFile}:$($c.line) — ``$($c.text)``") }
[void]$md.AppendLine("- ``viewDidLayoutSubviews`` 是否调用恢复入口：**$layoutCallsRestore**")
[void]$md.AppendLine("- 结论：**$($p0.P0_2_position.verdict)**")
[void]$md.AppendLine("")
[void]$md.AppendLine("### P0-3/P0-4 滑动多选")
[void]$md.AppendLine("")
[void]$md.AppendLine("- 结论：**$($p0.P0_3_slideSelect.verdict)**")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 文件:行 | 命中内容 |")
[void]$md.AppendLine("|---|---|")
foreach ($h in $p0.P0_3_slideSelect.singlePointHits) {
    [void]$md.AppendLine("| $($h.file):$($h.line) | ``$($h.text.Replace('|','\|'))`` |")
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 3. 测试清单")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 层 | 类数 | 测试函数数 |")
[void]$md.AppendLine("|---|---:|---:|")
[void]$md.AppendLine("| Core | $($coreTests.classes.Count) | $($coreTests.tests.Count) |")
[void]$md.AppendLine("| iOS | $($iosTests.classes.Count) | $($iosTests.tests.Count) |")
[void]$md.AppendLine("| UI | $($uiTests.classes.Count) | $($uiTests.tests.Count) |")
[void]$md.AppendLine("")
[void]$md.AppendLine("## 4. 最近 CI")
[void]$md.AppendLine("")
if ($runs.Count -eq 0) {
    [void]$md.AppendLine("（未取到 gh run list 结果）")
} else {
    [void]$md.AppendLine("| run id | workflow | status | conclusion | headSha |")
    [void]$md.AppendLine("|---|---|---|---|---|")
    foreach ($r in $runs) {
        [void]$md.AppendLine("| $($r.databaseId) | $($r.workflowName) | $($r.status) | $($r.conclusion) | $($r.headSha) |")
    }
}

Set-Content -Path $mdPath -Value $md.ToString() -Encoding UTF8
Write-Host "[OK] 审查完成：$mdPath"
Write-Host "[OK] JSON：$jsonPath"
exit 0
