# scripts/audit-m18.ps1
# 职责说明：M18 全新只读审查（原生轨迹滑选改造的确定性红/绿基线）——
# 只扫描当前源码与配置，输出 <OutDir>/audit.md + audit.json；不修改任何源码，不做推断。
# 与 audit-m17.ps1 的关系：M17 脚本以「框选」为验收目标（A07 要求选框必须存在、A14 硬编码
# MarqueeSelectionUITests 文件名），与 M18「彻底退役框选」直接冲突，已过期归档，不复用（docs/36 §3）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit-m18.ps1 [-Root <path>] [-OutDir artifacts/audit/m18] [-Strict]
# 退出码：0 正常；2 -Strict 且存在 BLOCKING 未达标；3 环境错误（根目录/必备文件缺失）。
# 确定性：除 generatedAt 外，audit.md / audit.json / stdout 连跑两次必须逐字节一致。
param(
    [string]$Root = "",
    [string]$OutDir = "artifacts/audit/m18",
    [switch]$Strict
)
$ErrorActionPreference = "Stop"
try {
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
    return @($out)
}

# 命中扫描；目标文件不存在时返回 missingFiles（检查判 FAIL，绝不静默跳过）。
function Find-Hits([string[]]$files, [string]$pattern, [string]$exclude) {
    $hits = @()
    $missing = @()
    foreach ($f in $files) {
        $abs = Join-Path $Root $f
        if (-not (Test-Path $abs)) { $missing += $f; continue }
        foreach ($x in @(Select-String -Path $abs -Pattern $pattern -AllMatches)) {
            $line = $x.Line.Trim()
            if (-not [string]::IsNullOrEmpty($exclude) -and $line -match $exclude) { continue }
            $hits += [pscustomobject]@{ file = $f; line = $x.LineNumber; text = $line }
        }
    }
    return @{ hits = @($hits | Sort-Object file, line); missing = @($missing) }
}

# 文件存在性检查（PRESENT 类：文件缺失即显式 FAIL）。
function Check-File([string]$f) {
    if (Test-Path (Join-Path $Root $f)) {
        return @{ hits = @([pscustomobject]@{ file = $f; line = 0; text = "[文件存在]" }); missing = @() }
    }
    return @{ hits = @(); missing = @($f) }
}

$features   = Get-SwiftRel "PhotoDesk/Features"
$appAll     = Get-SwiftRel "PhotoDesk"
$uiTests    = Get-SwiftRel "PhotoDeskUITests"
$unitTests  = Get-SwiftRel "PhotoDeskTests"
$coreSrc    = Get-SwiftRel "PhotoDeskCore/Sources"
$coreTests  = Get-SwiftRel "PhotoDeskCore/Tests"

$machine      = "PhotoDeskCore/Sources/PhotoDeskCore/SelectionGestureMachine.swift"
$selPolicy    = "PhotoDeskCore/Sources/PhotoDeskCore/SelectionPolicy.swift"
$selCtl       = "PhotoDesk/Features/Library/LibrarySelectionController.swift"
$hitTester    = "PhotoDesk/Features/Library/GridHitTester.swift"
$vc           = "PhotoDesk/Features/Library/LibraryViewController.swift"
$trailFile    = "PhotoDeskCore/Sources/PhotoDeskCore/SlideSelectTrail.swift"
$resolverFile = "PhotoDeskCore/Sources/PhotoDeskCore/TrailHitResolver.swift"
$cellFrame    = "PhotoDeskCore/Sources/PhotoDeskCore/GridCellFrame.swift"
$trailUI      = "PhotoDeskUITests/SlideSelectTrailUITests.swift"
$projYml      = "project.yml"
$iosYml       = ".github/workflows/ios.yml"

# Core 非 Foundation import 单独扫（红线 2：只允许 import Foundation）。
function Find-NonFoundationImports([string[]]$files) {
    $hits = @()
    $missing = @()
    foreach ($f in $files) {
        $abs = Join-Path $Root $f
        if (-not (Test-Path $abs)) { $missing += $f; continue }
        foreach ($x in @(Select-String -Path $abs -Pattern '^\s*import\s+\w+')) {
            if ($x.Line -notmatch 'import\s+Foundation\b') {
                $hits += [pscustomobject]@{ file = $f; line = $x.LineNumber; text = $x.Line.Trim() }
            }
        }
    }
    return @{ hits = @($hits | Sort-Object file, line); missing = @($missing) }
}

$checks = @(
    # ---------- BLOCKING（M18 红线：命中即失败） ----------
    @{ id="B01"; level="BLOCKING"; kind="coreImport"; title="PhotoDeskCore 零 Apple 依赖：只允许 import Foundation（AGENTS 红线 2）"; expect="empty"; files=$coreSrc; pattern='^\s*import\s+\w+'; exclude='import\s+Foundation\b' },
    @{ id="B02"; level="BLOCKING"; title="App 不得出现 iOS 17+ API（iOS 16 基线，禁 @Observable/SwiftData/ContentUnavailableView/scrollTargetBehavior/scrollPosition）"; expect="empty"; files=$appAll; pattern='@Observable\b|@Bindable\b|ContentUnavailableView|scrollTargetBehavior|\.scrollPosition\b|SwiftData|if\s+#available\(iOS\s*17|@available\(iOS\s*17'; exclude='' },
    @{ id="B03"; level="BLOCKING"; title="App 不得出现 minimumNumberOfTouches = 2（不用双指规则，docs/38 §1.2 #4）"; expect="empty"; files=$appAll; pattern='minimumNumberOfTouches\s*=\s*2'; exclude='' },
    @{ id="B04"; level="BLOCKING"; title="Feature 层不得直接引用 PHAsset（AGENTS 架构规则 1）"; expect="empty"; files=$features; pattern='PHAsset'; exclude='' },
    @{ id="B05"; level="BLOCKING"; title="红线 1 文案：不得出现「彻底删除/永久删除」祈使/陈述句（否定句与疑问句视为合规引用）"; expect="empty"; files=$appAll; pattern='彻底删除|永久删除'; exclude='不提供|不能|不会|无法|禁止|禁用|拒绝|不允许|也没|吗[？?]' },
    @{ id="B06"; level="BLOCKING"; title="App 层不得有活跃框选符号（marquee*/MarqueeOverlayView/Marquee-Overlay/lastMarqueeRect/hitTest(rectInContent:)/HitRect，docs/38 §1.2 #1）"; expect="empty"; files=$appAll; pattern='(?i)marquee|HitRect\b|hitTest\([Rr]ectInContent'; exclude='' },
    @{ id="B07"; level="BLOCKING"; title="Core 层不得有框选调用点（MarqueeSelectionPolicy.mode/resolved、MarqueeHitResolver.hit、GridHitRegion.hitIDs/mergedSelection 的调用归零）"; expect="empty"; files=$coreSrc; pattern='MarqueeSelectionPolicy\.(mode|resolved)\(|MarqueeHitResolver\.hit\(|GridHitRegion\.(hitIDs|mergedSelection)\('; exclude='' },
    @{ id="B08"; level="BLOCKING"; title="状态机 effect 不得再用旧名 beginMarquee/updateMarquee/endMarquee（T04 改名 beginTrail/updateTrail/endTrail）"; expect="empty"; files=@($machine); pattern='\bbeginMarquee\b|\bupdateMarquee\b|\bendMarquee\b'; exclude='' },
    @{ id="B09"; level="BLOCKING"; title="App 禁止 try! / as!（AGENTS 代码规范）"; expect="empty"; files=$appAll; pattern='try[!]|as[!]'; exclude='' },
    @{ id="B10"; level="BLOCKING"; title="UI/单测不得再断言框选 overlay/矩形/整行带/双指滚动（冻结用例契约必须迁移）"; expect="empty"; files=@($uiTests + $unitTests); pattern='(?i)marquee|hitTest\(rectInContent|SelectsRow\(|SelectsRectangle\(|TwoFingerScroll|框选|矩形命中|整行带'; exclude='' },

    # ---------- PRESENT（M18 目标结构必须就位；文件缺失显式 FAIL） ----------
    @{ id="P01"; level="PRESENT"; kind="pattern"; title="SelectionGestureMachine 状态机存在（复用状态表）"; expect="present"; files=@($machine); pattern='(enum|struct)\s+SelectionGestureMachine\b'; exclude='' },
    @{ id="P02"; level="PRESENT"; kind="file"; title="SlideSelectTrail.swift 存在（路径事务，T02 产出）"; expect="present"; files=@($trailFile); pattern=''; exclude='' },
    @{ id="P03"; level="PRESENT"; kind="file"; title="TrailHitResolver.swift 存在（线段扫掠命中，T03 产出）"; expect="present"; files=@($resolverFile); pattern=''; exclude='' },
    @{ id="P04"; level="PRESENT"; kind="file"; title="GridCellFrame.swift 存在（CellFrame 从 marquee 命名中抽出，T03 产出）"; expect="present"; files=@($cellFrame); pattern=''; exclude='' },
    @{ id="P05"; level="PRESENT"; kind="pattern"; title="App 控制器接线 trailHitProvider（线段命中注入）"; expect="present"; files=@($selCtl, $vc); pattern='trailHitProvider'; exclude='' },
    @{ id="P06"; level="PRESENT"; kind="pattern"; title="GridHitTester.hitTestLine(from:to:) 存在（真实 attributes 线段扫描）"; expect="present"; files=@($hitTester); pattern='func\s+hitTestLine'; exclude='' },
    @{ id="P07"; level="PRESENT"; kind="pattern"; title="App 增量落地 applySelectionDelta 存在"; expect="present"; files=@($selCtl, $vc); pattern='applySelectionDelta'; exclude='' },
    @{ id="P08"; level="PRESENT"; kind="pattern"; title="Core SelectionState.applyDelta(add:remove:) 存在（事务输出承担者）"; expect="present"; files=@($selPolicy); pattern='func\s+applyDelta\(add:\s*Set<String>,\s*remove:\s*Set<String>\)'; exclude='' },
    @{ id="P09"; level="PRESENT"; kind="pattern"; title="SlideSelectTrailTests 存在（T02 红/绿单测）"; expect="present"; files=$coreTests; pattern='final\s+class\s+SlideSelectTrailTests'; exclude='' },
    @{ id="P10"; level="PRESENT"; kind="pattern"; title="TrailHitResolverTests 存在（T03 红/绿单测）"; expect="present"; files=$coreTests; pattern='final\s+class\s+TrailHitResolverTests'; exclude='' },
    @{ id="P11"; level="PRESENT"; kind="file"; title="SlideSelectTrailUITests.swift 存在（T08 改名重写产物）"; expect="present"; files=@($trailUI); pattern=''; exclude='' },
    @{ id="P12"; level="PRESENT"; kind="pattern"; title="状态机新 effect 名 beginTrail/updateTrail/endTrail 就位（T04 产出）"; expect="present"; files=@($machine); pattern='beginTrail|updateTrail|endTrail'; exclude='' },
    @{ id="P13"; level="PRESENT"; kind="pattern"; title="方向锁与滚动让位保留（releaseScroll/scrollLocked，单指纵向滚动共存）"; expect="present"; files=@($machine, $selCtl); pattern='releaseScroll|scrollLocked'; exclude='' },

    # ---------- INFO（发布与取证记录；不计入退出码） ----------
    @{ id="I01"; level="INFO"; kind="pattern"; title="project.yml 版本号（T10 目标 1.7.0 (8)）"; expect="present"; files=@($projYml); pattern='MARKETING_VERSION|CURRENT_PROJECT_VERSION'; exclude='' },
    @{ id="I02"; level="INFO"; kind="pattern"; title="部署目标 IPHONEOS_DEPLOYMENT_TARGET = 16.0"; expect="present"; files=@($projYml); pattern='IPHONEOS_DEPLOYMENT_TARGET:\s*"16\.0"'; exclude='' },
    @{ id="I03"; level="INFO"; kind="pattern"; title="CI 产物名 PhotoDesk-Simulator-app-zip / PhotoDesk-unsigned-ipa"; expect="present"; files=@($iosYml); pattern='PhotoDesk-Simulator-app-zip|PhotoDesk-unsigned-ipa'; exclude='' },
    @{ id="I04"; level="INFO"; kind="pattern"; title="CI minos=16.0 校验链（MINOS_VERSION + otool LC_BUILD_VERSION）"; expect="present"; files=@($iosYml); pattern='MINOS_VERSION|LC_BUILD_VERSION'; exclude='' },
    @{ id="I05"; level="INFO"; kind="releaseDir"; title="Release 归档目录 artifacts/release/1.7.0（T10 前允许缺失）"; expect="present"; files=@("artifacts/release/1.7.0"); pattern=''; exclude='' },
    @{ id="I06"; level="INFO"; kind="pattern"; title="DEBUG 取证字段（debugAutoScrollTicks/debugHapticCount/debugTouchDownHitID）"; expect="present"; files=@($selCtl); pattern='debugAutoScrollTicks|debugHapticCount|debugTouchDownHitID'; exclude='' }
)

$results = @()
foreach ($c in $checks) {
    if ($c.kind -eq "file" -or $c.kind -eq "releaseDir") {
        $r = Check-File $c.files[0]
    } elseif ($c.id -eq "B01") {
        $r = Find-NonFoundationImports $c.files
    } else {
        $r = Find-Hits -files $c.files -pattern $c.pattern -exclude $c.exclude
    }
    $ok = ($r.missing.Count -eq 0)
    if ($ok) {
        if ($c.expect -eq "empty") { $ok = ($r.hits.Count -eq 0) } else { $ok = ($r.hits.Count -gt 0) }
    }
    $status = "FAIL"; if ($ok) { $status = "PASS" }
    $results += [pscustomobject]@{ id=$c.id; level=$c.level; title=$c.title; expect=$c.expect; status=$status; count=$r.hits.Count; missing=@($r.missing); hits=$r.hits }
}

# 版本号取值（INFO 记录用，确定性解析 project.yml）
$marketingVersion = "-"
$buildVersion = "-"
$deployTarget = "-"
if (Test-Path (Join-Path $Root $projYml)) {
    foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $Root $projYml))) {
        if ($l -match 'MARKETING_VERSION:\s*"([^"]+)"') { $marketingVersion = $Matches[1] }
        if ($l -match 'CURRENT_PROJECT_VERSION:\s*"([^"]+)"') { $buildVersion = $Matches[1] }
        if ($l -match 'IPHONEOS_DEPLOYMENT_TARGET:\s*"([^"]+)"') { $deployTarget = $Matches[1] }
    }
}
$releaseDirRel = "artifacts/release"
$releaseDirs = @()
if (Test-Path (Join-Path $Root $releaseDirRel)) {
    foreach ($d in (Get-ChildItem (Join-Path $Root $releaseDirRel) -Directory | Sort-Object Name)) { $releaseDirs += $d.Name }
}

$blockingFail = @($results | Where-Object { $_.level -eq "BLOCKING" -and $_.status -eq "FAIL" })
$generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# M18 全新审查（自动生成，只读扫描）")
[void]$md.AppendLine("")
[void]$md.AppendLine("- generatedAt: $generatedAt")
[void]$md.AppendLine("- root: $($Root.Replace([char]92, [char]47))")
[void]$md.AppendLine("- version: $marketingVersion ($buildVersion)，deploymentTarget: iOS $deployTarget")
[void]$md.AppendLine("- releaseDirs: $(if ($releaseDirs.Count -gt 0) { $releaseDirs -join ', ' } else { '(无)' })")
[void]$md.AppendLine("- blocking failures: $($blockingFail.Count) / $($results.Count)")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 编号 | 级别 | 检查 | 期望 | 结果 | 命中数 |")
[void]$md.AppendLine("|---|---|---|---|---|---|")
foreach ($r in $results) { [void]$md.AppendLine("| $($r.id) | $($r.level) | $($r.title) | $($r.expect) | $($r.status) | $($r.count) |") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## 命中明细")
foreach ($r in $results) {
    if ($r.missing.Count -gt 0) {
        [void]$md.AppendLine("")
        [void]$md.AppendLine("### $($r.id) - 文件缺失（显式 FAIL）")
        foreach ($m in $r.missing) { [void]$md.AppendLine("- [文件不存在] $m") }
    }
    if ($r.count -gt 0) {
        [void]$md.AppendLine("")
        [void]$md.AppendLine("### $($r.id) - $($r.title) [$($r.status)]")
        foreach ($h in $r.hits) { [void]$md.AppendLine("- $($h.file):$($h.line) - $($h.text)") }
    }
}
$mdPath = Join-Path $OutAbs "audit.md"
[System.IO.File]::WriteAllText($mdPath, $md.ToString(), (New-Object System.Text.UTF8Encoding($true)))

$jsonChecks = @()
foreach ($r in $results) {
    $hitList = @()
    foreach ($h in $r.hits) { $hitList += [pscustomobject]@{ file=$h.file; line=$h.line; text=$h.text } }
    $jsonChecks += [pscustomobject]@{ id=$r.id; level=$r.level; title=$r.title; expect=$r.expect; status=$r.status; count=$r.count; missing=$r.missing; hits=$hitList }
}
$json = [pscustomobject]@{
    generatedAt = $generatedAt
    root = $Root.Replace([char]92, [char]47)
    version = "$marketingVersion ($buildVersion)"
    deploymentTarget = "iOS $deployTarget"
    releaseDirs = $releaseDirs
    blockingFailures = $blockingFail.Count
    total = $results.Count
    checks = $jsonChecks
}
$jsonPath = Join-Path $OutAbs "audit.json"
[System.IO.File]::WriteAllText($jsonPath, ($json | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ("M18 audit: {0} checks, {1} blocking failures, version {2} ({3}) -> {4}" -f $results.Count, $blockingFail.Count, $marketingVersion, $buildVersion, (Rel $mdPath))
foreach ($r in $results) { Write-Host ("  {0} {1} {2} ({3})" -f $r.id, $r.status, $r.title, $r.count) }
if ($Strict -and $blockingFail.Count -gt 0) { exit 2 }
exit 0
}
catch {
    Write-Host "[X] 审查环境错误：$($_.Exception.Message)"
    exit 3
}