#requires -Version 5.1
<#
Export-DevOpsMetrics.ps1
Збирає добові метрики GitHub Actions у CSV для дашбордів.

Параметри за замовчуванням підігнані під CHECHA_CORE.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot   = "D:\CHECHA_CORE",
  [string]$Repo       = "Checha-hub-DAO/dao-gogs-docs",
  [string]$OutDir     = "D:\CHECHA_CORE\C07_ANALYTICS\devops",
  [int]$Days          = 14,
  [string[]]$Workflows = @(
    "release-verify.yml",
    "release-status-to-docs.yml",
    "daily-devops-report.yml"
  ),
  [switch]$NoGitCommitPush   # якщо вказати — не робити commit/push
)

$ErrorActionPreference = "Stop"
function Fail([string]$m){ throw $m }
function Log([string]$m){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host ("[{0}] {1}" -f $ts, $m)
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail "gh не знайдено. Встанови/авторизуй: gh auth login" }
try { gh auth status *> $null } catch { Fail "gh не авторизовано. Виконай: gh auth login" }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) { Fail "Не знайдено .git у RepoRoot: $RepoRoot" }

# Підготовка
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$today = Get-Date -Format 'yyyy-MM-dd'
$csvDaily  = Join-Path $OutDir ("devops_metrics_{0}.csv" -f $today)
$csvLatest = Join-Path $OutDir "devops_metrics_latest.csv"

# Збір усіх ран-ів за останні N днів для кожного workflow
$sinceIso = (Get-Date).AddDays(-$Days).ToString("s") + "Z"
$all = @()

foreach ($wf in $Workflows) {
  Log ("Збір ран-ів для {0} (since {1})" -f $wf, $sinceIso)
  # пагінація: витягнемо до ~1000 записів (10 сторінок по 100)
  $page = 1
  while ($true) {
    $endpoint = "repos/{0}/actions/workflows/{1}/runs?per_page=100&page={2}&created={3}.." -f $Repo, $wf, $page, $sinceIso
    $json = ""
    try { $json = gh api $endpoint 2>$null } catch { $json = "" }
    if ([string]::IsNullOrWhiteSpace($json)) { break }

    $obj = $json | ConvertFrom-Json
    if (-not $obj.workflow_runs -or $obj.workflow_runs.Count -eq 0) { break }

    foreach ($run in $obj.workflow_runs) {
      $dStart = Get-Date $run.created_at
      $dEnd   = if ($run.updated_at) { Get-Date $run.updated_at } else { $dStart }
      $durMin = [math]::Round((New-TimeSpan -Start $dStart -End $dEnd).TotalMinutes, 2)
      $status = if ($run.conclusion) { $run.conclusion } else { $run.status }
      $all += [pscustomobject]@{
        workflow   = $wf
        day        = (Get-Date $run.created_at -Format 'yyyy-MM-dd')
        status     = $status
        duration_m = $durMin
        id         = $run.id
      }
    }

    if ($obj.workflow_runs.Count -lt 100) { break }
    $page++
    if ($page -gt 10) { break } # захист від нескінченної пагінації
  }
}

# Агрегація по дню і воркфлоу
$groups = $all | Group-Object -Property workflow, day
$rows = foreach ($g in $groups) {
  $wf = $g.Group[0].workflow
  $dy = $g.Group[0].day
  $runs = $g.Count
  $succ = ($g.Group | Where-Object { $_.status -match '^success$' }).Count
  $fail = ($g.Group | Where-Object { $_.status -match '^failure$' }).Count
  $canc = ($g.Group | Where-Object { $_.status -match '^cancelled$' }).Count
  $durs = $g.Group | Select-Object -ExpandProperty duration_m
  $avg  = if ($durs.Count -gt 0) { [math]::Round(($durs | Measure-Object -Average).Average, 2) } else { 0 }
  $p95  = 0
  if ($durs.Count -gt 0) {
    $sorted = $durs | Sort-Object
    $idx = [int][math]::Ceiling(0.95 * $sorted.Count) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
    $p95 = [math]::Round($sorted[$idx], 2)
  }
  [pscustomobject]@{
    date            = $dy
    workflow        = $wf
    runs            = $runs
    success         = $succ
    failure         = $fail
    cancelled       = $canc
    avg_minutes     = $avg
    p95_minutes     = $p95
  }
}

# Додамо порожні дні (0-рядки) для повноти (опційно)
# (залишаю вимкненим для компактності; легко включити за потреби)

# Запис CSV
$rows | Sort-Object date, workflow | Export-Csv -LiteralPath $csvDaily -NoTypeInformation -Encoding UTF8
Copy-Item -LiteralPath $csvDaily -Destination $csvLatest -Force

Write-Host ("[OK] CSV метрики збережені: {0}; {1}" -f $csvDaily, $csvLatest) -ForegroundColor Green

# Commit & push (опційно)
if (-not $NoGitCommitPush) {
  git -C $RepoRoot add -- (Resolve-Path $csvDaily), (Resolve-Path $csvLatest) 2>$null
  git -C $RepoRoot commit -m ("analytics: devops metrics CSV ({0}d window)" -f $Days) 2>$null
  git -C $RepoRoot push origin main | Out-Null
  Write-Host "[OK] CSV закомічено та запушено." -ForegroundColor Green
} else {
  Write-Host "[SKIP] Commit/push вимкнено ключем -NoGitCommitPush." -ForegroundColor Yellow
}
