# Import utils
$utilsPath = "D:\CHECHA_CORE\TOOLS\CheCha.Utils.psm1"
if (Test-Path -LiteralPath $utilsPath) { Import-Module $utilsPath -Force }
else { Write-Host "[WARN] Utils not found at $utilsPath (continuing)"; }

<# 
.SYNOPSIS
  Створення Weekly-звіту за ISO-тиждень (Wxx), підстановка дат, пакування з архітектурним пакетом.

.PARAMETER ISOWeek
  Номер ISO-тижня (1..53). Якщо не задано — визначається для сьогодні.

.PARAMETER Year
  Рік ISO-тижня. Якщо не задано — визначається для сьогодні.

.PARAMETER ExtraInclude
  Додаткові вкладення (PNG/SVG G-Map тощо).

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File D:\CHECHA_CORE\TOOLS\Build-WeeklyReport.ps1 `
    -ISOWeek 44 -Year 2025 -GitCommit -Push -VerboseSummary `
    -ExtraInclude "D:\CHECHA_CORE\DAO-GOGS\docs\architecture\visuals\G-Map_v2.0.png"
#>

[CmdletBinding()]
param(
  [int]$ISOWeek,
  [int]$Year,
  [string]$RepoRoot        = "D:\CHECHA_CORE",
  [string]$ArchitectureDir = "D:\CHECHA_CORE\DAO-GOGS\docs\architecture",
  [string]$ReportsDir      = "D:\CHECHA_CORE\DAO-GOGS\docs\reports",
  [string]$OutDir          = "D:\CHECHA_CORE\C03_LOG\reports",
  [string[]]$ExtraInclude  = @(),
  [string]$Version         = "v2.0",
  [string]$ReleaseDate     = (Get-Date -Format 'yyyy-MM-dd'),
  [switch]$DryRun,
  [switch]$GitCommit,
  [switch]$Push,
  [switch]$VerboseSummary
)

# optional: config merge
$cfgPath = "D:\CHECHA_CORE\TOOLS\dao.config.json"
if (Test-Path -LiteralPath $cfgPath) {
  $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
  if (-not $RepoRoot)        { $RepoRoot        = $cfg.RepoRoot }
  if (-not $ArchitectureDir) { $ArchitectureDir = $cfg.ArchitectureDir }
  if (-not $ReportsDir)      { $ReportsDir      = $cfg.ReportsDir }
  if (-not $OutDir)          { $OutDir          = $cfg.OutDir }
  if ($Version -eq "v2.0")   { $Version         = $cfg.Version }
}

function Log([string]$m,[string]$lvl="INFO"){ $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m" }

# ---- 1) ISO Week helpers (Europe/Kyiv) ----
function Get-IsoWeekStartEnd([int]$y,[int]$w){
  # ISO: тиждень починається в понеділок, тиждень 1 — той, що містить 4 січня.
  $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("FLE Standard Time") # Europe/Kyiv (Windows id)
  # Знаходимо четвер першого тижня (4 січня)
  $jan4Utc = [datetime]::SpecifyKind([datetime]"$y-01-04", 'Utc')
  $jan4Kyiv = [System.TimeZoneInfo]::ConvertTimeFromUtc($jan4Utc,$tz)
  # Понеділок тижня, що містить 4 січня:
  $dow = [int]$jan4Kyiv.DayOfWeek; if($dow -eq 0){ $dow = 7 }
  $monWeek1 = $jan4Kyiv.AddDays(1 - $dow)
  $start = $monWeek1.AddDays(7 * ($w - 1))
  $end   = $start.AddDays(6)
  # Нормалізуємо часи:
  $start = Get-Date $start.Date
  $end   = Get-Date $end.Date
  [pscustomobject]@{ Start=$start; End=$end }
}

# Автовизначення поточного ISO-тижня/року, якщо не подано
if(-not $ISOWeek -or -not $Year){
  $now = Get-Date
  $cul = [System.Globalization.CultureInfo]::GetCultureInfo("uk-UA")
  $cal = $cul.DateTimeFormat.Calendar
  $rule= [System.Globalization.CalendarWeekRule]::FirstFourDayWeek
  $dow = [System.DayOfWeek]::Monday
  $ISOWeek = $cal.GetWeekOfYear($now,$rule,$dow)
  $Year    = $now.Year
  # якщо перші дні січня входять до останнього ISO-тижня попереднього року
  if($ISOWeek -ge 52 -and $now.Month -eq 1){ $Year-- }
}

$span = Get-IsoWeekStartEnd -y $Year -w $ISOWeek
$wTag = ('W{0:00}' -f $ISOWeek)
$reportName = "DAO-GOGS_Weekly_Report_${wTag}.md"

Log "Weekly: $wTag ($($span.Start.ToString('yyyy-MM-dd')) → $($span.End.ToString('yyyy-MM-dd'))) / Year: $Year"

# ---- 2) Ensure dirs ----
foreach($p in @($RepoRoot,$ArchitectureDir,$ReportsDir,$OutDir)){
  if (!(Test-Path -LiteralPath $p)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Log "Created: $p"
  }
}

# ---- 3) Create/update Weekly Markdown ----
$weeklyPath = Join-Path $ReportsDir $reportName
if(-not (Test-Path -LiteralPath $weeklyPath)){
  $md = @"
---
title: "DAO-GOGS · Weekly Report · $wTag"
subtitle: "Огляд за $($span.Start.ToString('dd.MM.yyyy'))–$($span.End.ToString('dd.MM.yyyy')) (Europe/Kyiv)"
author: "С.Ч."
created: $((Get-Date).ToString('yyyy-MM-dd'))
updated: $((Get-Date).ToString('yyyy-MM-dd'))
status: "Draft"
tags: [DAO-GOGS, weekly, $wTag, analytics, CheChaCore]
version: "$wTag-$Year"
description: "Щотижневий стратегічно-аналітичний огляд системи DAO-GOGS."
---

# 🧭 DAO-GOGS · Weekly Report · $wTag

- **Період:** $($span.Start.ToString('dd.MM.yyyy'))–$($span.End.ToString('dd.MM.yyyy'))  
- **Стан системи:** ⬜ Draft ⬛ Final  
- **Джерела:** INDEX v2.0 (G01–G44), ITETA, LeaderIntel, MAT_RESTORE, DAO-FORMS, DAO-MEDIA.

## 1) Executive Summary
- ✅ …
- ✅ …
- ⚠️ …

## 2) Оновлення модулів (G01–G44)
| Код | Статус | Зміна | Вплив | Власник | Дата |
|-----|--------|-------|-------|---------|------|
| G07 | ✅ Active | … | … | … | … |
| …  | … | … | … | … | … |

## 3) Метрики та аналітика
### 3.1 Операційні показники
| Метрика | Значення | Δ | Ціль | Коментар |
|---------|----------|---|------|----------|
| Tasks done | … | … | … | … |

### 3.2 DAO-MEDIA (G04/G35)
| Показник | Значення | Δ | Коментар |
|----------|----------|---|----------|
| Публікації | … | … | … |

### 3.3 DAO-FORMS (G36)
| Форма | Відповідей | Статус | Нотатка |
|-------|------------|--------|---------|
| … | … | Open/Closed | … |

## 4) Рішення та політики
- R-1: …

## 5) Ризики та блокери
| ID | Ризик/Блокер | Імовірн. | Вплив | Власник | План |
|----|--------------|----------|-------|---------|------|
| RS-01 | … | Mid | High | … | … |

## 6) План на $([string]::Format('W{0:00}', $ISOWeek+1)) 
- 🎯 …

## 🔒 Підпис і контроль
**Підпис:** С.Ч.  
**SHA-256:** _заповнити після генерації_  
**Репозиторій:** DAO-GOGS MAIN → `docs/reports/`  
**Дата:** $((Get-Date).ToString('yyyy-MM-dd'))
"@
  Set-Content -LiteralPath $weeklyPath -Encoding UTF8 -Value $md
  Log "Weekly created: $weeklyPath"
}else{
  (Get-Item $weeklyPath).LastWriteTime = Get-Date
  Log "Weekly exists → touch timestamp: $weeklyPath"
}

# ---- 4) Collect extras (weekly + optional) ----
$extras = @($weeklyPath)
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

# ---- 5) Invoke main packer (expects ExtraInclude support) ----
$builder = Join-Path $RepoRoot "TOOLS\Build-DAOIndexPackage.ps1"
if (!(Test-Path -LiteralPath $builder)){ throw "Не знайдено $builder" }

$args = @(
  "-ArchitectureDir", $ArchitectureDir,
  "-OutDir",          $OutDir,
  "-Version",         $Version,
  "-ReleaseDate",     $ReleaseDate
)
if ($DryRun)         { $args += "-DryRun" }
if ($GitCommit)      { $args += "-GitCommit" }
if ($Push)           { $args += "-Push" }
if ($VerboseSummary) { $args += "-VerboseSummary" }
if ($extras.Count -gt 0) {
  $args += "-ExtraInclude"
  $args += $extras
}

Log "Invoke Build-DAOIndexPackage.ps1 for $wTag"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $builder @args
$ec = $LASTEXITCODE
if ($ec -ne 0){ Log "Builder exit code: $ec" "ERR"; exit $ec }

Log "Weekly $wTag packaged OK"
exit 0
