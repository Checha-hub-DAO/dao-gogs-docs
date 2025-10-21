# --- BOOTSTRAP for Build-DAOIndexPackage.ps1 (PS7) ---
[CmdletBinding()]
param(
  [string]$Version         = "v2.0",
  [string]$ReleaseDate     = (Get-Date -Format "yyyy-MM-dd"),
  [string]$OutDir          = "D:\CHECHA_CORE\C03_LOG\reports",
  [switch]$GitCommit,
  [switch]$Push,
  [switch]$NotifyPublic,
  [string]$ExtraMask       = "D:\CHECHA_CORE\DAO-GOGS\docs\reports\*.md",
  [string]$ArchitectureDir = ""
)

$ErrorActionPreference = "Stop"

function Log([string]$m,[string]$lvl="INFO"){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$lvl] $ts $m"
  Write-Host $line
  if ($global:__LogFile) { Add-Content -LiteralPath $global:__LogFile -Value $line }
}

# 1) Лог-файл
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$global:__LogFile = Join-Path $OutDir ("DAO-ARCHITECTURE_{0}_{1}.log" -f $Version,$ReleaseDate)

# 2) Основний скрипт пакувальника
$pack = "D:\CHECHA_CORE\TOOLS\Build-DAOIndexPackage.ps1"
if (-not (Test-Path -LiteralPath $pack)) { Log "Main script not found: $pack" "ERR"; exit 1 }

# 3) Розгортання ExtraMask у файли
$extra = @()
if ($ExtraMask) {
  $dir  = Split-Path -Path $ExtraMask -Parent
  $mask = Split-Path -Path $ExtraMask -Leaf
  if (Test-Path -LiteralPath $dir) {
    $extra = Get-ChildItem -LiteralPath $dir -Filter $mask -File -Recurse -ErrorAction SilentlyContinue |
             Select-Object -Expand FullName
  }
}

# 4) Формування аргументів для пакувальника
$argv = @(
  "-Version", $Version,
  "-ReleaseDate", $ReleaseDate,
  "-OutDir", $OutDir,
  "-VerboseSummary"
)
if ($GitCommit)    { $argv += "-GitCommit" }
if ($Push)         { $argv += "-Push" }
if ($NotifyPublic) { $argv += "-NotifyPublic" }

# Проксі параметра -ArchitectureDir, якщо задано
if ($ArchitectureDir -and -not [string]::IsNullOrWhiteSpace($ArchitectureDir)) {
  $argv += "-ArchitectureDir"
  $argv += $ArchitectureDir
}

# Передача масиву -ExtraInclude коректно (окремо прапорець і далі елементи)
if ($extra -and $extra.Count -gt 0) {
  $argv += "-ExtraInclude"
  $argv += $extra
}

Log ("Invoking Build-DAOIndexPackage.ps1 with args: {0}" -f ($argv -join " "))
& pwsh -NoProfile -ExecutionPolicy Bypass -File $pack @argv
$rc = $LASTEXITCODE
Log ("Build-DAOIndexPackage.ps1 exit code: {0}" -f $rc) $(if($rc -eq 0){'INFO'}else{'ERR'})
exit $rc
