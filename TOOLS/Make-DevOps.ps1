#requires -Version 5.1
<#
Make-DevOps.ps1
Єдиний пусковий скрипт DevOps-циклу:
  1) Генерує Daily Report через Build-DevOpsDailyReport.API.ps1
  2) Гарантує наявність лінків у docs/SUMMARY.md (Ensure-SummaryDevOpsLinks.ps1)
  3) Комітить/пушить залишкові зміни (якщо є)
  4) (опційно) Тригерить GitHub Actions: daily-devops-report.yml та release-status-to-docs.yml

Параметри за замовчуванням виставлені під CHECHA_CORE.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$Repo     = "Checha-hub-DAO/dao-gogs-docs",
  [string]$OutDir   = "D:\CHECHA_CORE\C03_LOG\reports\devops",
  [string]$Template = "D:\CHECHA_CORE\TOOLS\DevOps_Daily_Report_TEMPLATE.md",
  [string]$DailyScript = "D:\CHECHA_CORE\TOOLS\Build-DevOpsDailyReport.API.ps1",
  [string]$EnsureSummaryScript = "D:\CHECHA_CORE\TOOLS\Ensure-SummaryDevOpsLinks.ps1",
  [switch]$RunWorkflows,     # якщо вказати — запустить GA воркфлоуи наприкінці
  [switch]$SkipPush          # якщо вказати — НЕ робитиме фінальний commit/push
)

$ErrorActionPreference = "Stop"

function Fail([string]$m){ throw $m }
function Log([string]$m){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[{0}] {1}" -f $ts, $m
  Write-Host $line
  try { Add-Content -LiteralPath $script:LogPath -Value $line } catch {}
}

# --- Підготовка логу ---
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$script:LogPath = Join-Path $OutDir "_make.log"
Log "=== Make-DevOps start ==="

# --- Префлайт ---
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) { Fail "Не знайдено .git у RepoRoot: $RepoRoot" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "Git не знайдено у PATH." }
if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { Log "Попередження: GitHub CLI (gh) не знайдено — пропущу RunWorkflows."; $RunWorkflows = $false }
else {
  try { gh auth status *> $null } catch { Log "Попередження: gh не авторизовано — пропущу RunWorkflows."; $RunWorkflows = $false }
}
if (-not (Test-Path -LiteralPath $DailyScript)) { Fail "Не знайдено $DailyScript" }
if (-not (Test-Path -LiteralPath $Template)) { Log "Шаблон $Template не знайдено — буде використано вбудований у скрипті щоденного звіту." }

# --- 1) Щоденний звіт ---
Log "Запуск Daily Report через $DailyScript"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $DailyScript `
  -Repo $Repo `
  -RepoRoot $RepoRoot `
  -OutDir $OutDir `
  -Template $Template
Log "Daily Report завершено."

# --- 2) Навігація SUMMARY ---
if (Test-Path -LiteralPath $EnsureSummaryScript) {
  Log "Запуск Ensure-SummaryDevOpsLinks: $EnsureSummaryScript"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $EnsureSummaryScript
  Log "Ensure-SummaryDevOpsLinks завершено."
} else {
  Log "Пропущено Ensure-Summary — файл відсутній: $EnsureSummaryScript"
}

# --- 3) Фінальний commit/push (якщо є зміни) ---
try {
  Log "Стаджу зміни…"
  & git -C $RepoRoot add -A | Out-Null

  & git -C $RepoRoot diff --cached --quiet
  $hasStaged = -not ($LASTEXITCODE -eq 0)

  if ($hasStaged) {
    $msg = "devops: Make-DevOps sync {0}" -f (Get-Date -Format 'yyyy-MM-dd')
    & git -C $RepoRoot commit -m $msg | Out-Null
    if (-not $SkipPush) {
      Log "Пуш у origin main…"
      & git -C $RepoRoot push origin main | Out-Null
      Log "Пуш виконано."
    } else {
      Log "SkipPush=true — пуш пропущено."
    }
  } else {
    Log "Немає staged-змін — коміт/пуш не потрібні."
  }
} catch {
  Log ("Git-коміт/пуш: {0}" -f $_.Exception.Message)
  if (-not $SkipPush) { throw }
}

# --- 4) (опційно) Запустити повʼязані GitHub Actions ---
if ($RunWorkflows) {
  Log "Запуск GitHub Actions воркфлоуів…"
  try {
    gh workflow run "daily-devops-report.yml"     -R $Repo | Out-Null
    gh workflow run "release-status-to-docs.yml"  -R $Repo | Out-Null
    Log "GA воркфлоуи запущено: daily-devops-report.yml, release-status-to-docs.yml"
  } catch {
    Log ("Помилка запуску GA: {0}" -f $_.Exception.Message)
  }
} else {
  Log "RunWorkflows=false — GA воркфлоуи не запускалися."
}

# --- 5) Вивести шлях до останнього звіту ---
try {
  $latest = Get-ChildItem -LiteralPath $OutDir -Filter "DevOps_Daily_Report_*.md" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) { Log ("Останній звіт: {0}" -f $latest.FullName) }
} catch {}

Log "=== Make-DevOps done ==="
