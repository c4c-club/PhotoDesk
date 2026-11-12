# scripts/audit-m16.ps1
# 职责说明：M16（1.6.0）全新基线审查（docs/28 §3.2 / docs/30 T00）——只读扫描当前源码，
# 确定性输出 audit.md / audit.json / root-cause.md / test-gap.md 四个文件；优先 rg，缺失时退回 Select-String。
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts/audit-m16.ps1 [-Root <仓库根>] [-OutDir artifacts/audit/2026-11-12] [-FailOnRedline]
# 退出码：0 正常；2 必需文件缺失，或 -FailOnRedline 且红线命中；3 环境错误。
# 确定性：除 generatedAt 时间戳外，两次运行输出逐字节一致（清单排序、路径统一正斜杠、固定文化格式）。
param(
    [string]$Root = "",
    [string]$OutDir = "artifacts/audit/2026-11-12",
    [switch]$FailOnRedline
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path.TrimEnd("\")
Set-Location $Root
$OutDirAbs = Join-Path $Root $OutDir
New-Item -ItemType Directory -Force -Path $OutDirAbs | Out-Null

$useRg = $null -ne (Get-Command rg -ErrorAction SilentlyContinue)

function Rel([string]$p) {
    if ($p.StartsWith($Root)) { return $p.Substring($Root.Length + 1).Replace('\', '/') }
    return $p.Replace('\', '/')
}

# 统一扫描：相对路径交给 rg（避免 Windows 绝对路径里的盘符冒号被当分隔符）；file/line/text 排序保证确定性
function Scan([string[]]$relFiles, [string]$pattern) {
    $hits = @()
    if ($useRg) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $out = & rg -n --no-heading --no-messages -- $pattern @relFiles 2>$null
        $ErrorActionPreference = $prevEap
        foreach ($l in $out) {
            $idx = $l.IndexOf(":")
            if ($idx -lt 1) { continue }
            $f = $l.Substring(0, $idx)
            $rest = $l.Substring($idx + 1)
            $idx2 = $rest.IndexOf(":")
            if ($idx2 -lt 0) { continue }
            $ln = 0
            if (-not [int]::TryParse($rest.Substring(0, $idx2), [ref]$ln)) { continue }
            $hits += [pscustomobject]@{ file = $f.Replace('\', '/'); line = $ln; text = $rest.Substring($idx2 + 1).Trim() }
        }
    } else {
        foreach ($f in $relFiles) {
            $abs = Join-Path $Root $f
            if (-not (Test-Path $abs)) { continue }
            foreach ($x in @(Select-String -Path $abs -Pattern $pattern -AllMatches)) {
                $hits += [pscustomobject]@{ file = $f.Replace('\', '/'); line = $x.LineNumber; text = $x.Line.Trim() }
            }
        }
    }
    return @($hits | Sort-Object file, line, text)
}

function Get-SwiftFiles([string]$relDir) {
    $full = Join-Path $Root $relDir
    if (-not (Test-Path $full)) { return @() }
    return @(Get-ChildItem $full -Recurse -Filter *.swift -File |
        Where-Object { $_.FullName -notmatch "[\\/]\.build[\\/]" } | Sort-Object FullName)
}

function Count-Lines([string]$abs) { return ([System.IO.File]::ReadAllLines($abs)).Count }

# ---- 必需文件门禁（缺失即过期，exit 2） ----
$required = @(
    "PhotoDesk/Features/Viewer/ZoomInteractionController.swift",
    "PhotoDesk/Features/Viewer/ZoomableImageCell.swift",
    "PhotoDesk/Features/Viewer/ViewerViewController.swift",
    "PhotoDesk/Features/Library/LibraryViewController.swift",
    "PhotoDesk/Features/Library/LibraryViewModel.swift",
    "PhotoDesk/Features/Library/SlideSelectGestureController.swift",
    "PhotoDesk/Features/Library/PhotoGridCell.swift",
    "PhotoDesk/Features/Library/LibraryPositionCoordinator.swift",
    "PhotoDesk/Core/Support/LibraryPositionStore.swift",
    "PhotoDesk/Core/Support/PositionFileStore.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/ZoomTransform.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/MarqueeSelectionPolicy.swift",
    "PhotoDeskCore/Sources/PhotoDeskCore/SelectionPolicy.swift",
    "project.yml"
)
$missingRequired = @($required | Where-Object { -not (Test-Path (Join-Path $Root $_)) })
if ($missingRequired.Count -gt 0) {
    Write-Host "[X] audit-m16 已过期，以下必需文件不存在："
    $missingRequired | ForEach-Object { Write-Host "    - $_" }
    exit 2
}

# ---- 1. 基线 ----
$branch = (git branch --show-current).Trim()
$head = (git rev-parse HEAD).Trim()
$lastCommit = (git log -1 --format="%H %ci %s").Trim()
$projectText = [System.IO.File]::ReadAllText((Join-Path $Root "project.yml"))
function Get-YamlValue([string]$key) {
    $m = [regex]::Match($projectText, '(?m)^\s*' + $key + '\s*:\s*"?([^"\r\n]+)"?')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ""
}
$versions = [ordered]@{
    MARKETING_VERSION          = Get-YamlValue "MARKETING_VERSION"
    CURRENT_PROJECT_VERSION    = Get-YamlValue "CURRENT_PROJECT_VERSION"
    IPHONEOS_DEPLOYMENT_TARGET = Get-YamlValue "IPHONEOS_DEPLOYMENT_TARGET"
    SWIFT_VERSION              = Get-YamlValue "SWIFT_VERSION"
}

# ---- 2. 规模与页面清单 ----
$dirs = @("PhotoDesk", "PhotoDeskCore/Sources", "PhotoDeskCore/Tests", "PhotoDeskTests", "PhotoDeskUITests")
$scale = [ordered]@{}
$allFiles = @()
foreach ($d in $dirs) {
    $fs = Get-SwiftFiles $d
    $lines = 0
    foreach ($f in $fs) { $lines += Count-Lines $f.FullName }
    $scale[$d] = [ordered]@{ files = $fs.Count; lines = $lines }
    $allFiles += $fs
}
$fileInventory = @($allFiles | ForEach-Object {
    [ordered]@{ file = (Rel $_.FullName); lines = Count-Lines $_.FullName }
})

$featureFiles = Get-SwiftFiles "PhotoDesk/Features"
$pageGroups = @($featureFiles | Group-Object { $_.Directory.Name } | Sort-Object Name)

# ---- 3. 红线 ----
$coreSources = @(Get-SwiftFiles "PhotoDeskCore/Sources" | ForEach-Object { Rel $_.FullName })
$appSources  = @(Get-SwiftFiles "PhotoDesk" | ForEach-Object { Rel $_.FullName })
$coreTests   = @(Get-SwiftFiles "PhotoDeskCore/Tests" | ForEach-Object { Rel $_.FullName })
$iosTests    = @(Get-SwiftFiles "PhotoDeskTests" | ForEach-Object { Rel $_.FullName })
$uiTests     = @(Get-SwiftFiles "PhotoDeskUITests" | ForEach-Object { Rel $_.FullName })
$repoSwift   = @($coreSources + $coreTests + $appSources + $iosTests + $uiTests)

$redlines = [ordered]@{}
$redlines.coreAppleImport = Scan $coreSources "^\s*import\s+(UIKit|SwiftUI|Photos|PhotosUI|Vision|CoreImage|CoreML|Accelerate|Metal|MetalKit|MapKit|LocalAuthentication|AVFoundation|Intents)\s*$"
$redlines.urlSession      = Scan $repoSwift "URLSession"
$redlines.tryForce        = Scan $repoSwift "try!\s"
$redlines.asForce         = Scan $repoSwift "as!\s"
$redlines.ios17Api        = Scan $repoSwift "@Observable|@Bindable|ContentUnavailableView|scrollTargetBehavior|scrollPosition|SwiftData|if\s+#available\(iOS\s*17"
$redlines.forbiddenCopy   = Scan $repoSwift "彻底删除|永久删除"
$redlineTotal = 0
foreach ($k in $redlines.Keys) { $redlineTotal += $redlines[$k].Count }

# 违规判定（确定性规则；规则同步写在本脚本头注释与 audit.md §2）
# 1) asForce：仅生产代码（PhotoDesk/**、PhotoDeskCore/Sources/**）计违规；测试 target 豁免（测试断言里的 CF 字典转换）
# 2) forbiddenCopy：命中行含否定/说明语境（不提供|禁用|禁止|不会|不是|并非|无需|没有|一律|吗？）豁免——否定句属合规说明（M15 先例 docs/05 变更 17）
# 3) 其余检查（coreAppleImport/urlSession/tryForce/ios17Api）：命中即违规
$violationRows = @()
$exemptRows = @()
foreach ($k in $redlines.Keys) {
    foreach ($h in $redlines[$k]) {
        $reason = ""
        if ($k -eq "asForce") {
            foreach ($tp in @("PhotoDeskTests/", "PhotoDeskUITests/", "PhotoDeskCore/Tests/")) {
                if ($h.file.StartsWith($tp)) { $reason = "豁免：测试 target 断言转换" }
            }
        } elseif ($k -eq "forbiddenCopy") {
            if ($h.text -match "不提供|禁用|禁止|不会|不是|并非|无需|没有|一律|吗？") { $reason = "豁免：否定句/说明语境" }
        }
        if ($reason -eq "") {
            $violationRows += [ordered]@{ check = $k; file = $h.file; line = $h.line; text = $h.text; reason = "违规" }
        } else {
            $exemptRows += [ordered]@{ check = $k; file = $h.file; line = $h.line; text = $h.text; reason = $reason }
        }
    }
}
$redlineViolations = $violationRows.Count

# ---- 4. P0-1A 查看器缩放证据 ----
$viewerFiles = @(
    "PhotoDesk/Features/Viewer/ZoomInteractionController.swift",
    "PhotoDesk/Features/Viewer/ZoomableImageCell.swift",
    "PhotoDesk/Features/Viewer/ViewerViewController.swift"
)
$p01a = [ordered]@{
    viewForZooming     = Scan $viewerFiles "viewForZooming"
    scrollDelegate     = Scan $viewerFiles "UIScrollViewDelegate"
    zoomScaleApi       = Scan $viewerFiles "setZoomScale|minimumZoomScale|maximumZoomScale"
    contentInset       = Scan $viewerFiles "contentInset"
    gestureStateAssign = Scan $viewerFiles "gesture\.state\s*="
    animatingGuard     = Scan @("PhotoDesk/Features/Viewer/ZoomInteractionController.swift") "guard !isAnimating"
    phaseGuardDrop     = Scan @("PhotoDesk/Features/Viewer/ZoomInteractionController.swift") "guard phase == \.(pinching|panning)"
    catransactionWrite = Scan @("PhotoDesk/Features/Viewer/ZoomableImageCell.swift") "CATransaction|imageView\.transform|imageView\.center"
    resetOnReuse       = Scan @("PhotoDesk/Features/Viewer/ZoomableImageCell.swift") "zoomController\.reset"
    policyClamp        = Scan @("PhotoDeskCore/Sources/PhotoDeskCore/ZoomTransform.swift") "isFinite|min\(|max\(|clamped|1\.\.\.5"
}

# ---- 5. P0-1B 网格捏合证据 ----
$lvc = @("PhotoDesk/Features/Library/LibraryViewController.swift")
$p01b = [ordered]@{
    pinchChangedColumn      = Scan $lvc "case \.changed|pinchTargetColumns"
    setColumnsAnimated      = Scan $lvc "setColumns\("
    setCollectionViewLayout = Scan $lvc "setCollectionViewLayout|collectionViewLayout\s*=\s*makeLayout"
    reloadVisibleItems      = Scan $lvc "reloadItems"
    scrollToInTransition    = Scan $lvc "scrollToItem"
    pinToVisibleBounds      = Scan $lvc "pinToVisibleBounds"
    gestureStateAssign      = Scan $lvc "gesture\.state\s*="
}

# ---- 6. P0-2 位置记忆证据 ----
$posStoreFiles = @(
    "PhotoDesk/Core/Support/LibraryPositionStore.swift",
    "PhotoDesk/Core/Support/PositionFileStore.swift"
)
$posMachine = @("PhotoDeskCore/Sources/PhotoDeskCore/PositionRestoreMachine.swift")
$posCoord = @("PhotoDesk/Features/Library/LibraryPositionCoordinator.swift")
$lvm = @("PhotoDesk/Features/Library/LibraryViewModel.swift")
$p02 = [ordered]@{
    saveCallSites      = Scan $lvc "positionCoordinator\.(saveNow|scheduleSave)|savePositionNow\(|flushPendingJumpSave\("
    storeSchema        = Scan ($posStoreFiles + $posCoord) "schema|Schema|SCHEMA|version\s*=|VERSION"
    restoreEntries     = Scan $lvc "beginRestore|attemptPositionRestore"
    settledGate        = Scan ($posMachine + $posCoord) "settled|isIndexComplete"
    verifyNilBranch    = Scan $lvc "anchorInData|anchorMinY|layoutMinY"
    machineVerifyNil   = @(Scan $posMachine "nil" | Where-Object { $_.text -match "anchorMinY|verify|fallback|guard" })
    vmFirstBatchWindow = Scan $lvm "fetchFirstBatch|windowStart|firstBatchWindowStart"
    vmHeadBackfill     = Scan $lvm "freshHead"
}

# ---- 7. P0-3 滑动多选证据 ----
$gridCellFiles = @("PhotoDesk/Features/Library/PhotoGridCell.swift")
$p03 = [ordered]@{
    marqueeGeometry      = Scan $lvc "marqueeGeometry"
    stickyHeaderOrigin   = Scan $lvc "layoutAttributesForSupplementaryView"
    visibleTraversal     = Scan $lvc "indexPathsForVisibleItems|visibleCells"
    countGate            = Scan $lvc "previous\.count != current\.count"
    updateSelectionCount = Scan $lvc "updateSelectionCount"
    badgeVisibility      = Scan $gridCellFiles "setSelectionVisible|isSelectedCell|selectionBadge\.isHidden"
    axValueDebugOnly     = Scan $gridCellFiles "accessibilityValue"
    scopeFromSnapshot    = Scan $lvc "currentItemsBySection\.flatMap"
    slideScopeProvider   = Scan $lvc "scopeProvider"
}

# ---- 8. 页面静态清单（入口/空态/错误态/按钮） ----
$pageRows = @()
$pageDetails = @()
foreach ($g in $pageGroups) {
    $dirRel = "PhotoDesk/Features/" + $g.Name
    $dirFiles = @($g.Group | ForEach-Object { Rel $_.FullName })
    $ids = @()
    foreach ($f in $g.Group) {
        $txt = [System.IO.File]::ReadAllLines($f.FullName)
        foreach ($l in $txt) {
            if ($l -match 'accessibilityIdentifier\s*=\s*"([^"]+)"') { $ids += $Matches[1] }
        }
    }
    $ids = @($ids | Sort-Object -Unique)
    $entryStr = "(none)"
    if ($ids.Count -gt 0) {
        $head8 = ($ids | Select-Object -First 8) -join ", "
        if ($ids.Count -gt 8) { $entryStr = $head8 + " …共" + $ids.Count } else { $entryStr = $head8 }
    }
    $emptyHits  = Scan $dirFiles "DSEmptyState|暂无|空库|EmptyState"
    $errorHits  = Scan $dirFiles "加载失败|showFailure|presentError|errorMessage|失败"
    $buttonHits = Scan $dirFiles "systemName:"
    $pageRows += [ordered]@{
        page       = $g.Name
        files      = $dirFiles.Count
        entries    = $entryStr
        emptyState = $emptyHits.Count
        errorState = $errorHits.Count
        buttons    = $buttonHits.Count
    }
    $pageDetails += [ordered]@{ page = $g.Name; files = $dirFiles; entryIds = $ids; emptyHits = $emptyHits; errorHits = $errorHits; buttonHits = $buttonHits }
}

# ---- 9. 测试清单 ----
function Get-TestInventory([string[]]$relFiles) {
    $classes = @(); $tests = @()
    foreach ($f in $relFiles) {
        $abs = Join-Path $Root $f
        $lines = [System.IO.File]::ReadAllLines($abs)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "class\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase") {
                $classes += [pscustomobject]@{ file = $f; line = $i + 1; name = $Matches[1] }
            }
            if ($lines[$i] -match "func\s+(test[A-Za-z0-9_]+)\s*\(") {
                $tests += [pscustomobject]@{ file = $f; line = $i + 1; name = $Matches[1] }
            }
        }
    }
    return [pscustomobject]@{ classes = @($classes); tests = @($tests) }
}
$coreInv = Get-TestInventory $coreTests
$iosInv  = Get-TestInventory $iosTests
$uiInv   = Get-TestInventory $uiTests

# ---- 10. root-cause.md（当前源码证据，不引用 docs/25/27 结论） ----
function EvidenceTable($hits, [int]$max = 40) {
    $rows = @("| 文件:行 | 代码 |", "|---|---|")
    $shown = @($hits | Select-Object -First $max)
    foreach ($h in $shown) {
        $t = $h.text.Replace('|', '\|')
        $rows += ("| {0}:{1} | {2} |" -f $h.file, $h.line, $t)
    }
    if ($hits.Count -gt $max) { $rows += ("| … |（其余 {0} 条见 audit.json） |" -f ($hits.Count - $max)) }
    return ($rows -join [string][char]10)
}

$generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz", [System.Globalization.CultureInfo]::InvariantCulture)

$rc = New-Object System.Text.StringBuilder
$rcTitle = "# M16 根因取证（fresh audit，仅当前源码证据）"
[void]$rc.AppendLine($rcTitle)
[void]$rc.AppendLine("")
[void]$rc.AppendLine("> 生成：audit-m16.ps1（generatedAt $generatedAt）。证据全部来自本轮对当前源码的扫描（同轮 audit.json 可交叉核对）；不引用 docs/25/27 的任何历史结论。")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("## P0-1A 查看器缩放（入口 A）")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**现象关联**：连续捏合缩小/放大时崩溃/黑屏/卡死（docs/28 §1 验收目标）。")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**证据（当前源码）**：")
[void]$rc.AppendLine("")
$rcEvA = EvidenceTable (@($p01a.animatingGuard) + @($p01a.phaseGuardDrop) + @($p01a.gestureStateAssign) + @($p01a.catransactionWrite) + @($p01a.resetOnReuse) + @($p01a.policyClamp))
[void]$rc.AppendLine($rcEvA)
[void]$rc.AppendLine("")
$rcTrigA = '**触发条件**：动画/收敛窗口（Phase = animating 或 settling）内再次捏合——handlePinch 的 .began 命中 guard !isAnimating 直接置 gesture.state = .cancelled（被取消手势的后续触摸事件仍会到达）；随后 UIKit 送达的 .changed/.ended 被 guard phase == .pinching 丢弃，状态机停在非 idle 窗口；动画块内 imageView.transform/center 持续改写，与 cell 复用/翻页 zoomController.reset 竞态。'
[void]$rc.AppendLine($rcTrigA)
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**根因分级**：R2 结构性（状态机在动画窗口拒绝新手势而不是并入事务）+ R3 概率时序（复用/翻页与动画竞态）。")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("## P0-1B 网格捏合换列（入口 B）")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**证据（当前源码）**：")
[void]$rc.AppendLine("")
$rcEvB = EvidenceTable (@($p01b.pinchChangedColumn) + @($p01b.setColumnsAnimated) + @($p01b.setCollectionViewLayout) + @($p01b.reloadVisibleItems) + @($p01b.scrollToInTransition) + @($p01b.pinToVisibleBounds))
[void]$rc.AppendLine($rcEvB)
[void]$rc.AppendLine("")
$rcTrigB = '**触发条件**：捏合 .changed 每跨一次列数阈值即调 setColumns(animated: true) → setCollectionViewLayout(makeLayout, animated: true) 启动动画布局过渡；过渡未完成再次跨阈值又起新过渡；过渡完成回调内 reloadItems(indexPathsForVisibleItems) 绕过 Diffable 数据源（同文件 viewDidLayoutSubviews 注释已确认与 dataSource.apply 撞车触发 _existingNumberOfItemsInSection abort 的先例），过渡中 scrollToItem(anchor) 再触发布局。连续快速捏合时事件与过渡交错即崩。'
[void]$rc.AppendLine($rcTrigB)
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**根因分级**：R1 直接崩溃（Diffable 批更新与动画布局过渡/裸 reloadItems 竞态）+ R2 结构性（捏合全程应单飞事务，逐帧换列无事务边界）。")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("## P0-2 上次浏览位置（概率事件）")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**证据（当前源码）**：")
[void]$rc.AppendLine("")
$rcEvC = EvidenceTable (@($p02.saveCallSites) + @($p02.storeSchema) + @($p02.restoreEntries) + @($p02.settledGate) + @($p02.verifyNilBranch) + @($p02.machineVerifyNil) + @($p02.vmFirstBatchWindow) + @($p02.vmHeadBackfill))
[void]$rc.AppendLine($rcEvC)
[void]$rc.AppendLine("")
$rcTrigC = '**触发条件**：三条链各自带概率——① 保存链：makePositionSnapshot 在无完整可见 cell（恢复遮罩期间、索引未完成、刚切查询）返回 nil，保存静默丢失；② 首批窗口链：fetchFirstBatch 以锚点为中心截断（windowStart = anchorIndex − batchSize/2），尾部/头部索引由后台补齐，恢复时 isIndexComplete 未就绪则 anchorMinY 走估算 layoutAttributes，scrollToItem 落点偏移；③ 回填链：头部回填 allItems = freshHead + allItems 前插后，contentOffset 依赖 enforceHeadInsertAnchor 逐布局 pass 收敛，收敛期间任何一次保存（scroll 防抖、dragging/decelerating/rest/resignActive）都会把脏 offset 写盘，下次冷启动按脏值恢复。'
[void]$rc.AppendLine($rcTrigC)
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**根因分级**：R3 概率时序（head 回填、恢复、用户滚动三者竞速）+ R4 假绿（UI 测试以 AX 值/宽松范围断言落点）。")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("## P0-3 滑动多选（不显示选中/数量不对）")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**证据（当前源码）**：")
[void]$rc.AppendLine("")
$rcEvD = EvidenceTable (@($p03.marqueeGeometry) + @($p03.stickyHeaderOrigin) + @($p03.visibleTraversal) + @($p03.countGate) + @($p03.updateSelectionCount) + @($p03.badgeVisibility) + @($p03.axValueDebugOnly) + @($p03.scopeFromSnapshot) + @($p03.slideScopeProvider))
[void]$rc.AppendLine($rcEvD)
[void]$rc.AppendLine("")
$rcTrigD = '**触发条件**：① 命中几何：marqueeGeometry 的 sectionOriginY 读 layoutAttributesForSupplementaryView 的当前 frame，而月份头 pinToVisibleBounds = true——粘性头被钉住时 minY ≠ 该 section 的静态原点，矩形命中整体偏移一个头高；② 计数：applySlideSelection 仅在 previous.count != current.count 时刷新计数——等量替换（框选与已选恰好数量相同）时顶部计数停在旧值；③ 渲染：角标可见性 = isSelectingVisible && isSelectedCell 双标志，configure/复用路径只置其一即缺角标；④ scope：enterSelectionMode 默认 scope 取 currentItemsBySection.flatMap（已提交快照）而非 filteredItems 全量，索引未完成时 scope 缺尾部照片。'
[void]$rc.AppendLine($rcTrigD)
[void]$rc.AppendLine("")
[void]$rc.AppendLine("**根因分级**：R2 结构性（几何/渲染/计数三处均非单一事实来源）+ R4 假绿（accessibilityValue 仅 DEBUG 写入，AX 断言不证明视觉）。")
[void]$rc.AppendLine("")
$rcRed = "## 红线扫描（本轮命中 " + $redlineTotal + " · 违规 " + $redlineViolations + "）"
[void]$rc.AppendLine($rcRed)
[void]$rc.AppendLine("")
foreach ($k in $redlines.Keys) {
    $vCount = 0
    foreach ($v in $violationRows) { if ($v.check -eq $k) { $vCount++ } }
    $line = "- " + $k + "：命中 " + $redlines[$k].Count + " · 违规 " + $vCount
    [void]$rc.AppendLine($line)
}
[void]$rc.AppendLine("")
$rcRedRule = "判定规则：asForce 仅生产代码计违规（测试 target 豁免）；forbiddenCopy 仅非否定语境计违规（否定句/说明语境属合规，M15 先例 docs/05 变更 17）；其余检查命中即违规。"
[void]$rc.AppendLine($rcRedRule)
[void]$rc.AppendLine("")
[void]$rc.AppendLine("## 与测试缺口的关系")
[void]$rc.AppendLine("")
[void]$rc.AppendLine("上述四条根因的红测试清单见同目录 test-gap.md（P0-1A→T01、P0-1B→T02、P0-2→T03、P0-3→T04、X01–X16→T11A）。")
Set-Content -Path (Join-Path $OutDirAbs "root-cause.md") -Value $rc.ToString() -Encoding UTF8

# ---- 11. test-gap.md（P0 + X01–X16 红测试计划） ----
$gapPlan = @(
    @{ id = "P0-1A"; gap = "查看器缩放无事务边界：动画中捏合被取消、复用/翻页与动画竞态；Core 侧缩放钳制无事务单测"; task = "T01"; classes = @("ViewerZoomTransactionTests（PhotoDeskTests）", "ZoomTransformTransactionBoundaryTests（PhotoDeskCore/Tests）") },
    @{ id = "P0-1B"; gap = "网格捏合逐帧换列无单飞事务；reloadItems 绕过 Diffable 无回归测试"; task = "T02"; classes = @("GridPinchTransactionTests（PhotoDeskTests）", "GridColumnsPolicyTests（PhotoDeskCore/Tests，若换列事务下沉 Core）") },
    @{ id = "P0-2"; gap = "保存触发矩阵、settled 门禁、verify nil 分支、head 回填补偿均无直接断言；UI 断言宽松（±2pt 未见）"; task = "T03"; classes = @("PositionRestoreV6Tests（PhotoDeskCore/Tests）", "PositionSaveTriggerMatrixTests（PhotoDeskTests）", "PositionFakeSettledGuardTests（PhotoDeskTests）") },
    @{ id = "P0-3"; gap = "粘性头几何命中、等量替换计数、badge 双标志渲染、scope 全量语义均无测试"; task = "T04"; classes = @("MarqueeStickyHeaderGeometryTests（PhotoDeskCore/Tests）", "SlideSelectGeometryTests（PhotoDeskTests）", "SelectionRenderSingleSourceTests（PhotoDeskTests）") }
)
$xPlan = @(
    @{ id = "X01"; gap = "BatchCommitCoordinator 批间失败丢 committed、队列不清"; cls = "BatchCommitPartialFailureTests" },
    @{ id = "X02"; gap = "PhotoWriter.createAlbum 按 title 重查取第一个同名相簿"; cls = "PhotoWriterCreateAlbumTests" },
    @{ id = "X03"; gap = "AssetRepository.isCloudOnly 恒 false，iCloud-only 无法识别"; cls = "AssetRepositoryCloudOnlyTests" },
    @{ id = "X04"; gap = "EditorViewController 裁剪遮罩/applyCrop 坐标空间混用"; cls = "EditorCropCoordinateTests" },
    @{ id = "X05"; gap = "EditorViewModel.applyAspect 读到已更新 transform，旋转/翻转被重置"; cls = "EditorViewModelAspectTests" },
    @{ id = "X06"; gap = "StorageStatsService 缓存回写 O(n²) 卡主线程"; cls = "StorageStatsPerfTests" },
    @{ id = "X07"; gap = "TrashBin.storeCopy 主线程同步拷贝大文件"; cls = "TrashBinAsyncCopyTests" },
    @{ id = "X08"; gap = "VaultViewModel 隐藏库一次取全部，绕过分批约束"; cls = "VaultPagedFetchTests" },
    @{ id = "X09"; gap = "AlbumDetailView.removeFromAlbum 不递减 total，loadMore 空转"; cls = "AlbumDetailTotalTests" },
    @{ id = "X10"; gap = "PhotoWriter.renameAlbum 未 trim/空标题校验"; cls = "PhotoWriterRenameValidationTests" },
    @{ id = "X11"; gap = "MemoryCache block-based observer token 泄漏"; cls = "MemoryCacheObserverTests" },
    @{ id = "X12"; gap = "purgeTrash 清空 TrashBin 不同步 UndoCenter"; cls = "TrashPurgeUndoTests" },
    @{ id = "X13"; gap = "DiagnosticsExporter 临时文件无生命周期所有者"; cls = "DiagnosticsCleanupTests" },
    @{ id = "X14"; gap = "AppLockController.isBiometryAvailable 判定写反、unlockedThisSession 未参与"; cls = "AppLockGateTests" },
    @{ id = "X15"; gap = "EditorViewController.revertTapped try? 静默吞错"; cls = "EditorRevertErrorTests" },
    @{ id = "X16"; gap = "ExportViewModel/ExportRenderer 导出临时文件不清理"; cls = "ExportTempCleanupTests" }
)

$tg = New-Object System.Text.StringBuilder
[void]$tg.AppendLine("# M16 测试缺口与红测试计划（fresh audit）")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("> 生成：audit-m16.ps1（generatedAt $generatedAt）。基线 = 864af86。计划类名以本文件为准；后续任务卡执行时若与类名有出入，以任务卡为准并在 docs/31 验收记录对齐。")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("## P0 缺口（红测试先行）")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("| 编号 | 缺口 | 计划新增测试类 | 任务 |")
[void]$tg.AppendLine("|---|---|---|---|")
foreach ($p in $gapPlan) {
    $row = "| " + $p.id + " | " + $p.gap + " | " + ($p.classes -join "<br>") + " | " + $p.task + " |"
    [void]$tg.AppendLine($row)
}
[void]$tg.AppendLine("")
[void]$tg.AppendLine("## §7A X01–X16 缺口（T11A 收口，每条红→绿）")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("| ID | 缺口（当前源码） | 计划新增测试类 | 现状 | 任务 |")
[void]$tg.AppendLine("|---|---|---|---|---|")
$existingClasses = @(($coreInv.classes + $iosInv.classes + $uiInv.classes) | ForEach-Object { $_.name } | Sort-Object -Unique)
foreach ($x in $xPlan) {
    $status = "缺失（红）"
    if ($existingClasses -contains $x.cls) { $status = "已有" }
    $row = "| " + $x.id + " | " + $x.gap + " | " + $x.cls + "（PhotoDeskTests） | " + $status + " | T11A |"
    [void]$tg.AppendLine($row)
}
[void]$tg.AppendLine("")
[void]$tg.AppendLine("## 假绿审计（现有断言盲区）")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("- PhotoGridCell.accessibilityValue 仅 #if DEBUG 写入（选中态 AX 与视觉可能分叉）——T04 必须断言真实图层（badge isHidden + borderWidth），AX 仅作辅助。")
[void]$tg.AppendLine("- 现有缩放/位置 UI 测试以宽松范围断言，无 ±2pt 精度与 500/200/20 次重复场景——T01–T03 各自补压力维度。")
[void]$tg.AppendLine("- Core 层 ZoomTransformPolicyTests/ZoomGeometryTransactionTests 存在但未覆盖事务边界（动画中并入/取消路径）——T01 下沉逻辑时补。")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("## 现有测试规模")
[void]$tg.AppendLine("")
[void]$tg.AppendLine("| 层 | 类数 | test 函数数 |")
[void]$tg.AppendLine("|---|---:|---:|")
$tg1 = "| PhotoDeskCore/Tests | " + $coreInv.classes.Count + " | " + $coreInv.tests.Count + " |"
$tg2 = "| PhotoDeskTests | " + $iosInv.classes.Count + " | " + $iosInv.tests.Count + " |"
$tg3 = "| PhotoDeskUITests | " + $uiInv.classes.Count + " | " + $uiInv.tests.Count + " |"
[void]$tg.AppendLine($tg1)
[void]$tg.AppendLine($tg2)
[void]$tg.AppendLine($tg3)
Set-Content -Path (Join-Path $OutDirAbs "test-gap.md") -Value $tg.ToString() -Encoding UTF8

# ---- 12. audit.json ----
$report = [ordered]@{
    generatedAt   = $generatedAt
    repo          = $Root
    branch        = $branch
    head          = $head
    lastCommit    = $lastCommit
    scanner       = $(if ($useRg) { "rg" } else { "Select-String" })
    versions      = $versions
    scale         = $scale
    fileInventory = $fileInventory
    redlines      = $redlines
    redlineTotal  = $redlineTotal
    redlineViolations = $redlineViolations
    violationRows = $violationRows
    exemptRows    = $exemptRows
    p0_1a         = $p01a
    p0_1b         = $p01b
    p0_2          = $p02
    p0_3          = $p03
    pages         = $pageRows
    pageDetails   = $pageDetails
    tests         = [ordered]@{
        coreClasses = $coreInv.classes.Count
        coreTests   = $coreInv.tests.Count
        iosClasses  = $iosInv.classes.Count
        iosTests    = $iosInv.tests.Count
        uiClasses   = $uiInv.classes.Count
        uiTests     = $uiInv.tests.Count
    }
}
$jsonPath = Join-Path $OutDirAbs "audit.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

# ---- 13. audit.md ----
$md = New-Object System.Text.StringBuilder
$mdTitle = "# PhotoDesk M16 基线审查（generatedAt $generatedAt）"
[void]$md.AppendLine($mdTitle)
[void]$md.AppendLine("")
[void]$md.AppendLine("## 1. 基线")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 项 | 值 |")
[void]$md.AppendLine("|---|---|")
$mdScanner = $(if ($useRg) { "rg" } else { "Select-String" })
[void]$md.AppendLine("| 分支 | $branch |")
[void]$md.AppendLine("| HEAD | $head |")
[void]$md.AppendLine("| 最后提交 | $lastCommit |")
[void]$md.AppendLine("| 扫描器 | $mdScanner |")
[void]$md.AppendLine("")
[void]$md.AppendLine("### 版本")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 键 | 值 |")
[void]$md.AppendLine("|---|---|")
foreach ($k in $versions.Keys) { $row = "| " + $k + " | " + $versions[$k] + " |"; [void]$md.AppendLine($row) }
[void]$md.AppendLine("")
[void]$md.AppendLine("### 规模")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 目录 | Swift 文件 | 行数 |")
[void]$md.AppendLine("|---|---:|---:|")
foreach ($k in $scale.Keys) { $row = "| " + $k + " | " + $scale[$k].files + " | " + $scale[$k].lines + " |"; [void]$md.AppendLine($row) }
[void]$md.AppendLine("")
$mdRed = "## 2. 红线（命中 " + $redlineTotal + " · 违规 " + $redlineViolations + "）"
[void]$md.AppendLine($mdRed)
[void]$md.AppendLine("")
[void]$md.AppendLine("| 检查 | 命中 | 违规 |")
[void]$md.AppendLine("|---|---:|---:|")
foreach ($k in $redlines.Keys) {
    $vCount = 0
    foreach ($v in $violationRows) { if ($v.check -eq $k) { $vCount++ } }
    $row = "| " + $k + " | " + $redlines[$k].Count + " | " + $vCount + " |"
    [void]$md.AppendLine($row)
}
[void]$md.AppendLine("")
[void]$md.AppendLine("判定规则（确定性）：asForce 仅生产代码计违规（测试 target 豁免）；forbiddenCopy 仅非否定语境计违规（否定句/说明语境属合规，M15 先例 docs/05 变更 17）；其余检查命中即违规。")
if ($exemptRows.Count -gt 0) {
    [void]$md.AppendLine("")
    [void]$md.AppendLine("### 豁免明细")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| 检查 | 文件:行 | 代码 | 豁免原因 |")
    [void]$md.AppendLine("|---|---|---|---|")
    foreach ($e in $exemptRows) {
        $t = $e.text.Replace('|', '\|')
        $row = "| " + $e.check + " | " + $e.file + ":" + $e.line + " | " + $t + " | " + $e.reason + " |"
        [void]$md.AppendLine($row)
    }
}
if ($violationRows.Count -gt 0) {
    [void]$md.AppendLine("")
    [void]$md.AppendLine("### 违规明细")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("| 检查 | 文件:行 | 代码 |")
    [void]$md.AppendLine("|---|---|---|")
    foreach ($v in $violationRows) {
        $t = $v.text.Replace('|', '\|')
        $row = "| " + $v.check + " | " + $v.file + ":" + $v.line + " | " + $t + " |"
        [void]$md.AppendLine($row)
    }
}
foreach ($k in $redlines.Keys) {
    if ($redlines[$k].Count -gt 0) {
        [void]$md.AppendLine("")
        $secRed = "### " + $k + " 明细"
        [void]$md.AppendLine($secRed)
        [void]$md.AppendLine("")
        $mdRedDetail = EvidenceTable $redlines[$k]
        [void]$md.AppendLine($mdRedDetail)
    }
}
$sections = @(
    @{ no = "3"; title = "P0-1A 查看器缩放证据"; obj = $p01a },
    @{ no = "4"; title = "P0-1B 网格捏合证据"; obj = $p01b },
    @{ no = "5"; title = "P0-2 位置记忆证据"; obj = $p02 },
    @{ no = "6"; title = "P0-3 滑动多选证据"; obj = $p03 }
)
foreach ($s in $sections) {
    $secHead = "## " + $s.no + ". " + $s.title
    [void]$md.AppendLine($secHead)
    [void]$md.AppendLine("")
    foreach ($k in $s.obj.Keys) {
        $sub = "### " + $s.no + "." + $k + "（" + $s.obj[$k].Count + " 处）"
        [void]$md.AppendLine($sub)
        [void]$md.AppendLine("")
        $mdEv = EvidenceTable $s.obj[$k] 20
        [void]$md.AppendLine($mdEv)
        [void]$md.AppendLine("")
    }
}
[void]$md.AppendLine("## 7. Features 页面静态清单（入口/空态/错误态/按钮）")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 页面目录 | 文件数 | 入口标识（前 8） | 空态命中 | 错误态命中 | 按钮符号 |")
[void]$md.AppendLine("|---|---:|---|---:|---:|---:|")
foreach ($p in $pageRows) {
    $row = "| " + $p.page + " | " + $p.files + " | " + $p.entries + " | " + $p.emptyState + " | " + $p.errorState + " | " + $p.buttons + " |"
    [void]$md.AppendLine($row)
}
[void]$md.AppendLine("")
[void]$md.AppendLine("## 8. 测试清单")
[void]$md.AppendLine("")
[void]$md.AppendLine("| 层 | 类数 | test 函数数 |")
[void]$md.AppendLine("|---|---:|---:|")
[void]$md.AppendLine($tg1)
[void]$md.AppendLine($tg2)
[void]$md.AppendLine($tg3)
[void]$md.AppendLine("")
[void]$md.AppendLine("## 9. 输出文件")
[void]$md.AppendLine("")
[void]$md.AppendLine("- audit.md（本文件）")
[void]$md.AppendLine("- audit.json")
[void]$md.AppendLine("- root-cause.md")
[void]$md.AppendLine("- test-gap.md")
Set-Content -Path (Join-Path $OutDirAbs "audit.md") -Value $md.ToString() -Encoding UTF8

# ---- 14. 收尾门禁 ----
$outFiles = @("audit.md", "audit.json", "root-cause.md", "test-gap.md") | ForEach-Object { Join-Path $OutDirAbs $_ }
$missingOut = @($outFiles | Where-Object { -not (Test-Path $_) })
if ($missingOut.Count -gt 0) {
    Write-Host "[X] 必需输出文件缺失："
    $missingOut | ForEach-Object { Write-Host "    - $_" }
    exit 2
}
if ($FailOnRedline -and $redlineViolations -gt 0) {
    Write-Host "[X] 红线违规 $redlineViolations 处（-FailOnRedline），exit 2。明细见 audit.md 第 2 节。"
    exit 2
}
Write-Host "[OK] audit-m16 完成：branch=$branch head=$($head.Substring(0,7)) 红线命中=$redlineTotal 违规=$redlineViolations 输出目录=$OutDir"
exit 0