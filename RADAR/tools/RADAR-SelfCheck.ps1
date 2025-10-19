<#
  RADAR-SelfCheck.ps1
  Перевіряє готовність RADAR-середовища до запуску пайплайну.

  Перевіряє:
    - Наявність тек: RADAR\INBOX, \ARTIFACTS, \INDEX, \HISTORY, \REPORTS, \tools
    - Права запису до REPORTS та C03_LOG
    - Індекс artifacts.csv: існує/читається/має ключові колонки
    - Парсинг timestamp, частку порожніх title/summary/tags
    - Дублікатні sha256/id, відсутні sha256
    - Наявність/типові значення RadarScore (мін/макс/NaN)
    - Рекомендації з виправлення
  Виходи:
    0 = OK, 1 = WARN (можна запускати, але є зауваження), 2 = ERR (критичні помилки)
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = "D:\CHECHA_CORE",
    [string]$CsvPath
)

# ---------- Helpers ----------
function Write-Log {
    param([string]$m, [string]$lvl = "INFO")
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$lvl] $ts $m"
}
function Ensure-Dir([string]$p) { if (!(Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function TryNum([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s2 = $s -replace ',', '.'
    $n = 0.0
    if ([double]::TryParse($s2, [ref]$n)) { return $n } else { return $null }
}
# -----------------------------

$exit = 0
$warns = @()
$errs = @()

try {
    # 0) Структура
    $radarRoot = Join-Path $RepoRoot 'RADAR'
    $paths = @{
        INBOX = Join-Path $radarRoot 'INBOX'
        ART   = Join-Path $radarRoot 'ARTIFACTS'
        INDEX = Join-Path $radarRoot 'INDEX'
        HIST  = Join-Path $radarRoot 'HISTORY'
        REPTS = Join-Path $radarRoot 'REPORTS'
        TOOLS = Join-Path $radarRoot 'tools'
        LOGS  = Join-Path $RepoRoot  'C03_LOG'
    }

    foreach ($k in $paths.Keys) {
        if (!(Test-Path -LiteralPath $paths[$k])) {
            $warns += "Відсутня тека $k → створено: $($paths[$k])"
            Ensure-Dir $paths[$k]
        }
    }

    # 1) Права запису
    $testFile = Join-Path $paths.REPTS ".__write_test.txt"
    try { "ok" | Out-File -FilePath $testFile -Encoding utf8; Remove-Item $testFile -Force }
    catch { $errs += "Немає права запису в REPORTS: $($paths.REPTS)" }

    $testFile2 = Join-Path $paths.LOGS ".__write_test.txt"
    try { "ok" | Out-File -FilePath $testFile2 -Encoding utf8; Remove-Item $testFile2 -Force }
    catch { $errs += "Немає права запису в C03_LOG: $($paths.LOGS)" }

    # 2) CSV
    if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $paths.INDEX 'artifacts.csv' }
    if (!(Test-Path -LiteralPath $CsvPath)) { $errs += "Не знайдено індекс артефактів: $CsvPath" }
    else {
        try {
            $rows = Import-Csv -LiteralPath $CsvPath
            if (-not $rows -or $rows.Count -eq 0) { $errs += "CSV порожній: $CsvPath" }
            else {
                $header = $rows[0].PSObject.Properties.Name
                $need = @('id', 'timestamp', 'source', 'lang', 'title', 'summary', 'tags', 'sha256')
                $miss = $need | Where-Object { $header -notcontains $_ }
                if ($miss.Count -gt 0) { $errs += "Відсутні ключові колонки: $($miss -join ', ')" }

                # 3) Парсинг дат/оцінка порожніх полів
                $total = $rows.Count
                $badTs = 0; $emptyTitle = 0; $emptySha = 0; $emptyTags = 0; $NaNScore = 0
                $dupeId = 0; $dupeSha = 0

                $idSet = New-Object 'System.Collections.Generic.HashSet[string]'
                $shaSet = New-Object 'System.Collections.Generic.HashSet[string]'

                $minScore = [double]::PositiveInfinity
                $maxScore = [double]::NegativeInfinity

                foreach ($r in $rows) {
                    # timestamp
                    $ts = $null; [datetime]::TryParse($r.timestamp, [ref]$ts) | Out-Null
                    if ($null -eq $ts) { $badTs++ }

                    # порожні
                    if ([string]::IsNullOrWhiteSpace($r.title)) { $emptyTitle++ }
                    if ([string]::IsNullOrWhiteSpace($r.sha256)) { $emptySha++ }
                    if ([string]::IsNullOrWhiteSpace($r.tags)) { $emptyTags++ }

                    # RadarScore
                    $sc = TryNum $r.RadarScore
                    if ($sc -eq $null) { $NaNScore++ }
                    else {
                        if ($sc -lt $minScore) { $minScore = $sc }
                        if ($sc -gt $maxScore) { $maxScore = $sc }
                    }

                    # duplicates
                    if ($r.id) {
                        if (-not $idSet.Add([string]$r.id)) { $dupeId++ }
                    }
                    if ($r.sha256) {
                        if (-not $shaSet.Add([string]$r.sha256)) { $dupeSha++ }
                    }
                }

                # 4) Порогові попередження
                if ($badTs -gt 0) { $warns += "Непридатних timestamp: $badTs / $total" }
                if ($emptyTitle -gt 0) { $warns += "Порожніх title: $emptyTitle / $total" }
                if ($emptyTags -gt 0) { $warns += "Порожніх tags: $emptyTags / $total (негативно впливає на тренди)" }
                if ($emptySha -gt 0) { $errs += "Порожніх sha256: $emptySha / $total (критично для дедуплікації)" }
                if ($NaNScore -gt 0) { $warns += "Відсутній/некоректний RadarScore: $NaNScore / $total (запусти Radar-ScoreRecalc.ps1)" }
                if ($dupeId -gt 0) { $warns += "Дублікатів id: $dupeId" }
                if ($dupeSha -gt 0) { $warns += "Дублікатів sha256: $dupeSha (перевір дедуп/ingest)" }

                if ($minScore -eq [double]::PositiveInfinity) { $minScore = 0 }
                if ($maxScore -eq [double]::NegativeInfinity) { $maxScore = 0 }

                Write-Log ("Статистика RadarScore: min={0}, max={1}" -f $minScore, $maxScore)

                # 5) Перехресні залежності (скрипти)
                $req = @(
                    Join-Path $paths.TOOLS 'Radar-ScoreRecalc.ps1'),
                (Join-Path $paths.TOOLS 'Build-RadarDigest.ps1'),
                (Join-Path $paths.TOOLS 'Radar-Trends.ps1'),
                (Join-Path $paths.TOOLS 'RADAR-Pipeline_Run.ps1')
            )
            foreach ($p in $req) {
                if (!(Test-Path -LiteralPath $p)) { $warns += "Відсутній скрипт: $p" }
            }
        }
    }
    catch {
        $errs += "Помилка читання CSV: $($_.Exception.Message)"
    }
}

# 6) Візуальні шрифти (для кирилиці в HTML)
# Не критично, але підказка якщо бачиш 'кракозябри'
$fontHint = "DejaVu Sans, Arial Unicode MS"
$warns += "Для HTML-дайджестів використовуй шрифт з кирилицею: $fontHint (якщо бачиш некоректні символи)."

# 7) Підсумок
if ($errs.Count -gt 0) { $exit = 2 }
elseif ($warns.Count -gt 0) { $exit = 1 }
else { $exit = 0 }

# Лог-файл
$logFile = Join-Path $paths.LOGS 'RADAR_SELFCHECK_LOG.md'
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$status = @('OK', 'WARN', 'ERR')[$exit]
Add-Content -Path $logFile -Encoding UTF8 ("## [{0}] SelfCheck: {1}" -f $ts, $status)
if ($errs.Count -gt 0) { Add-Content -Path $logFile -Encoding UTF8 ("- ERR: " + ($errs -join "`n- ERR: ")) }
if ($warns.Count -gt 0) { Add-Content -Path $logFile -Encoding UTF8 ("- WARN: " + ($warns -join "`n- WARN: ")) }
Add-Content -Path $logFile -Encoding UTF8 ""

# Вивід у консоль
if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Log $_ "ERR" } }
if ($warns.Count -gt 0) { $warns | ForEach-Object { Write-Log $_ "WARN" } }

if ($exit -eq 0) { Write-Log "SelfCheck: OK — можна запускати пайплайн." }
elseif ($exit -eq 1) { Write-Log "SelfCheck: WARN — запуск дозволено, але рекомендовано виправити попередження." "WARN" }
else { Write-Log "SelfCheck: ERR — виправ помилки перед запуском." "ERR" }

exit $exit
}
catch {
    Write-Log $_.Exception.Message "ERR"
    exit 2
}


