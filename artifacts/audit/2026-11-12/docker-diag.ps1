$paths = @(
  'C:\Program Files\Docker\Docker\Docker Desktop.exe',
  "$env:LOCALAPPDATA\Docker\Docker Desktop.exe",
  "$env:ProgramFiles\Docker\Docker\frontend\Docker Desktop.exe"
)
foreach ($p in $paths) { Write-Output ("PATH_EXISTS: " + $p + " = " + (Test-Path $p)) }
Write-Output "--- Docker processes ---"
$procs = Get-Process | Where-Object { $_.Name -like '*Docker*' -or $_.Name -like '*com.docker*' }
if ($procs) { $procs | Select-Object Name, Id | Format-Table -AutoSize | Out-String -Width 120 | Write-Output }
else { Write-Output '(no docker processes)' }
Write-Output "--- WSL distros ---"
try { wsl -l -v 2>&1 | Out-String | Write-Output } catch { Write-Output ("wsl error: " + $_.Exception.Message) }
Write-Output "--- docker context ls ---"
docker context ls 2>&1 | Out-String | Write-Output
Write-Output "--- service state ---"
try { Get-Service com.docker.service -ErrorAction SilentlyContinue | Format-List Name,Status,StartType | Out-String | Write-Output } catch { Write-Output '(no com.docker.service)' }
