# audit-m15.ps1 - M15 audit script (docs/25 Phase 0). ASCII-only output for cp936 consoles.
# Exit codes: 0 = pass, 2 = required file missing, 3 = red-line violation, 4 = P0 gate violation.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/audit-m15.ps1 [-Baseline]
#   -Baseline: skip P0 gate failures (Phase 0 evidence run; P0 counters still reported).
param([switch]$Baseline)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$outDir = Join-Path $repo "artifacts\audit\2026-11-09"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:sszzz")
$result = [ordered]@{ timestamp = $stamp; requiredFiles = @(); redlines = [ordered]@{}; p0 = [ordered]@{}; pages = @(); tests = [ordered]@{} }
$failures = New-Object System.Collections.Generic.List[string]

function Count-Hits([string]$pattern, [string[]]$paths, [string[]]$globs = @("*.swift")) {
    # UTF-8 explicit line scan: Select-String in Windows PowerShell assumes ANSI (cp936)
    # for BOM-less files, which silently misses Chinese patterns.
    $total = 0
    $rx = [System.Text.RegularExpressions.Regex]::new($pattern)
    foreach ($p in $paths) {
        $full = Join-Path $repo $p
        if (-not (Test-Path $full)) { continue }
        $files = Get-ChildItem -Path $full -Recurse -Include $globs -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\/]\.build[\/]' }
        foreach ($f in $files) {
            $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
            foreach ($line in $lines) { $total += $rx.Matches($line).Count }
        }
    }
    return $total
}

# --- a) required files ---
$required = @(
    "PhotoDesk/Features/Viewer/ZoomableImageCell.swift",
    "PhotoDesk/Features/Viewer/ViewerViewController.swift",
    "PhotoDesk/Features/Viewer/ViewerGesturePolicy.swift",
    "PhotoDesk/Features/Library/LibraryViewController.swift",
    "PhotoDesk/Features/Library/LibraryPositionCoordinator.swift",
    "PhotoDesk/Features/Library/SlideSelectGestureController.swift",
    "PhotoDesk/Features/Library/LibraryViewModel.swift",
    "PhotoDesk/Core/Support/LibraryPositionStore.swift",
    "scripts/test-core.ps1",
    "project.yml"
)
foreach ($f in $required) {
    $ok = Test-Path (Join-Path $repo $f)
    $result.requiredFiles += [ordered]@{ path = $f; exists = $ok }
    if (-not $ok) { $failures.Add("MISSING-FILE: $f") }
}
if ($failures.Count -gt 0) {
    $result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir "audit.json") -Encoding UTF8
    "AUDIT FAIL (missing files): exit 2"
    exit 2
}


# permanent-delete entries: only actionable UI literals / APIs count; compliance
# sentences like "本 App 不提供永久删除" and policy comments are excluded.
function Count-PermanentDeleteEntry([string[]]$paths) {
    $total = 0
    foreach ($p in $paths) {
        $full = Join-Path $repo $p
        if (-not (Test-Path $full)) { continue }
        $files = Get-ChildItem -Path $full -Recurse -Include "*.swift" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\/]\.build[\/]' }
        foreach ($f in $files) {
            $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
            foreach ($line in $lines) {
                if ($line -match "deleteAllAssets|permanentlyDelete") { $total++; continue }
                if ($line -match "Text\(|Button\(|setTitle|titleLabel|navigationTitle|alertTitle|confirmationDialog") {
                    if ($line -match "彻底删除|永久删除" -and $line -notmatch "不提供|禁用|不做|不出现") { $total++ }
                }
            }
        }
    }
    return $total
}
# --- b) red lines (must be 0) ---
$red = [ordered]@{
    urlsession              = Count-Hits "URLSession" @("PhotoDesk", "PhotoDeskCore/Sources")
    core_apple_imports      = Count-Hits "^import (UIKit|SwiftUI|Photos|PhotosUI|Vision|CoreImage|Accelerate|MapKit|Metal|AVFoundation)" @("PhotoDeskCore/Sources")
    force_try               = Count-Hits "try!" @("PhotoDesk", "PhotoDeskCore/Sources")
    force_cast              = Count-Hits "as!" @("PhotoDesk", "PhotoDeskCore/Sources")
    ios17_observable        = Count-Hits "@Observable" @("PhotoDesk")
    contentUnavailableView  = Count-Hits "ContentUnavailableView" @("PhotoDesk")
    swiftData               = Count-Hits "SwiftData" @("PhotoDesk")
    scrollTargetBehavior    = Count-Hits "scrollTargetBehavior" @("PhotoDesk")
    scrollPosition          = Count-Hits "\.scrollPosition" @("PhotoDesk")
    permanent_delete_entry  = Count-PermanentDeleteEntry @("PhotoDesk", "PhotoDeskCore/Sources")
}
$result.redlines = $red
foreach ($k in $red.Keys) {
    if ($red[$k] -gt 0) { $failures.Add("REDLINE $k = $($red[$k])") }
}

# --- c) P0-1 zoom symbols in Viewer (gate = docs/25 §4.7 list) ---
$p01 = [ordered]@{
    viewForZooming         = Count-Hits "viewForZooming" @("PhotoDesk/Features/Viewer")
    UIScrollViewDelegate   = Count-Hits "UIScrollViewDelegate" @("PhotoDesk/Features/Viewer")
    setZoomScale           = Count-Hits "setZoomScale" @("PhotoDesk/Features/Viewer")
    contentInset           = Count-Hits "contentInset" @("PhotoDesk/Features/Viewer")
    zoomContentView        = Count-Hits "zoomContentView" @("PhotoDesk/Features/Viewer")
    zoomScale_info_count   = Count-Hits "zoomScale" @("PhotoDesk/Features/Viewer")
    scrollViewDidZoom      = Count-Hits "scrollViewDidZoom" @("PhotoDesk/Features/Viewer")
}
$result.p0.zoom = $p01
if (-not $Baseline) {
    foreach ($k in @("viewForZooming","UIScrollViewDelegate","setZoomScale","contentInset","zoomContentView","scrollViewDidZoom")) {
        if ($p01[$k] -gt 0) { $failures.Add("P0-1 $k = $($p01[$k])") }
    }
}

# --- d) P0-2 position ---
$p02 = [ordered]@{
    positionStore_save_calls   = Count-Hits "positionStore\.save\(|store\.save\(" @("PhotoDesk")
    userdefaults_position_writes = Count-Hits "library\.lastPosition" @("PhotoDesk")
    beginRestore_calls         = Count-Hits "beginRestore\(" @("PhotoDesk")
    viewWillDisappear_conditional = Count-Hits "isMovingFromParent" @("PhotoDesk/Features/Library")
    machine_maxAttempts        = Count-Hits "maxAttempts" @("PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift")
    machine_timeout_3s         = Count-Hits "timeout: TimeInterval = 3" @("PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift")
    position_file_store        = (Test-Path (Join-Path $repo "PhotoDesk/Core/Support/PositionFileStore.swift"))
    restore_machine_v5         = (Test-Path (Join-Path $repo "PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift"))
}
$result.p0.position = $p02
if (-not $Baseline) {
    if (-not $p02.position_file_store) { $failures.Add("P0-2 PositionFileStore.swift missing") }
    if (-not $p02.restore_machine_v5) { $failures.Add("P0-2 PositionRestoreMachine.swift missing") }
    if ($p02.machine_maxAttempts -gt 0) { $failures.Add("P0-2 maxAttempts still in machine = $($p02.machine_maxAttempts)") }
    if ($p02.machine_timeout_3s -gt 0) { $failures.Add("P0-2 3s timeout still in machine") }
    if ($p02.viewWillDisappear_conditional -lt 1) { $failures.Add("P0-2 viewWillDisappear save gate missing") }
}

# --- e) P0-3/4 marquee ---
$p03 = [ordered]@{
    slideSelectRangePolicy_refs = Count-Hits "SlideSelectRangePolicy" @("PhotoDesk", "PhotoDeskCore/Sources", "PhotoDeskCore/Tests", "PhotoDeskTests", "PhotoDeskUITests")
    insert_only_target_baseIDs = Count-Hits "target = baseIDs" @("PhotoDesk/Features/Library")
    whole_row_banner          = Count-Hits "单指按住|整行连续选择" @("PhotoDesk/Features/Library")
    marquee_policy            = (Test-Path (Join-Path $repo "PhotoDeskCore/Sources/PhotoDeskCore/MarqueeSelectionPolicy.swift"))
    range_policy_file         = (Test-Path (Join-Path $repo "PhotoDeskCore/Sources/PhotoDeskCore/SlideSelectRangePolicy.swift"))
    range_policy_tests        = (Test-Path (Join-Path $repo "PhotoDeskCore/Tests/PhotoDeskCoreTests/SlideSelectRangePolicyTests.swift"))
    old_tests_still_present   = Count-Hits "testVerticalSlideSelectSelectsLeftColumns|testSlideSelectDragBackRestores\b" @("PhotoDeskUITests")
}
$result.p0.marquee = $p03
if (-not $Baseline) {
    if ($p03.slideSelectRangePolicy_refs -gt 0) { $failures.Add("P0-3 SlideSelectRangePolicy refs = $($p03.slideSelectRangePolicy_refs)") }
    if ($p03.range_policy_file) { $failures.Add("P0-3 SlideSelectRangePolicy.swift still exists") }
    if ($p03.range_policy_tests) { $failures.Add("P0-3 SlideSelectRangePolicyTests.swift still exists") }
    if ($p03.insert_only_target_baseIDs -gt 0) { $failures.Add("P0-4 insert-only target = baseIDs = $($p03.insert_only_target_baseIDs)") }
    if ($p03.whole_row_banner -gt 0) { $failures.Add("P0-3 whole-row banner text = $($p03.whole_row_banner)") }
    if (-not $p03.marquee_policy) { $failures.Add("P0-3 MarqueeSelectionPolicy.swift missing") }
}

# --- f) pages inventory ---
$pages = Get-ChildItem -Path (Join-Path $repo "PhotoDesk/Features") -Recurse -Include "*View.swift","*ViewController.swift" -File |
    ForEach-Object {
        $lines = (Get-Content $_.FullName | Measure-Object -Line).Lines
        $hasAx = (Select-String -Path $_.FullName -Pattern "accessibilityIdentifier" -Quiet)
        [ordered]@{ path = $_.FullName.Substring($repo.Length + 1).Replace("\", "/"); lines = $lines; hasAccessibilityId = [bool]$hasAx }
    }
$result.pages = $pages

# --- g) tests inventory ---
$tests = [ordered]@{}
foreach ($d in @("PhotoDeskTests", "PhotoDeskUITests", "PhotoDeskCore/Tests")) {
    $n = 0
    $full = Join-Path $repo $d
    if (Test-Path $full) {
        Get-ChildItem -Path $full -Recurse -Include "*.swift" -File | ForEach-Object {
            $n += (Select-String -Path $_.FullName -Pattern "func test" -AllMatches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
        }
    }
    $tests[$d] = $n
}
$result.tests = $tests

# --- emit ---
$jsonPath = Join-Path $outDir "audit.json"
$result | ConvertTo-Json -Depth 8 | Set-Content $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# M15 Audit Report")
$md.Add("")
$md.Add("- stamp: $stamp")
$md.Add("- mode: $(if ($Baseline) { 'BASELINE (P0 gates informational)' } else { 'GATE (P0 must be 0)' })")
$md.Add("")
$md.Add("## Red lines (must be 0)")
foreach ($k in $red.Keys) { $md.Add("- $k = $($red[$k])") }
$md.Add("")
$md.Add("## P0-1 zoom symbols in Viewer")
foreach ($k in $p01.Keys) { $md.Add("- $k = $($p01[$k])") }
$md.Add("")
$md.Add("## P0-2 position")
foreach ($k in $p02.Keys) { $md.Add("- $k = $($p02[$k])") }
$md.Add("")
$md.Add("## P0-3/4 marquee")
foreach ($k in $p03.Keys) { $md.Add("- $k = $($p03[$k])") }
$md.Add("")
$md.Add("## Tests (func test count)")
foreach ($k in $tests.Keys) { $md.Add("- $k = $($tests[$k])") }
$md.Add("")
$md.Add("## Pages ($($pages.Count) view/viewcontroller files)")
foreach ($p in $pages) { $md.Add("- $($p.path) ($($p.lines) lines, ax=$($p.hasAccessibilityId))") }
$md.Add("")
if ($failures.Count -gt 0) {
    $md.Add("## FAILURES")
    foreach ($f in $failures) { $md.Add("- $f") }
} else {
    $md.Add("## RESULT: PASS")
}
$mdPath = Join-Path $outDir "audit.md"
$md | Set-Content $mdPath -Encoding UTF8

Write-Output "audit: $(if ($failures.Count -eq 0) { 'PASS' } else { "FAIL ($($failures.Count))" }) -> $mdPath"
if ($failures.Count -gt 0) { exit 4 }
exit 0
