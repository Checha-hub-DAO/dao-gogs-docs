# ==========================================================
# File: D:\CHECHA_CORE\TOOLS\CoreLoader.ps1
# Purpose: Unified loader for CHECHA_CORE tools and utilities
# Author: С.Ч. (CheCha System)
# ==========================================================

param(
    [switch]$Quiet
)

# --- 1) Helper: timestamp ---
function Get-TimeStamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }

# --- 2) Root and paths ---
$Root = Split-Path -Parent $PSScriptRoot
$UtilsCore = Join-Path $PSScriptRoot "Utils.Core"
$ConsoleMod = Join-Path $UtilsCore "Write-Console.ps1"
$TZMod      = Join-Path $PSScriptRoot "Utils.TZ.ps1"
$LogMod     = Join-Path $PSScriptRoot "Utils.Log.ps1"

# --- 3) Load console logger first ---
if (Test-Path $ConsoleMod) {
    . $ConsoleMod
} else {
    Write-Host "[{0}] [WARN] Console module missing → $ConsoleMod" -f (Get-TimeStamp) -ForegroundColor Yellow
}

# --- 4) Load other utils if available ---
if (Test-Path $TZMod)  { . $TZMod;  Write-Info "Utils.TZ loaded." }
if (Test-Path $LogMod) { . $LogMod; Write-Info "Utils.Log loaded." }

# --- 5) Show banner unless quiet ---
if (-not $Quiet) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor DarkGray
    Write-Host ("[{0}] [CHECHA CORE INIT ✅]" -f (Get-TimeStamp)) -ForegroundColor Green
    Write-Host ("Root: {0}" -f $Root) -ForegroundColor Gray
    Write-Host "Modules:" -ForegroundColor Gray
    Write-Host (" - {0}" -f $ConsoleMod) -ForegroundColor Cyan
    if (Test-Path $TZMod)  { Write-Host (" - {0}" -f $TZMod)  -ForegroundColor Cyan }
    if (Test-Path $LogMod) { Write-Host (" - {0}" -f $LogMod) -ForegroundColor Cyan }
    Write-Host "==================================================" -ForegroundColor DarkGray
    Write-Host ""
}

# --- 6) Export indicator ---
$env:CHECHA_CORE_INIT = "1"
if (-not $Quiet) { Write-Ok "CHECHA_CORE environment initialized." }

# --- 7) Core health (silent) ---
try {
  $chk = Join-Path $PSScriptRoot "Check-CoreHealth.ps1"
  if (Test-Path $chk) {
    & $chk -Root (Split-Path -Parent $PSScriptRoot) -Quiet | Out-Null
    # Не шумимо при OK/WARN; ALERT створюється самим чекером
  } else {
    Write-Wrn ("CoreHealth script missing: {0}" -f $chk)
  }
} catch {
  Write-Wrn ("CoreHealth invocation failed: {0}" -f $_.Exception.Message)
}

# ==========================================================
