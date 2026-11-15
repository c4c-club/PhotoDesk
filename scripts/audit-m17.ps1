# scripts/audit-m17.ps1
# 职责说明：M17 全新基线审查（只读、确定性）——只扫描当前源码，输出 artifacts/audit/m17/audit.md + audit.json。
# 覆盖：滑动多选手感 / 滚动后错位 / 长按进入 + 架构红线 + 页面级缺陷线索。不修改任何源码，不做推断。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit-m17.ps1 [-Strict] [-OutDir artifacts/audit/m17]
# 退出码：0 正常；2 -Strict 且存在 BLOCKING 未达标；3 环境错误。
param(
    [string]$Root = "",
    [string]$OutDir = "artifacts/audit/m17",
    [switch]$Strict
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path.TrimEnd([char]92)
Set-Location $Root
$OutAbs = Join-Path $Root $OutDir
New-Item -ItemType Directory -Force -Path $OutAbs | Out-Null

function Rel([string]$p) {
    if ($p -eq $Root) { return "." }
    if ($p.StartsWith($Root + [char]92)) { return $p.Substring($Root.Length + 1).Replace([char]92, [char]47) }
    return $p.Replace([char]92, [char]47)
}

function Get-SwiftRel([string]$relDir) {
    $full = Join-Path $Root $relDir
    if (-not (Test-Path $full)) { return @() }
    $out = @()
    foreach ($i in (Get-ChildItem $full -Recurse -Filter *.swift -File |
            Where-Object { $_.FullName -notmatch "[\\/][.]build[\\/]" } | Sort-Object FullName)) {
        $out += (Rel $i.FullName)
    }
    return $out
}

function Find-Hits([string[]]$files, [string]$pattern) {
    $hits = @()
    foreach ($f in $files) {
        $abs = Join-Path $Root $f
        if (-not (Test-Path $abs)) { continue }
        foreach ($x in @(Select-String -Path $abs -Pattern $pattern -AllMatches)) {
            $hits += [pscustomobject]@{ file = $f; line = $x.LineNumber; text = $x.Line.Trim() }
        }
    }
    return @($hits | Sort-Object file, line)
}

$features = @(Get-SwiftRel "PhotoDesk/Features")
$appAll = @(Get-SwiftRel "PhotoDesk")
$uiTests = @(Get-SwiftRel "PhotoDeskUITests")
$coreSrc = @(Get-SwiftRel "PhotoDeskCore/Sources")

$libVC = "PhotoDesk/Features/Library/LibraryViewController.swift"
$selCtl = "PhotoDesk/Features/Library/LibrarySelectionController.swift"
$coreMachine = "PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift"
$gridLayout = "PhotoDesk/Features/Library/LibraryGridLayout.swift"
$cell = "PhotoDesk/Features/Library/PhotoGridCell.swift"
$marqueeTests = "PhotoDeskUITests/MarqueeSelectionUITests.swift"

$checks = @(
    @{ id = "A01"; level = "WARN"; title = "框选几何来源：DSSpacing 估算 vs 真实 layoutAttributes"; expect = "empty"; files = @($libVC); pattern = "itemSide = [(]width" },
    @{ id = "A02"; level = "WARN"; title = "supplementary attributes 参与命中（粘性头可能污染 originY，需实测）"; expect = "empty"; files = @($libVC); pattern = "layoutAttributesForSupplementaryView" },
    @{ id = "A03"; level = "INFO"; title = "网格粘性头开关（记录用）"; expect = "present"; files = @($libVC); pattern = "pinToVisibleBounds" },
    @{ id = "A04"; level = "BLOCKING"; title = "网格必须支持长按进入多选"; expect = "present"; files = @($libVC, $selCtl); pattern = "UILongPressGestureRecognizer" },
    @{ id = "A05"; level = "BLOCKING"; title = "多选模式不得用双指规则劫持单指滚动"; expect = "empty"; files = @($libVC); pattern = "minimumNumberOfTouches = 2" },
    @{ id = "A06"; level = "BLOCKING"; title = "框选必须有方向锁（垂直拖动让位滚动）"; expect = "present"; files = @($coreMachine, $selCtl); pattern = "releaseScroll|scrollLocked" },
    @{ id = "A07"; level = "BLOCKING"; title = "框选必须有可视反馈（选框/压暗/动画）"; expect = "present"; files = @($libVC, $selCtl, $cell); pattern = "MarqueeOverlay|marqueeOverlay|dimView|setDimmed|CASpringAnimation" },
    @{ id = "A08"; level = "BLOCKING"; title = "多选 scope 必须取全量筛选结果"; expect = "empty"; files = @($libVC); pattern = "currentItemsBySection[.]flatMap" },
    @{ id = "A09"; level = "BLOCKING"; title = "框选每帧不得 O(n log n) 全量排序替换"; expect = "empty"; files = @($libVC); pattern = "replaceSelection[(]Array[(]ids[)][.]sorted" },
    @{ id = "A10"; level = "BLOCKING"; title = "Feature 层不得直接引用 PHAsset（AGENTS 3.1）"; expect = "empty"; files = $features; pattern = "PHAsset" },
    @{ id = "A11"; level = "BLOCKING"; title = "iOS 16 基线：不得出现 iOS 17+ API"; expect = "empty"; files = $appAll; pattern = "@available[(]iOS 17|ContentUnavailableView|scrollTargetBehavior|@Observable|SwiftData" },
    @{ id = "A12"; level = "BLOCKING"; title = "禁止 try! / as!"; expect = "empty"; files = $appAll; pattern = "try[!]|as[!]" },
    @{ id = "A13"; level = "WARN"; title = "红线 1 文案：人工核对永久删除/彻底删除出现处"; expect = "empty"; files = $appAll; pattern = "彻底删除|永久删除" },
    @{ id = "A14"; level = "BLOCKING"; title = "UI 测试必须覆盖长按进入"; expect = "present"; files = @($marqueeTests); pattern = "longPress|press[(]forDuration: 0[.](3|35|4)" },
    @{ id = "A15"; level = "BLOCKING"; title = "命中计算不得每帧遍历全部 section 查询布局"; expect = "empty"; files = @($selCtl, $libVC); pattern = "for section in 0[.][.]<counts[.]count" },
    @{ id = "A16"; level = "INFO"; title = "DEBUG 自动滚动诊断采样（记录用）"; expect = "present"; files = @($selCtl); pattern = "debugAutoScrollTicks" },
    @{ id = "A17"; level = "INFO"; title = "布局横向 interItemSpacing 已显式设置（与几何公式需一致性核对）"; expect = "present"; files = @($libVC, $gridLayout); pattern = "group[.]interItemSpacing" },
    @{ id = "A18"; level = "BLOCKING"; title = "PhotoDeskCore 零 Apple UI 依赖"; expect = "empty"; files = $coreSrc; pattern = "import (UIKit|Photos|SwiftUI|Vision|CoreImage|Accelerate)" },
    @{ id = "A19"; level = "WARN"; title = "SlideSelectPolicy 遗留方向锁/往返统计函数是否仍被引用（死代码）"; expect = "empty"; files = @($selCtl, $libVC); pattern = "resolvedSelection|deduplicated[(]" }
)

$results = @()
foreach ($c in $checks) {
    $hits = @(Find-Hits -files $c.files -pattern $c.pattern)
    if ($c.expect -eq "empty") { $ok = ($hits.Count -eq 0) } else { $ok = ($hits.Count -gt 0) }
    $status = "FAIL"
    if ($ok) { $status = "PASS" }
    $results += [pscustomobject]@{ id = $c.id; level = $c.level; title = $c.title; expect = $c.expect; status = $status; count = $hits.Count; hits = $hits }
}

$blockingFail = @($results | Where-Object { $_.level -eq "BLOCKING" -and $_.status -eq "FAIL" })
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# M17 基线审查（自动生成，只读扫描）")
[void]$md.AppendLine("")
[void]$md.AppendLine("- generatedAt: $generatedAt")
[void]$md.AppendLine("- root: $($Root.Replace([char]92, [char]47))")
[void]$md.AppendLine("- blocking failures: $($blockingFail.Count) / $($results.Count)")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 编号 | 级别 | 检查 | 期望 | 结果 | 命中数 |")
[void]$md.AppendLine("|---|---|---|---|---|---|")
foreach ($r in $results) { [void]$md.AppendLine("| $($r.id) | $($r.level) | $($r.title) | $($r.expect) | $($r.status) | $($r.count) |") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## 命中明细")
foreach ($r in $results) {
    if ($r.count -eq 0) { continue }
    [void]$md.AppendLine("")
    [void]$md.AppendLine("### $($r.id) - $($r.title) [$($r.status)]")
    foreach ($h in $r.hits) { [void]$md.AppendLine("- $($h.file):$($h.line) - $($h.text)") }
}
$mdPath = Join-Path $OutAbs "audit.md"
[System.IO.File]::WriteAllText($mdPath, $md.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$jsonChecks = @()
foreach ($r in $results) { $jsonChecks += [pscustomobject]@{ id = $r.id; level = $r.level; title = $r.title; expect = $r.expect; status = $r.status; count = $r.count } }
$json = [pscustomobject]@{ generatedAt = $generatedAt; root = $Root.Replace([char]92, [char]47); blockingFailures = $blockingFail.Count; total = $results.Count; checks = $jsonChecks }
$jsonPath = Join-Path $OutAbs "audit.json"
[System.IO.File]::WriteAllText($jsonPath, ($json | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("M17 audit: {0} checks, {1} blocking failures -> {2}" -f $results.Count, $blockingFail.Count, (Rel $mdPath))
foreach ($r in $results) { Write-Host ("  {0} {1} {2} ({3})" -f $r.id, $r.status, $r.title, $r.count) }
if ($Strict -and $blockingFail.Count -gt 0) { exit 2 }
exit 0
