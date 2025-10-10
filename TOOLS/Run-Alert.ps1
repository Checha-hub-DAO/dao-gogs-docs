# D:\CHECHA_CORE\TOOLS\Run-Alert.ps1 (хвіст файла)
$ErrorActionPreference = 'Stop'

function RLog($m){
  $ts=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Add-Content -Encoding utf8 -LiteralPath 'D:\CHECHA_CORE\C07_ANALYTICS\Run-Alert.log' -Value "[$ts] $m"
}

try {
  $RepoRoot  = 'D:\CHECHA_CORE'
  $Tools     = Join-Path $RepoRoot 'TOOLS'
  $Analytics = Join-Path $RepoRoot 'C07_ANALYTICS'
  if(!(Test-Path $Tools)){ throw "TOOLS not found: $Tools" }
  if(!(Test-Path $Analytics)){ throw "ANALYTICS not found: $Analytics" }

  Set-Location -LiteralPath $RepoRoot

  RLog "START Run-Alert"
  Start-Sleep -Milliseconds (Get-Random -Min 100 -Max 1200)

  $notify = Join-Path $Tools 'Notify-If-Degraded.ps1'
  if(!(Test-Path $notify)){ throw "Notify script not found: $notify" }

  # ВАЖЛИВО: НЕ використовуємо $LASTEXITCODE для .ps1
  & $notify -RepoRoot $RepoRoot
  RLog "Notify OK"

  RLog "END Run-Alert (rc=0)"
  exit 0
}
catch {
  RLog ("ERROR: " + $_.Exception.Message)
  exit 1
}
