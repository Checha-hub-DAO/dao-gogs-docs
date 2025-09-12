param(
  [string]$Root = "D:\CHECHA_CORE",
  [switch]$All,
  [switch]$BuildRelease,
  [string]$Version,
  [string]$NewReleasePath,
  [string[]]$ModulesToAdd = @(),
  [switch]$IntegrateG43,
  [string]$G43ZipPath,
  [switch]$RunWeekly,
  [string[]]$Modules = @('G35','G37','G43'),
  [switch]$UpdateDigest,
  [switch]$OpenDigest,
  [switch]$DryRun,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ==== Paths & setup ==========================================================
$ts     = Get-Date -f 'yyyyMMdd_HHmmss'
$logDir = Join-Path $Root 'C03\LOG\weekly_reports'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$master = Join-Path $logDir ("CHECHA_Weekly_{0}.log" -f $ts)

$Path_Builder      = Join-Path $Root 'C11\tools\Build_Shield4_Release_Fallback.ps1'
$Path_Integrator   = Join-Path $Root 'C11\tools\Integrate-DAOModule_v1.ps1'
$Path_Orchestrator = Join-Path $Root 'C11\C11_AUTOMATION\tools\Checha-Orchestrator.ps1'
$Path_Verifier     = Join-Path $Root 'C11\C11_AUTOMATION\tools\Run-DAOModule-VerifyWeekly.ps1'
$Path_G43Health    = Join-Path $Root 'C11\C11_AUTOMATION\tools\Check-G43-Health.ps1'

$BaseDir_Shield4   = Join-Path $Root 'C11\SHIELD4_ODESA'
$ReleasesDir       = Join-Path $BaseDir_Shield4 'releases'
$DistDir           = Join-Path $BaseDir_Shield4 'dist'
$VaultDAO          = Join-Path $Root 'C12\Vault\DAO'

# ==== Helpers ================================================================
function Write-Log {
  param([string]$Message,[string]$Level='INFO')
  $line = "{0} [{1,-5}] {2}" -f (Get-Date -f 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $Message
  if (-not $Quiet) { Write-Host $line }
  Add-Content -LiteralPath $master -Value $line
}

function Ensure-Path {
  param([string]$Path)
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

function Get-WeekPeriodString {
  $today = Get-Date
  $dow   = [int]$today.DayOfWeek  # Sun=0, Mon=1, ...
  $mon   = if ($dow -eq 0) { $today.AddDays(-6) } else { $today.AddDays(-( $dow - 1 )) }
  $sun   = $mon.AddDays(6)
  return ('{0:dd}–{1:dd}.{1:MM}.{1:yyyy}' -f $mon,$sun)
}

function Get-LatestDigestPath {
  param([string]$Dir)
  $file = Get-ChildItem $Dir -Filter 'G35_Weekly_Digest_*.md' -File -ea SilentlyContinue |
          Sort-Object LastWriteTime -Desc | Select-Object -First 1 -Expand FullName
  return $file
}

$failCount = 0

# Decide defaults if -All
if ($All) {
  $BuildRelease = $true
  $IntegrateG43 = $true
  $RunWeekly    = $true
  $UpdateDigest = $true
}

Write-Log "BEGIN Master: Root=$Root; All=$All; DryRun=$DryRun"

# ==== STEP 1: Build Release (Fallback) =======================================
if ($BuildRelease) {
  try {
    Write-Log "STEP BuildRelease"
    if ($DryRun) { Write-Log "DRYRUN: would build release via $Path_Builder" 'INFO' }
    else {
      if (-not (Test-Path $Path_Builder)) { throw "Builder not found: $Path_Builder" }
      if (-not $Version)       { throw "-Version is required for BuildRelease" }
      if (-not $NewReleasePath){ throw "-NewReleasePath is required for BuildRelease" }
      Ensure-Path $ReleasesDir
      $splat = @{
        BaseDir        = $BaseDir_Shield4
        NewReleasePath = $NewReleasePath
        Version        = $Version
        ModulesToAdd   = $ModulesToAdd
      }
      (& $Path_Builder @splat *>&1) | Tee-Object -FilePath (Join-Path $logDir ("build_{0}.log" -f $ts)) | Out-Null
      # pick latest vX zip
      $zip = Get-ChildItem $ReleasesDir -Filter ("SHIELD4_ODESA_release_{0}_*.zip" -f $Version) |
             Sort-Object LastWriteTime -Desc | Select-Object -First 1
      if (-not $zip) { throw "Release ZIP not found after build (v=$Version)" }
      $sha = (Get-FileHash $zip.FullName -Algorithm SHA256).Hash
      Add-Content -LiteralPath (Join-Path $ReleasesDir 'CHECKSUMS_RELEASES.txt') -Value ("{0}  {1}" -f $sha,$zip.Name)
      Set-Content -LiteralPath (Join-Path $ReleasesDir 'LATEST.txt') -Encoding UTF8 -Value @"
version: $Version
zip: $($zip.Name)
built_at: $(Get-Date -f 'yyyy-MM-dd HH:mm:ss')
"@
      Ensure-Path $DistDir
      Copy-Item $zip.FullName $DistDir -Force
      Write-Log ("Built: {0} | SHA256={1}" -f $zip.FullName,$sha)
    }
  }
  catch { Write-Log $_.Exception.Message 'ERROR'; $failCount++ }
}

# ==== STEP 2: Integrate G43 ==================================================
if ($IntegrateG43) {
  try {
    Write-Log "STEP IntegrateG43"
    if ($DryRun) { Write-Log "DRYRUN: would integrate G43 via $Path_Integrator"; }
    else {
      if (-not (Test-Path $Path_Integrator)) { throw "Integrator not found: $Path_Integrator" }
      Ensure-Path $VaultDAO
      $zipSel = $null
      if ($G43ZipPath) {
        if (-not (Test-Path $G43ZipPath)) { throw "ZIP not found: $G43ZipPath" }
        $zipSel = Get-Item $G43ZipPath
      } else {
        $cands = @()
        $cands += Get-ChildItem (Join-Path $env:USERPROFILE 'Downloads') -Filter 'G43*.zip' -File -ea SilentlyContinue
        if ($env:OneDrive) {
          foreach($od in @('Downloads','Завантаження')){
            $p = Join-Path $env:OneDrive $od; if (Test-Path $p) { $cands += Get-ChildItem $p -Filter 'G43*.zip' -File -ea SilentlyContinue }
          }
        }
        $cands += Get-ChildItem $VaultDAO -Filter 'G43*.zip' -File -ea SilentlyContinue
        $zipSel = $cands | Sort-Object LastWriteTime -Desc | Select-Object -First 1
        if (-not $zipSel) { throw "No G43*.zip discovered in Downloads/OneDrive/Vault" }
      }
      # copy to Vault if needed
      if ($zipSel.DirectoryName -ne $VaultDAO) {
        Copy-Item $zipSel.FullName (Join-Path $VaultDAO $zipSel.Name) -Force
      }
      # integrate (let tool auto-pick from Vault)
      (& $Path_Integrator -Module G43 *>&1) | Tee-Object -FilePath (Join-Path $logDir ("integrate_G43_{0}.log" -f $ts)) | Out-Null
      Write-Log ("Integrated G43 from {0}" -f $zipSel.FullName)
    }
  }
  catch { Write-Log $_.Exception.Message 'ERROR'; $failCount++ }
}

# ==== STEP 3: Run Weekly Orchestrator =======================================
if ($RunWeekly) {
  try {
    Write-Log "STEP RunWeekly"
    if ($DryRun) { Write-Log "DRYRUN: would run Orchestrator Weekly" }
    else {
      if (-not (Test-Path $Path_Orchestrator)) { throw "Orchestrator not found: $Path_Orchestrator" }
      $wk = Join-Path $logDir ("weekly_{0}.run.log" -f $ts)
      (& $Path_Orchestrator -Mode Weekly -Root $Root -Verbose *>&1) | Tee-Object -FilePath $wk | Out-Null
      Write-Log ("Weekly log: {0}" -f $wk)
    }
  }
  catch { Write-Log $_.Exception.Message 'ERROR'; $failCount++ }
}

# ==== STEP 4: Verify Modules (CSV) ===========================================
try {
  Write-Log "STEP VerifyModules => $($Modules -join ',')"
  if ($DryRun) { Write-Log "DRYRUN: would verify via $Path_Verifier" }
  else {
    if (-not (Test-Path $Path_Verifier)) { throw "Verifier not found: $Path_Verifier" }
    (& $Path_Verifier -Root $Root -Modules $Modules -Csv *>&1) | Tee-Object -FilePath (Join-Path $logDir ("verify_{0}.log" -f $ts)) | Out-Null
  }
}
catch { Write-Log $_.Exception.Message 'ERROR'; $failCount++ }

# locate latest CSV
$csvLatest = Get-ChildItem $logDir -Filter 'verify_weekly_*.csv' -File -ea SilentlyContinue |
             Sort-Object LastWriteTime -Desc | Select-Object -First 1 -Expand FullName
if ($csvLatest) { Write-Log ("CSV: {0}" -f $csvLatest) } else { Write-Log 'CSV not found' 'WARN' }

# ==== STEP 5: Update G35 Digest =============================================
if ($UpdateDigest) {
  try {
    Write-Log "STEP UpdateDigest"
    if ($DryRun) { Write-Log 'DRYRUN: would update G35 digest' }
    else {
      if (-not $csvLatest) { throw 'No CSV to update digest from' }
      $rows = Import-Csv $csvLatest
      $mdPath = Get-LatestDigestPath -Dir $logDir
      if (-not $mdPath) {
        $mdPath = Join-Path $logDir ("G35_Weekly_Digest_{0}.md" -f $ts)
@"
# G35 — Weekly Digest
**Період:** ___–___.MM.YYYY

**Коротко (3 події):**
- …
- …
- …

**Метрики (з дашборда):** Reach — ___; Engagement — ___; Subs — ___

**Статус модулів (сьогодні):**
| Module | Status | Code |
|---|---|---|
| G35 |  |  |
| G37 |  |  |
| G43 |  |  |

**Top-3 пости:** 1) ___  2) ___  3) ___

**Рішення (≤5):**
- …

**Фокус наступного тижня (3):**
1) Дія → ефект …
2) …
3) …

**Ризики / потреби:** • … • … • …
**Подяки:** …
"@ | Set-Content -Enc UTF8 -LiteralPath $mdPath
      }

      $period = Get-WeekPeriodString
      $tableLines = @(
        '| Module | Status | Code |'
        '|---|---|---|'
      ) + ($rows | Sort-Object Module | ForEach-Object { "| $($_.Module) | $($_.Status) | $($_.Code) |" })
      $tableStr = ($tableLines -join "`r`n") + "`r`n"

      $txt = Get-Content -LiteralPath $mdPath -Raw -Encoding UTF8
      $txt = [regex]::Replace($txt, '^\*\*Період:\*\*.*$', ("**Період:** {0}" -f $period), 'Multiline')
      $pattern = '(\*\*Статус модулів[^\r\n]*\r?\n)(?:\|.*\r?\n)+'
      if ([regex]::IsMatch($txt, $pattern)) { $txt = [regex]::Replace($txt, $pattern, ('$1' + $tableStr)) }
      else { $txt = $txt -replace '(\*\*Статус модулів[^\r\n]*\r?\n)', ('$1' + $tableStr) }
      Set-Content -LiteralPath $mdPath -Encoding UTF8 -Value $txt
      Write-Log ("Digest updated: {0}" -f $mdPath)
      if ($OpenDigest -and -not $Quiet) { notepad $mdPath }
    }
  }
  catch { Write-Log $_.Exception.Message 'ERROR'; $failCount++ }
}

Write-Log ("END Master | fails=$failCount")
if ($failCount -gt 0) { exit 1 } else { exit 0 }

