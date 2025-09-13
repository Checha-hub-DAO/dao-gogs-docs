# Smoke-All.ps1 — CHECHA_CORE quick sanity run
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Line($t){ Write-Host ("`n=== {0} ===" -f $t) -ForegroundColor Cyan }

# 0) Версія і шлях
Line "Env"
$ver = $PSVersionTable.PSVersion
$src = (Get-Command pwsh).Source
Write-Host ("PS v{0}.{1}.{2} @ {3}" -f $ver.Major,$ver.Minor,$ver.Patch,$src)

# 1) Release-скрипт (сухий прогін без розпаковки)
Line "Release script"
$BaseDir = 'D:\CHECHA_CORE\C11\SHIELD4_ODESA'
$MainZip = 'C:\Users\serge\Downloads\SHIELD4_ODESA_UltimatePack_test.zip'
$ModZip  = 'C:\Users\serge\Downloads\SHIELD4_ODESA_MegaPack_v1.0.zip'

if (-not (Test-Path $MainZip)) {
  $tmp = Join-Path $env:TEMP ("reltest_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  "Smoke ZIP $(Get-Date)" | Set-Content (Join-Path $tmp 'README.txt') -Encoding UTF8
  Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $MainZip -Force
}
if (-not (Test-Path $ModZip)) {
  $t2 = Join-Path $env:TEMP ("modtest_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
  New-Item -ItemType Directory -Force -Path $t2 | Out-Null
  "Module ZIP $(Get-Date)" | Set-Content (Join-Path $t2 'MODULE.txt') -Encoding UTF8
  Compress-Archive -Path (Join-Path $t2 '*') -DestinationPath $ModZip -Force
}

& pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C11\tools\Manage_Shield4_Release.ps1" `
   -BaseDir $BaseDir -NewReleasePath $MainZip -Version 'vSMOKE' -ModulesToAdd @($ModZip) -NoUnpack

# 2) Інтеграція DAO-модуля (тільки якщо ZIP є)
Line "DAO integrate"
$G43Zip = "C:\Users\serge\Downloads\G43_ITETA_Pack_v1.0.zip"
if (Test-Path $G43Zip) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C11\tools\Integrate-DAOModule_v1.ps1" `
     -Module G43 -ZipPath $G43Zip
} else {
  Write-Host "Skip: $G43Zip not found" -ForegroundColor Yellow
}

# 3) Валідація релізів
Line "Validate releases"
& pwsh -NoProfile -File "D:\CHECHA_CORE\C11\tools\Validate-Releases.ps1" -All
$rc = $LASTEXITCODE
Write-Host "Validate exit code: $rc"

# 4) Git статус
Line "Git"
git -C D:\CHECHA_CORE status
git -C D:\CHECHA_CORE log -1 --oneline

# Підсумок
Line "Summary"
if ($rc -eq 0) { Write-Host "✅ Smoke: OK" -ForegroundColor Green }
else           { Write-Host "⚠️ Smoke: WARN (rc=$rc)" -ForegroundColor Yellow }
exit $rc
