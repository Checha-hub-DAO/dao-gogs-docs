# ==========================================================
# File: D:\CHECHA_CORE\TOOLS\Utils.Core\Write-Console.ps1
# Purpose: Standardized colored console output for CHECHA tools
# ==========================================================

function Get-TimeStamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }

function Write-Info([string]$msg) {
  Write-Host ("[{0}] [INFO]  {1}" -f (Get-TimeStamp), $msg) -ForegroundColor Cyan
}
function Write-Ok([string]$msg) {
  Write-Host ("[{0}] [OK]    {1}" -f (Get-TimeStamp), $msg) -ForegroundColor Green
}
function Write-Wrn([string]$msg) {
  Write-Host ("[{0}] [WARN]  {1}" -f (Get-TimeStamp), $msg) -ForegroundColor Yellow
}
function Write-Err([string]$msg) {
  Write-Host ("[{0}] [ERROR] {1}" -f (Get-TimeStamp), $msg) -ForegroundColor Red
}
function Write-Step([string]$msg) {
  Write-Host ("[{0}] [STEP]  {1}" -f (Get-TimeStamp), $msg) -ForegroundColor Magenta
}

Write-Host ("[{0}] [CHECHA] Utils.Core\Write-Console.ps1 loaded ✅" -f (Get-TimeStamp)) -ForegroundColor DarkGray
# ==========================================================
