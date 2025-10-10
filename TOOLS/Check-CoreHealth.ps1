# D:\CHECHA_CORE\TOOLS\Check-CoreHealth.ps1
# ==========================================================
[CmdletBinding()]
param(
  [string]$Root   = "D:\CHECHA_CORE",
  [string]$LogDir = "D:\CHECHA_CORE\C03_LOG",
  [switch]$Quiet
)
$ErrorActionPreference = "Stop"

# --- Helpers ---
function Get-TimeStamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
function Combine-Path([string]$p1, [string]$p2){ [System.IO.Path]::Combine($p1,$p2) }

# Fallback console if Write-Console не підключено
if (-not (Get-Command Write-Ok -ErrorAction SilentlyContinue)) {
  function Write-Info([string]$m){ Write-Host ("[{0}] [INFO]  {1}" -f (Get-TimeStamp), $m) -ForegroundColor Cyan }
  function Write-Ok  ([string]$m){ Write-Host ("[{0}] [OK]    {1}" -f (Get-TimeStamp), $m) -ForegroundColor Green }
  function Write-Wrn ([string]$m){ Write-Host ("[{0}] [WARN]  {1}" -f (Get-TimeStamp), $m) -ForegroundColor Yellow }
  function Write-Err ([string]$m){ Write-Host ("[{0}] [ERROR] {1}" -f (Get-TimeStamp), $m) -ForegroundColor Red }
}

# --- Logging ---
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$logBase = [System.IO.Path]::Combine($LogDir, ("CoreHealth_{0}" -f (Get-Date -Format "yyyyMMdd_HHmm")))
$log = @(); $fail = 0; $warn = 0
function L([string]$s){ $script:log += $s; if(-not $Quiet){ Write-Host $s } }

if (-not $Quiet){ Write-Info ("CoreHealth started. Root={0}" -f $Root) }

# --- Paths (БЕЗ Join-Path масивів) ---
$req = @(
  "$Root\TOOLS",
  "$Root\TOOLS\CoreLoader.ps1",
  "$Root\TOOLS\Utils.Core\Write-Console.ps1",
  "$Root\TOOLS\Utils.TZ.ps1"
)
$rec = @(
  "$Root\C03_LOG",
  "$Root\C06_FOCUS",
  "$Root\C07_ANALYTICS",
  "$Root\REPORTS",
  "$Root\REPORTS\WEEKLY",
  "$Root\C13_LEARNING_FEEDBACK"
)

# --- Report ---
L "# Core Health Report"
L ("- Date: {0}" -f (Get-TimeStamp))
L ("- Root: {0}" -f $Root)
L ""

L "## Required paths"
foreach($p in $req){
  if(Test-Path -LiteralPath $p){ L ("- [OK] {0}" -f $p) }
  else { L ("- [ERR] Missing: {0}" -f $p); $fail++ }
}
L ""

L "## Recommended paths"
foreach($p in $rec){
  if(Test-Path -LiteralPath $p){ L ("- [OK] {0}" -f $p) }
  else { L ("- [WARN] Missing: {0}" -f $p); $warn++ }
}
L ""

L "## Environment"
if($env:CHECHA_CORE_INIT -eq "1"){ L "- [OK] CHECHA_CORE_INIT=1" } else { L "- [WARN] CHECHA_CORE_INIT not set"; $warn++ }
L ""

# --- Git sanity ---
try{
  Push-Location -LiteralPath $Root
  $top = (git rev-parse --show-toplevel 2>$null).Trim()
  L "## Git"
  if($top){
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    $dirty  = (git status --porcelain).Trim()
    L ("- [OK] Repo: {0}" -f $top)
    L ("- Branch: {0}" -f $branch)
    if([string]::IsNullOrWhiteSpace($dirty)){ L "- Worktree: clean" } else { L "- [WARN] Worktree: dirty"; $warn++ }
  } else {
    L "- [WARN] Not a git repository"; $warn++
  }
} catch {
  L ("- [WARN] Git check error: {0}" -f $_.Exception.Message); $warn++
} finally {
  Pop-Location -ErrorAction SilentlyContinue
}
L ""

# --- Summary & write ---
L "## Summary"
L ("- Errors: {0}" -f $fail)
L ("- Warnings: {0}" -f $warn)

$log | Set-Content -LiteralPath "$logBase.md" -Encoding UTF8

if($fail -gt 0){
  $alert = "$LogDir\CoreHealth_ALERT.txt"
  ("{0} Errors={1} Warnings={2}" -f (Get-TimeStamp), $fail, $warn) | Set-Content -LiteralPath $alert -Encoding ASCII
  if(-not $Quiet){ Write-Err ("CoreHealth FAILED. See: {0}.md; Alert: {1}" -f $logBase, $alert) }
  exit 2
} elseif($warn -gt 0){
  if(-not $Quiet){ Write-Wrn ("CoreHealth WARN. See: {0}.md" -f $logBase) }
  exit 1
} else {
  if(-not $Quiet){ Write-Ok ("CoreHealth OK. See: {0}.md" -f $logBase) }
  exit 0
}
# ==========================================================
