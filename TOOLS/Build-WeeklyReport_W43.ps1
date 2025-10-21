<# 
.SYNOPSIS
  Обгортка для збирання пакета архітектури з включенням Weekly-звіту W43.
  Викликає Build-DAOIndexPackage.ps1 з -ExtraInclude для звіту та (опційно) G-Map.

.EXAMPLES
  # Базовий запуск з підстановкою SHA, git commit/push та виводом Summary
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File "D:\CHECHA_CORE\TOOLS\Build-WeeklyReport_W43.ps1" `
    -GitCommit -Push -VerboseSummary

  # Додати в пакет G-Map (PNG/SVG)
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File "D:\CHECHA_CORE\TOOLS\Build-WeeklyReport_W43.ps1" `
    -ExtraInclude @("D:\CHECHA_CORE\DAO-GOGS\docs\architecture\visuals\G-Map_v2.0.png") `
    -GitCommit -Push
#>

[CmdletBinding()]
param(
  # Шляхи за замовчуванням — як у попередніх кроках
  [string]$RepoRoot        = "D:\CHECHA_CORE",
  [string]$ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture",
  [string]$ReportsDir      = "D:\CHECHA_CORE\DAO-GOGS\docs\reports",
  [string]$OutDir          = "D:\CHECHA_CORE\C03_LOG\reports",

  # Файл Weekly W43
  [string]$WeeklyReport    = "DAO-GOGS_Weekly_Report_W43.md",

  # Додаткові файли (G-Map, інші вкладення)
  [string[]]$ExtraInclude  = @(),

  # Метадані релізу архітектури (залишаємо v2.0)
  [string]$Version         = "v2.0",
  [string]$ReleaseDate     = (Get-Date -Format 'yyyy-MM-dd'),

  # Керування
  [switch]$DryRun,
  [switch]$GitCommit,
  [switch]$Push,
  [switch]$VerboseSummary
)

function Log([string]$m,[string]$lvl="INFO"){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$lvl] $ts $m"
}

# 1) Перевіряємо існування базових директорій
foreach($p in @($RepoRoot,$ArchitectureDir,$ReportsDir,$OutDir)){
  if (!(Test-Path -LiteralPath $p)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Log "Created missing directory: $p"
  }
}

# 2) Знаходимо скрипт-«пакувальник» архітектури
$builder = Join-Path $RepoRoot "TOOLS\Build-DAOIndexPackage.ps1"
if (!(Test-Path -LiteralPath $builder)){
  throw "Не знайдено $builder. Переконайся, що він існує (з попередніх кроків)."
}

# 3) Готуємо список ExtraInclude
$extras = @()

# Weekly звіт (повний шлях)
$weeklyPath = Join-Path $ReportsDir $WeeklyReport
if (Test-Path -LiteralPath $weeklyPath) {
  $extras += $weeklyPath
  Log "Weekly included: $weeklyPath"
} else {
  Log "Weekly report not found: $weeklyPath" "WARN"
}

# Додаткові, якщо передані
foreach($mask in $ExtraInclude){
  if ([string]::IsNullOrWhiteSpace($mask)) { continue }
  $resolved = Get-ChildItem -LiteralPath $mask -ErrorAction SilentlyContinue -File
  if (-not $resolved) { $resolved = Get-ChildItem $mask -ErrorAction SilentlyContinue -File }
  if ($resolved) {
    $extras += $resolved.FullName
    foreach($f in $resolved){ Log "Extra include: $($f.FullName)" }
  } else {
    Log "ExtraInclude not found: $mask" "WARN"
  }
}

# 4) Формуємо аргументи до Build-DAOIndexPackage.ps1
$commonArgs = @(
  "-ArchitectureDir", $ArchitectureDir,
  "-OutDir",          $OutDir,
  "-Version",         $Version,
  "-ReleaseDate",     $ReleaseDate
)
if ($DryRun)         { $commonArgs += "-DryRun" }
if ($GitCommit)      { $commonArgs += "-GitCommit" }
if ($Push)           { $commonArgs += "-Push" }
if ($VerboseSummary) { $commonArgs += "-VerboseSummary" }

# Підтримка ExtraInclude (потрібна оновлена версія Build-DAOIndexPackage.ps1)
if ($extras.Count -gt 0) {
  $commonArgs += "-ExtraInclude"
  $commonArgs += $extras
}

# 5) Запуск основного «пакувальника»
Log "Invoke Build-DAOIndexPackage.ps1"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $builder @commonArgs

$ec = $LASTEXITCODE
if ($ec -ne 0) {
  Log "Build-DAOIndexPackage exited with code $ec" "ERR"
  exit $ec
}

Log "Weekly wrapper finished OK"
exit 0
