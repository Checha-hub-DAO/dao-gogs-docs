# ============================
# Run-WeeklyPipeline.ps1
# ============================
param(
  [string]  $RepoRoot = 'D:\CHECHA_CORE',
  [datetime]$WeekEnd  = (Get-Date)
)

# --- Ensure tools in PATH (важливо для SYSTEM)
$env:Path += ';C:\Program Files\Git\bin;C:\Program Files\GitHub CLI;C:\Program Files\GitHub CLI\bin;C:\Program Files\PowerShell\7'

# --- Import modules (psm1 to avoid psd1 encoding issues)
Import-Module "D:\CHECHA_CORE\TOOLS\Utils.Core\Utils.Core.psd1" -Force -ErrorAction Stop
Import-Module "D:\CHECHA_CORE\TOOLS\Checha.Reports\Checha.Reports.psm1" -Force -ErrorAction Stop

# --- Logs
$logDir = Join-Path $RepoRoot "C03_LOG\SCHED"
$null = New-Item -ItemType Directory -Force -Path $logDir
$runStamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
$logMain  = Join-Path $logDir ("WEEKLY_{0}.log" -f $runStamp)
$logOut   = Join-Path $logDir "weekly_stdout.log"
$logErr   = Join-Path $logDir "weekly_stderr.log"

# --- Helper to append safe lines to stdout/stderr logs
function Write-Std {
  param([string]$Line)
  Add-Content -LiteralPath $logOut -Value $Line
}
function Write-Err {
  param([string]$Line)
  Add-Content -LiteralPath $logErr -Value $Line
}

# --- Basic diag header
Write-Std ("=== Weekly pipeline start @ {0} ===" -f (Get-Date).ToString('u'))
Write-Std ("Host={0} PSV={1}" -f $Host.Name, $PSVersionTable.PSVersion)
Write-Std ("RepoRoot={0}" -f $RepoRoot)

# --- Force Kyiv TZ for computations
$WeekEndKyiv = (Get-KyivDate -Base $WeekEnd).Date
Write-Std ("WeekEndKyiv={0}" -f $WeekEndKyiv.ToString('yyyy-MM-dd'))

# --- Ensure working directory
try {
  Push-Location -Path $RepoRoot
} catch {
  Write-Err ("Cannot set location to RepoRoot: {0}" -f $_)
  throw
}

# --- Tooling presence + GH token
$gitPath = (Get-Command git  -ErrorAction SilentlyContinue)?.Source
$ghPath  = (Get-Command gh   -ErrorAction SilentlyContinue)?.Source
$hasTok  = [bool]$env:GH_TOKEN

Write-Std ("git={0}" -f ($gitPath   ?? '(not found)'))
Write-Std ("gh ={0}" -f ($ghPath    ?? '(not found)'))
Write-Std ("GH_TOKEN?={0}" -f $hasTok)

if (-not $gitPath) { Write-Err "git not found in PATH"; }
if (-not $ghPath)  { Write-Err "gh  not found in PATH"; }
if (-not $hasTok)  { Write-Err "GH_TOKEN not set (Machine env). gh will likely fail on GitHub operations."; }

# --- Optional: quick non-interactive sanity check (doesn't fail the run)
try {
  if ($hasTok -and $ghPath) {
    & gh api /rate_limit *> $null
    if ($LASTEXITCODE -ne 0) { Write-Err "gh api /rate_limit failed (token/SSO/permissions?)" }
    else { Write-Std "gh token OK (rate_limit reachable)" }
  }
} catch {
  Write-Err ("gh api sanity-check exception: {0}" -f $_.Exception.Message)
}

# --- Main run
$op = Start-Op "Scheduled Weekly Pipeline"
try {
  # звіт -> тег -> реліз (усередині Publish-WeeklyAll власні логи Info/Err)
  Publish-WeeklyAll -RepoRoot $RepoRoot -WeekEnd $WeekEndKyiv
  Info "OK: pipeline finished"
  Write-Std "Pipeline finished successfully."
}
catch {
  Err  ("FAILED: {0}" -f $_)
  Write-Err ("Pipeline failed: {0}" -f $_)
  throw
}
finally {
  $opDone = Stop-Op $op
  $stamp  = (Get-KyivDate).ToString('yyyy-MM-dd HH:mm:ss')
  Add-Content -LiteralPath $logMain -Value ("[{0}] Duration: {1}" -f $stamp, $opDone.Duration)

  # повертаємось у попередню локацію
  try { Pop-Location } catch {}
  Write-Std ("=== Weekly pipeline end @ {0} ===" -f (Get-Date).ToString('u'))
}
