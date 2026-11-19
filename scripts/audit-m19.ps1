# scripts/audit-m19.ps1 — M19 行带滑选静态审查（T01 重写；scripts/audit-m18.ps1 只读归档）
# 职责说明：只读审查 PhotoDesk / PhotoDeskCore / 测试的行带滑选改造契约与 AGENTS.md 红线。
#   audit-m18 的 B10/P03/P06 语义已作废（docs/41 §5、docs/42 §9），本脚本按 M19 契约全新编写。
# 确定性：除 generatedAt 外输出逐字节一致——文件清单排序、检查顺序固定、无耗时/随机数。
# 退出码：0 = 无 BLOCKING 失败（-Strict 时 PRESENT 失败也判失败）；2 = 有失败；3 = 脚本异常。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit-m19.ps1 [-Root <repo>] [-OutDir <dir>] [-Strict]

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$OutDir = "",
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'
$nl = [Environment]::NewLine
try {
    $repo = (Resolve-Path $Root).Path
    if (-not (Test-Path (Join-Path $repo 'PhotoDeskCore'))) { throw "repo 根目录无 PhotoDeskCore：$repo" }
    if ($OutDir -eq "") { $OutDir = Join-Path $repo 'artifacts\audit\m19' }
    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
    $generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    function Get-RelSwift([string]$Sub) {
        $dir = Join-Path $repo ($Sub -replace '/', '\')
        if (-not (Test-Path $dir)) { return @() }
        Get-ChildItem -Path $dir -Recurse -Filter *.swift -File |
            Where-Object { -not $_.FullName.Contains('\.build\') } |
            ForEach-Object { $_.FullName.Substring($repo.Length + 1).Replace('\', '/') } |
            Sort-Object
    }
    $appFiles  = Get-RelSwift 'PhotoDesk'
    $coreFiles = Get-RelSwift 'PhotoDeskCore/Sources'
    $coreTests = Get-RelSwift 'PhotoDeskCore/Tests'
    $uiTests   = Get-RelSwift 'PhotoDeskUITests'
    $unitTests = Get-RelSwift 'PhotoDeskTests'
    $featFiles = Get-RelSwift 'PhotoDesk/Features'

    $lineCache = @{}
    function Get-Lines([string]$Rel) {
        if (-not $lineCache.ContainsKey($Rel)) {
            $p = Join-Path $repo ($Rel -replace '/', '\')
            if (-not (Test-Path $p)) { throw "文件缺失：$Rel" }
            $lineCache[$Rel] = @(Get-Content -LiteralPath $p -Encoding UTF8)
        }
        return ,$lineCache[$Rel]
    }
    function Get-Text([string]$Rel) { (Get-Lines $Rel) -join $nl }

    function Find-Hits([string[]]$Files, [string]$Pattern, [string]$ExcludePattern = "") {
        $hits = @()
        foreach ($f in $Files) {
            $lines = Get-Lines $f
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ([regex]::IsMatch($lines[$i], $Pattern)) {
                    if ($ExcludePattern -ne "" -and [regex]::IsMatch($lines[$i], $ExcludePattern)) { continue }
                    $hits += ('{0}:{1}: {2}' -f $f, ($i + 1), $lines[$i].Trim())
                }
            }
        }
        return $hits
    }
    function File-Missing([string]$Rel) { -not (Test-Path (Join-Path $repo ($Rel -replace '/', '\'))) }

    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check([string]$Id, [string]$Level, [string]$Status, [string]$Detail, [string[]]$Hits) {
        if ($null -eq $Hits) { $Hits = @() }
        $checks.Add([pscustomobject]@{ id = $Id; level = $Level; status = $Status; detail = $Detail; hits = @($Hits) })
    }

    # ===== BLOCKING A：AGENTS.md 红线（既有）=====

    # A1 Core 只许 import Foundation（红线 2）
    $hits = Find-Hits $coreFiles '^import\s+(?!Foundation\b)\w+'
    Add-Check 'core-import-foundation-only' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDeskCore/Sources 只允许 import Foundation（AGENTS.md 红线 2）" $hits

    # A2 App 层禁 iOS 17+ API（iOS 16 基线）
    $hits = Find-Hits $appFiles '@Observable\b|@Bindable\b|\bContentUnavailableView\b|\.(scrollTargetBehavior|scrollPosition)\b|\bSwiftData\b'
    Add-Check 'app-no-ios17-api' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 禁 iOS 17+ API：@Observable/@Bindable/ContentUnavailableView/.scrollTargetBehavior/.scrollPosition/SwiftData" $hits

    # A3 禁双指轨迹（docs/42 不变量）
    $hits = Find-Hits $appFiles 'minimumNumberOfTouches\s*=\s*2'
    Add-Check 'app-no-two-finger' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 禁 minimumNumberOfTouches = 2（双指轨迹退役）" $hits

    # A4 Feature 层禁直接引用 PHAsset（单向依赖：Features → Domain → Core → System）
    $hits = Find-Hits $featFiles '\bPHAsset\b'
    Add-Check 'feature-no-phasset' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/Features/ 禁直接引用 PHAsset（统一 PhotoItem）" $hits

    # A5 删除文案红线（红线 1）：否定句合规表述（不提供/不能/禁用等）不判违规
    $hits = Find-Hits $appFiles '彻底删除|永久删除' '不提供|不能|不会|不可|无法|禁用|永不|只把|吗'
    Add-Check 'wording-no-permanent-delete' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 禁肯定语气的「彻底删除/永久删除」文案（排除否定句：不提供/不能/不会/不可/无法/禁用/永不/只把/吗）" $hits

    # A6 禁活跃框选符号（docs/42：Marquee 全家退役，禁复活）
    $hits = Find-Hits $appFiles 'MarqueeOverlayView|Marquee-Overlay|lastMarqueeRect|hitTest\(rectInContent:|HitRect|MarqueeSelectionPolicy\.resolved'
    Add-Check 'app-no-marquee-symbols' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 禁活跃框选符号：MarqueeOverlayView/Marquee-Overlay/lastMarqueeRect/hitTest(rectInContent:/HitRect/MarqueeSelectionPolicy.resolved" $hits

    # A7 禁 try! / as!（App + Core 源码）
    $hits = @() + (Find-Hits $appFiles 'try!|as!') + (Find-Hits $coreFiles 'try!|as!')
    Add-Check 'no-try-bang-as-bang' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 与 PhotoDeskCore/Sources 禁 try! / as!" $hits

    # ===== BLOCKING B：M19 行带契约（本轮新增；改造前预期 FAIL——即红基线）=====

    # B1 GridHitTester 必须提供 rowBandHitTest（docs/42 §3.2）
    $relTester = 'PhotoDesk/Features/Library/GridHitTester.swift'
    if (File-Missing $relTester) {
        Add-Check 'gridhittester-rowbandhittest' 'BLOCKING' 'FAIL' "$relTester 文件不存在" @()
    } else {
        $hits = Find-Hits @($relTester) 'func\s+rowBandHitTest'
    Add-Check 'gridhittester-rowbandhittest' 'BLOCKING' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "GridHitTester 必须实现 func rowBandHitTest(from:to:)（行带命中唯一单元）" $hits
    }

    # B2 生产选择路径不得仍以 hitTestLine 为选择结果
    $relVc = 'PhotoDesk/Features/Library/LibraryViewController.swift'
    if (File-Missing $relVc) {
        Add-Check 'production-trail-provider-band' 'BLOCKING' 'FAIL' "$relVc 文件不存在" @()
    } else {
        $text = Get-Text $relVc
        $stillLine = [regex]::IsMatch($text, 'trailHitProvider[\s\S]{0,800}?hitTestLine\(')
        $hasBand = [regex]::IsMatch($text, 'trailHitProvider[\s\S]{0,800}?rowBandHitTest')
        $hits = @()
        if ($stillLine) { $hits += 'LibraryViewController.swift: trailHitProvider 闭包内引用 hitTestLine（未接行带展开）' }
    Add-Check 'production-trail-provider-band' 'BLOCKING' $(if ($hasBand) { 'PASS' } else { 'FAIL' }) "trailHitProvider 必须走行带展开（rowBandHitTest）；直连 hitTestLine = 逐格语义残留（docs/42 §3.2）" $hits
    }

    # B3 行带几何必须 scope 过滤（Core 侧：RowBandMap 供 scope 能力）
    $relMap = 'PhotoDeskCore/Sources/PhotoDeskCore/RowBandMap.swift'
    if (File-Missing $relMap) {
        Add-Check 'band-scope-core' 'BLOCKING' 'FAIL' "$relMap 文件不存在（T02 交付）" @()
    } else {
        $hits = Find-Hits @($relMap) 'scope'
    Add-Check 'band-scope-core' 'BLOCKING' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "RowBandMap 必须具备 scope 过滤能力（单月 scope 轨迹不泄漏，docs/42 §1 行为表）" $hits
    }

    # B4 App 侧事务构造必须带 scope（唯一写入口的 scope 输入）
    $relCtl = 'PhotoDesk/Features/Library/LibrarySelectionController.swift'
    if (File-Missing $relCtl) {
        Add-Check 'band-scope-app' 'BLOCKING' 'FAIL' "$relCtl 文件不存在" @()
    } else {
        $hits = Find-Hits @($relCtl) 'scope:\s*scopeProvider\(\)'
    Add-Check 'band-scope-app' 'BLOCKING' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "LibrarySelectionController 构造 SlideSelectTrail 必须传 scope: scopeProvider()" $hits
    }

    # B5 行带展开必须行主序（几何派生自真实 attributes 字段，禁 DSSpacing 推算）
    if (File-Missing $relMap) {
        Add-Check 'band-row-major-core' 'BLOCKING' 'FAIL' "$relMap 文件不存在（T02 交付）" @()
    } else {
        $text = Get-Text $relMap
        $missing = @()
        foreach ($token in @('firstRowMinY', 'rowHeight', 'columns')) {
            if (-not $text.Contains($token)) { $missing += $token }
        }
    Add-Check 'band-row-major-core' 'BLOCKING' $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) "RowBandMap 行主序几何必须基于真实 attributes 派生字段 firstRowMinY/rowHeight/columns" $(if ($missing.Count -gt 0) { @('RowBandMap.swift 缺少字段标记：' + ($missing -join ', ')) } else { @() })
    }

    # B6 测试契约：旧「cell 级命中」断言必须退役（T06/T08 重写前预期 FAIL）
    $oldNames = 'testLeftColumnTrailExcludesRightColumn|testDiagonalTrailDoesNotFillRectangle|testHorizontalPressDragTrailSelectsExactRow|testSelectAllTrailDeselectExactAndExitResets|testPreSelectedCellSurvivesTrail'
    $hits = @() + (Find-Hits $uiTests $oldNames) + (Find-Hits $unitTests $oldNames)
    Add-Check 'tests-old-cell-contract' 'BLOCKING' $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }) "UI/单测不得保留旧语义断言：左列下滑右列不得入选/斜拖不补全等（5 条冲突用例，docs/41 §4；T06/T08 重写）" $hits

    # ===== PRESENT：M19 交付物存在性（-Strict 时计入退出码）=====

    if (File-Missing $relMap) {
        Add-Check 'present-rowbandmap-swift' 'PRESENT' 'FAIL' "PhotoDeskCore/Sources/PhotoDeskCore/RowBandMap.swift 不存在（T02）" @()
    } else {
        Add-Check 'present-rowbandmap-swift' 'PRESENT' 'PASS' 'RowBandMap.swift 存在' @()
    }
    $hits = Find-Hits $appFiles 'rowBandHitTest'
    Add-Check 'present-rowbandhittest-symbol' 'PRESENT' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 必须出现 rowBandHitTest 符号（App 侧行带命中）" $hits
    $hits = Find-Hits $appFiles 'rowBandHitProvider'
    Add-Check 'present-rowbandprovider-symbol' 'PRESENT' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "PhotoDesk/ 必须出现 rowBandHitProvider 符号（VC 注入行带命中提供者，docs/42 §3.2）" $hits
    $hits = Find-Hits $coreTests 'RowBandMapTests'
    Add-Check 'present-rowbandmap-tests' 'PRESENT' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "PhotoDeskCore/Tests 必须出现 RowBandMapTests" $hits
    $uiSuite = 'PhotoDeskUITests/RowBandSlideSelectUITests.swift'
    if (File-Missing $uiSuite) {
        Add-Check 'present-band-ui-suite' 'PRESENT' 'FAIL' "$uiSuite 不存在（T08 行带 UI 套件）" @()
    } else {
        Add-Check 'present-band-ui-suite' 'PRESENT' 'PASS' '行带 UI 套件文件存在' @()
    }
    if (File-Missing $relVc) {
        Add-Check 'present-band-debug-field' 'PRESENT' 'FAIL' "$relVc 文件不存在" @()
    } else {
        $hits = Find-Hits @($relVc) 'band='
    Add-Check 'present-band-debug-field' 'PRESENT' $(if ($hits.Count -gt 0) { 'PASS' } else { 'FAIL' }) "LibraryViewController DEBUG Summary 必须暴露 band= 字段（行带深度取证）" $hits
    }

    # ===== INFO（不影响退出码）=====

    $projText = Get-Text 'project.yml'
    $mkt = [regex]::Match($projText, 'MARKETING_VERSION:\s*"([^"]+)"').Groups[1].Value
    $cur = [regex]::Match($projText, 'CURRENT_PROJECT_VERSION:\s*"([^"]+)"').Groups[1].Value
    Add-Check 'info-version' 'INFO' 'INFO' "MARKETING_VERSION=$mkt CURRENT_PROJECT_VERSION=$cur（T10 目标 1.8.0 (9)）" @()
    $optMinos = [regex]::Match($projText, 'iOS:\s*"([^"]+)"').Groups[1].Value
    $tgtMinos = ([regex]::Matches($projText, 'IPHONEOS_DEPLOYMENT_TARGET:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) -join '/'
    Add-Check 'info-deployment-target' 'INFO' 'INFO' "deploymentTarget iOS=$optMinos IPHONEOS_DEPLOYMENT_TARGET=$tgtMinos（基线 16.0）" @()
    $ciText = Get-Text '.github/workflows/ios.yml'
    $ipaName = [regex]::IsMatch($ciText, 'PhotoDesk-unsigned-ipa')
    $appName = [regex]::IsMatch($ciText, 'PhotoDesk-Simulator-app-zip')
    Add-Check 'info-ci-artifacts' 'INFO' 'INFO' "ios.yml 产物名：unsigned-ipa=$ipaName simulator-app-zip=$appName" @()
    $relExists = Test-Path (Join-Path $repo 'artifacts\release\1.8.0')
    Add-Check 'info-release-dir' 'INFO' 'INFO' "artifacts/release/1.8.0/ 存在=$relExists（T10 产出）" @()
    $hits = Find-Hits $appFiles 'hitTestLine'
    Add-Check 'info-hitTestLine-refs' 'INFO' 'INFO' "PhotoDesk/ 内 hitTestLine 引用（行带改造后应仅剩降级路径或清零）：" $hits

    # ===== 汇总与输出 =====

    $failBlocking = @($checks | Where-Object { $_.level -eq 'BLOCKING' -and $_.status -eq 'FAIL' })
    $failPresent  = @($checks | Where-Object { $_.level -eq 'PRESENT'  -and $_.status -eq 'FAIL' })
    $passCount    = @($checks | Where-Object { $_.status -eq 'PASS' }).Count
    $infoCount    = @($checks | Where-Object { $_.level -eq 'INFO' }).Count
    $exitCode = 0
    if ($failBlocking.Count -gt 0) { $exitCode = 2 } elseif ($Strict -and $failPresent.Count -gt 0) { $exitCode = 2 }

    $summary = [pscustomobject]@{
        generatedAt = $generatedAt
        root = $repo
        strict = [bool]$Strict
        totals = [pscustomobject]@{ checks = $checks.Count; pass = $passCount; failBlocking = $failBlocking.Count; failPresent = $failPresent.Count; info = $infoCount }
        exitCode = $exitCode
        checks = $checks
    }
    $jsonPath = Join-Path $OutDir 'audit-m19.json'
    $mdPath   = Join-Path $OutDir 'audit-m19.md'
    $outPath  = Join-Path $OutDir 'audit-m19.stdout.txt'
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('# M19 静态审查报告（audit-m19.ps1）')
    $md.Add('')
    $md.Add("generatedAt: $generatedAt")
    $md.Add('')
    $md.Add("- root: " + $repo)
    $md.Add("- strict: " + [bool]$Strict)
    $md.Add("- checks: $($checks.Count)（PASS $passCount / BLOCKING-FAIL $($failBlocking.Count) / PRESENT-FAIL $($failPresent.Count) / INFO $infoCount）")
    $md.Add("- exitCode: $exitCode")
    $md.Add('')
    foreach ($c in $checks) {
        $md.Add("## [$($c.status)] $($c.level) $($c.id)")
        $md.Add('')
        $md.Add($c.detail)
        if ($c.hits.Count -gt 0) {
            $md.Add('')
            foreach ($h in $c.hits) { $md.Add("- " + $h) }
        }
        $md.Add('')
    }
    Set-Content -LiteralPath $mdPath -Value ($md -join $nl) -Encoding UTF8

    $stdout = New-Object System.Collections.Generic.List[string]
    $stdout.Add("audit-m19 root=$repo strict=$([bool]$Strict) checks=$($checks.Count) pass=$passCount failBlocking=$($failBlocking.Count) failPresent=$($failPresent.Count) info=$infoCount exitCode=$exitCode")
    foreach ($c in $checks) {
        $stdout.Add("[$($c.status)] $($c.level) $($c.id) :: $($c.detail)")
        foreach ($h in $c.hits) { $stdout.Add("    $h") }
    }
    $stdoutText = $stdout -join $nl
    Set-Content -LiteralPath $outPath -Value $stdoutText -Encoding UTF8
    Write-Output $stdoutText
    exit $exitCode
}
catch {
    Write-Output "audit-m19 EXCEPTION: $($_.Exception.Message)"
    exit 3
}
