[CmdletBinding()]
Param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Визначаємо корінь репо
if (-not $Root -or -not (Test-Path $Root)) {
  if ($env:GITHUB_WORKSPACE -and (Test-Path $env:GITHUB_WORKSPACE)) { $Root = $env:GITHUB_WORKSPACE }
  else { $Root = "D:\CHECHA_CORE" }
}

function Line($t){ Write-Host ("`n=== {0} ===" -f $t) -ForegroundColor Cyan }

# Логи всередині репо
$logDir = Join-Path $Root 'C03\LOG'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("smoke_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $log -Append | Out-Null

try {
  Line "Env"
  $ver = $PSVersionTable.PSVersion
  Write-Host ("PS v{0}.{1}.{2}" -f $ver.Major,$ver.Minor,$ver.Patch)
  Write-Host "Root = $Root"

  Line "Release script"
  $BaseDir = Join-Path $Root 'C11\SHIELD4_ODESA'

  # Куди складати тимчасові ZIP (Downloads, якщо нема — TEMP)
  $Downloads = [System.IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'),'Downloads')
  if (-not (Test-Path $Downloads)) { try { New-Item -ItemType Directory -Force -Path $Downloads | Out-Null } catch { $Downloads = $env:TEMP } }
  $MainZip = Join-Path $Downloads 'SHIELD4_ODESA_UltimatePack_test.zip'
  $ModZip  = Join-Path $Downloads 'SHIELD4_ODESA_MegaPack_v1.0.zip'

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

  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'C11\tools\Manage_Shield4_Release.ps1') `
      -BaseDir $BaseDir -NewReleasePath $MainZip -Version 'vSMOKE_CI' -ModulesToAdd @($ModZip) -NoUnpack

  Line "DAO integrate"
  $G43Zip = Join-Path $Downloads 'G43_ITETA_Pack_v1.0.zip'
  if (Test-Path $G43Zip) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'C11\tools\Integrate-DAOModule_v1.ps1') `
       -Module G43 -ZipPath $G43Zip -TargetRoot $Root
  } else {
    Write-Host "Skip: $G43Zip not found" -ForegroundColor Yellow
  }

  Line "Validate releases"
  & pwsh -NoProfile -File (Join-Path $Root 'C11\tools\Validate-Releases.ps1') -All -Root $Root
  $rc = $LASTEXITCODE
  Write-Host "Validate exit code: $rc"

  Line "Git (local)"
  git -C $Root status
  git -C $Root log -1 --oneline

  Line "Summary"
  if ($rc -eq 0) { Write-Host "✅ Smoke: OK" -ForegroundColor Green }
  else           { Write-Host "⚠️ Smoke: WARN (rc=$rc)" -ForegroundColor Yellow }
  exit $rc
}
finally { Stop-Transcript | Out-Null }
