<#
.SYNOPSIS
  Створює/перевіряє тижневий тег формату weekly-YYYY-MM-DD_to_YYYY-MM-DD
  для місячних 7-денних блоків (1–7, 8–14, 15–21, 22–кінець місяця).
  Ідемпотентний: якщо тег існує локально/на origin — лише повідомляє.

.PARAMETER RepoRoot
  Корінь git-репозиторію (де є .git)

.PARAMETER Remote
  Назва віддаленого (origin за замовчуванням)

.PARAMETER WeekEnd
  Кінцева дата блоку (локальна, Europe/Kyiv). Якщо не вказано — береться сьогодні.

.PARAMETER Branch
  Очікувана гілка для постановки тега (reports за замовчуванням). Якщо '', перевірка вимикається.

.PARAMETER DryRun
  Лише показує дії без змін.

.EXAMPLE
  pwsh -File D:\CHECHA_CORE\TOOLS\New-WeeklyTag.ps1 -RepoRoot D:\CHECHA_CORE -DryRun

.EXAMPLE
  pwsh -File D:\CHECHA_CORE\TOOLS\New-WeeklyTag.ps1 -RepoRoot D:\CHECHA_CORE
#>

param(
  [string]  $RepoRoot = "D:\CHECHA_CORE",
  [string]  $Remote   = "origin",
  [datetime]$WeekEnd,
  [string]  $Branch   = "reports",
  [switch]  $DryRun
)

# ---------- helpers ----------
function Info([string]$msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Warn([string]$msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err ([string]$msg){ Write-Host "[ERR]  $msg" -ForegroundColor Red }
function Die ([string]$msg){ Err $msg; exit 1 }

# ---------- preflight ----------
if (!(Test-Path -LiteralPath $RepoRoot)) { Die "RepoRoot не знайдено: $RepoRoot" }
Push-Location $RepoRoot
try {
  git rev-parse --is-inside-work-tree *>$null; if ($LASTEXITCODE -ne 0) { Die "Не git-репозиторій: $RepoRoot" }

  # Чітко фіксуємо дату в київському поясі (Windows TZ Id: FLE Standard Time)
  $kyivNow = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([datetime]::UtcNow,'FLE Standard Time')
  if (-not $WeekEnd) { $WeekEnd = $kyivNow.Date }
  else { $WeekEnd = $WeekEnd.Date }  # нормалізуємо до .Date

  # Обчислюємо початок блоку за схемою 1–7, 8–14, 15–21, 22–28/29–кінець
  $blockStartDay = [math]::Floor(($WeekEnd.Day - 1) / 7) * 7 + 1
  $WeekStart = Get-Date -Year $WeekEnd.Year -Month $WeekEnd.Month -Day $blockStartDay
  $WeekEnd   = $WeekStart.AddDays(6)
  $endOfMonth = (Get-Date -Year $WeekStart.Year -Month $WeekStart.Month -Day 1).AddMonths(1).AddDays(-1)
  if ($WeekEnd -gt $endOfMonth) { $WeekEnd = $endOfMonth }

  $tagName = 'weekly-{0}_to_{1}' -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')
  $reportRel = "REPORTS/WeeklyChecklist_{0}_to_{1}.md" -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')

  $curBranch = (git rev-parse --abbrev-ref HEAD).Trim()
  if ($Branch -and $curBranch -ne $Branch) { Die "Очікувалась гілка '$Branch', зараз '$curBranch'." }

  # Файл звіту має бути у знімку HEAD
  $headCommit = (git rev-parse HEAD).Trim()
  $hasInCommit = (git ls-tree -r --name-only $headCommit | Select-String -SimpleMatch $reportRel)
  if (-not $hasInCommit) {
    Die "У коміті $headCommit немає $reportRel. Спочатку додай і закоміть файл звіту."
  }

  Info ("Цільовий інтервал: {0} → {1}" -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd'))
  Info "Тег: $tagName"
  Info "Файл звіту: $reportRel"

  # Локальний тег
  $localHas = (git tag -l $tagName) -join ''
  if ([string]::IsNullOrWhiteSpace($localHas)) {
    if ($DryRun) {
      Warn "DRY-RUN: створив би локальний тег $tagName"
    } else {
      git tag -a $tagName -m ("Weekly checklist {0} → {1}" -f $WeekStart.ToString('yyyy-MM-dd'), $WeekEnd.ToString('yyyy-MM-dd')) || Die "Не вдалося створити локальний тег."
      Info "Локальний тег створено."
    }
  } else {
    Info "Локальний тег вже існує."
  }

  # Віддалений тег
  $remoteHas = (git ls-remote --tags $Remote "refs/tags/$tagName") -join ''
  if ([string]::IsNullOrWhiteSpace($remoteHas)) {
    if ($DryRun) {
      Warn "DRY-RUN: запушив би тег $tagName на $Remote"
    } else {
      git push $Remote $tagName || Die "Не вдалося запушити тег на $Remote."
      Info "Тег запушено на $Remote."
    }
  } else {
    Info "Віддалений тег вже існує."
  }

  # Післяумова: у знімку тега є файл звіту
  if (-not $DryRun) {
    $present = (git ls-tree -r --name-only $tagName | Select-String -SimpleMatch $reportRel)
    if (-not $present) { Die "Аномалія: у знімку $tagName немає $reportRel." }
    Info "Перевірка пройдена: $reportRel присутній у $tagName."
  } else {
    Warn "DRY-RUN: валідацію знімка тега пропущено."
  }

  # Лог події
  $logDir = "D:\CHECHA_CORE\C03_LOG\AUDIT"
  $null = New-Item -ItemType Directory -Force -Path $logDir
  $logPath = Join-Path $logDir ("WEEKLY_TAG_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
  $stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  $entry = "{0} | repo={1} | branch={2} | head={3} | tag={4} | report={5} | dryrun={6}" -f $stamp,$RepoRoot,$curBranch,$headCommit,$tagName,$reportRel,$DryRun.IsPresent
  Add-Content -Path $logPath -Value $entry
  Info "Запис у лог: $logPath"
}
finally {
  Pop-Location
}
