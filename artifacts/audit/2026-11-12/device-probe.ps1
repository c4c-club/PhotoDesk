$ErrorActionPreference = 'Continue'
Write-Output '=== PnP (Apple/iPhone) ==='
$pnp = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'Apple|iPhone' } | Select-Object Status,Class,FriendlyName
if ($pnp) { $pnp | Format-Table -AutoSize | Out-String -Width 140 } else { Write-Output '(no Apple/iPhone PnP device)' }
Write-Output '=== idevice_id ==='
$c = Get-Command idevice_id -ErrorAction SilentlyContinue
if ($c) {
  Write-Output "FOUND: $($c.Source)"
  $ids = & idevice_id -l 2>&1 | Out-String
  Write-Output "idevice_id -l output: $ids"
} else { Write-Output 'NOT FOUND' }
Write-Output '=== pymobiledevice3 ==='
$pm = Get-Command pymobiledevice3 -ErrorAction SilentlyContinue
if ($pm) { pymobiledevice3 version 2>&1 | Out-String } else { Write-Output 'NOT FOUND' }
Write-Output '=== AltServer process ==='
$p = Get-Process -Name 'AltServer*' -ErrorAction SilentlyContinue
if ($p) { $p | Select-Object Name,Id,Path | Format-Table -AutoSize | Out-String -Width 140 } else { Write-Output 'NOT RUNNING' }
