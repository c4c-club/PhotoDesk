param([string]$Path)
$bytes = [System.IO.File]::ReadAllBytes($Path)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  Write-Output "BOM: present"
  exit 0
}
$text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $true))
Write-Output "BOM: added"
