<#
Генерує D:\CHECHA_CORE\C06_FOCUS\WEEKLY_INDEX.md
Сканує WEEKLY_CHECKLIST_*.md у FocusDir, зчитує:
- Діапазон дат зі шапки "# Тижневий звіт чек-листів (YYYY-MM-DD → YYYY-MM-DD)"
- Блок "## Підсумки тижня"
- Блок "## 📌 Мікро-KPI" (avg/day, done-share, median, best, worst, streak)
Додає зверху "Дайджест останніх 4 тижнів" із трендами (Avg%, DONE share).
#>

param(
    [string]$FocusDir = "D:\CHECHA_CORE\C06_FOCUS",
    [switch]$WriteRestoreLog = $true,
    [string]$RestoreLogPath = "D:\CHECHA_CORE\C06_FOCUS\FOCUS_RestoreLog.md"
)


# Import Checha utils
$utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
# Import Checha utils
$utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
# Fallback / validation for FocusDir
if (-not $FocusDir -or [string]::IsNullOrWhiteSpace($FocusDir)) {
    $FocusDir = "D:\CHECHA_CORE\C06_FOCUS"
}
if (-not (Test-Path $FocusDir)) {
    throw "FocusDir not found: $FocusDir"
}



# Import Checha utils
$utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
function Parse-DoneSharePct {
    param([string]$s)

    # Import Checha utils
    $utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
    # Import Checha utils
    $utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
    if ([string]::IsNullOrWhiteSpace($s) -or $s -eq "—") { return $null }
    $m = [regex]::Match($s, '^\s*([0-9]+(?:\.[0-9]+)?)%')
    if ($m.Success) { return [double]$m.Groups[1].Value }
    return $null
}

function Format-Trend {
    param(
        [double]$curr,
        $prev  # може бути $null або число
    )

    # Import Checha utils
    $utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
    # Import Checha utils
    $utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
    # якщо попереднього нема або він не число — просто повертаємо поточне значення
    if (-not $PSBoundParameters.ContainsKey('prev') -or $null -eq $prev -or ($prev -isnot [double] -and $prev -isnot [int])) {
        return ("{0}%" -f [math]::Round([double]$curr, 1))
    }

    $p = [double]$prev
    $c = [double]$curr
    $delta = [math]::Round($c - $p, 1)

    if ($delta -gt 0) { return ("{0}% (↑ {1})" -f [math]::Round($c, 1), $delta) }
    elseif ($delta -lt 0) { return ("{0}% (↓ {1})" -f [math]::Round($c, 1), ([math]::Abs($delta))) }
    else { return ("{0}% (→ 0.0)" -f [math]::Round($c, 1)) }
}

function Parse-WeeklyFile {
    param([string]$Path)


    # Import Checha utils
    $utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
    # Import Checha utils
    $utilsPath = Join-Path $PSScriptRoot 'lib\Checha.Utils.psm1'
    if (Test-Path $utilsPath) { Import-Module $utilsPath -Force -DisableNameChecking } else { throw "Utils module not found: $utilsPath" }
    $name = Split-Path $Path -Leaf
    $lines = Get-Content -Path $Path -Encoding UTF8

    # 1) Діапазон дат зі шапки
    $range = "—"
    $hdr = $lines | Select-String -Pattern '^\s*#\s*Тижневий звіт чек-листів\s*\((\d{4}-\d{2}-\d{2})\s*→\s*(\d{4}-\d{2}-\d{2})\)\s*$' | Select-Object -First 1
    if ($hdr) { $range = "{0} → {1}" -f $hdr.Matches[0].Groups[1].Value, $hdr.Matches[0].Groups[2].Value }

    # 2) Підсумки тижня
    $days = 0; $total = 0; $done = 0; $todo = 0; $avgpct = 0.0
    foreach ($l in $lines) {
        if ($l -match '^\s*-\s*Днів у звіті:\s*\*\*(\d+)\*\*') { $days = [int]$Matches[1]; continue }
        elseif ($l -match '^\s*-\s*Сума пунктів:\s*\*\*(\d+)\*\*') { $total = [int]$Matches[1]; continue }
        elseif ($l -match '^\s*-\s*Виконано всього:\s*\*\*(\d+)\*\*') { $done = [int]$Matches[1]; continue }
        elseif ($l -match '^\s*-\s*Залишилось всього:\s*\*\*(\d+)\*\*') { $todo = [int]$Matches[1]; continue }
        elseif ($l -match '^\s*-\s*Середній прогрес за день:\s*\*\*(\d+(\.\d+)?)%?\*\*') { $avgpct = [double]$Matches[1]; continue }
    }

    # 3) KPI-блок
    $avgItems = ""; $doneShare = ""; $median = ""; $best = ""; $worst = ""; $streak = ""
    $kpiStart = ($lines | Select-String -Pattern '^\s*##\s*📌\s*Мікро-KPI\s*$' -SimpleMatch | Select-Object -First 1)
    if ($kpiStart) {
        for ($i = $kpiStart.LineNumber; $i -le [math]::Min($kpiStart.LineNumber + 20, $lines.Count); $i++) {
            $row = $lines[$i - 1]
            if ($row -match '^\|\s*Середня кількість пунктів/день\s*\|\s*([0-9]+(\.[0-9]+)?)\s*\|\s*$') { $avgItems = $Matches[1] }
            elseif ($row -match '^\|\s*Частка днів зі статусом DONE\s*\|\s*([0-9]+(\.[0-9]+)?)%\s*\((\d+)\/(\d+)\)\s*\|\s*$') { $doneShare = "{0}% ({1}/{2})" -f $Matches[1], $Matches[3], $Matches[4] }
            elseif ($row -match '^\|\s*Медіана прогресу\s*\|\s*([0-9]+(\.[0-9]+)?)%\s*\|\s*$') { $median = "{0}%" -f $Matches[1] }
            elseif ($row -match '^\|\s*Найкращий день\s*\|\s*(\d{4}-\d{2}-\d{2})\s*—\s*([0-9]+(\.[0-9]+)?)%\s*\|\s*$') { $best = "{0} — {1}%" -f $Matches[1], $Matches[2] }
            elseif ($row -match '^\|\s*Найгірший день\s*\|\s*(\d{4}-\d{2}-\d{2})\s*—\s*([0-9]+(\.[0-9]+)?)%\s*\|\s*$') { $worst = "{0} — {1}%" -f $Matches[1], $Matches[2] }
            elseif ($row -match '^\|\s*Поточний DONE-стрік.*\|\s*(\d+)\s*\|\s*$') { $streak = $Matches[1] }
        }
    }

    # 4) ISO з назви
    $iso = "—"
    if ($name -match 'WEEKLY_CHECKLIST_(\d{4})-W(\d{2})\.md') { $iso = "{0}-W{1}" -f $Matches[1], $Matches[2] }

    [pscustomobject]@{
        File      = $name
        ISO       = $iso
        Range     = $range
        Days      = $days
        Total     = $total
        Done      = $done
        Todo      = $todo
        AvgPct    = $avgpct
        AvgItems  = $avgItems
        DoneShare = $doneShare
        Median    = $median
        Best      = $best
        Worst     = $worst
        Streak    = $streak
    }
}

# Збір файлів і парсинг
$files = Get-ChildItem $FocusDir -Filter 'WEEKLY_CHECKLIST_*.md' -File | Sort-Object Name -Descending
$rows = @()
foreach ($f in $files) { $rows += Parse-WeeklyFile -Path $f.FullName }

# Побудова індексу


# Lock на індекс під час побудови
$lock = Join-Path $FocusDir '.index.lock'
Acquire-ChechaLock -Path $lock -TimeoutMinutes 10
try {
    $nowStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $indexPath = Join-Path $FocusDir 'WEEKLY_INDEX.md'
    $bakRoot = Join-Path $FocusDir '.bak'

    $md = @()
    $md += "# WEEKLY INDEX"
    $md += ""
    $md += "> Оновлено: $nowStamp"
    $md += ""

    # === ДАЙДЖЕСТ ОСТАННІХ 4 ТИЖНІВ з трендом ===
    $last4 = $rows | Select-Object -First 4
    if ($last4.Count -gt 0) {
        # розрахунок трендів: порівнюємо з попереднім тижнем у списку
        $digest = @()
        for ($i = 0; $i -lt $last4.Count; $i++) {
            $curr = $last4[$i]
            $prev = if ($i -lt $last4.Count - 1) { $last4[$i + 1] } else { $null }

            $avgCurr = [double]$curr.AvgPct
            $avgPrev = if ($prev) { [double]$prev.AvgPct } else { $null }
            $dsCurrPct = Parse-DoneSharePct $curr.DoneShare
            $dsPrevPct = if ($prev) { Parse-DoneSharePct $prev.DoneShare } else { $null }

            $digest += [pscustomobject]@{
                ISO      = $curr.ISO
                Range    = $curr.Range
                AvgTrend = Format-Trend $avgCurr $avgPrev
                DsTrend  = if ($dsCurrPct -ne $null) { Format-Trend $dsCurrPct $dsPrevPct } else { "—" }
                Median   = if ($curr.Median -and $curr.Median -ne "") { $curr.Median } else { "—" }
                Best     = if ($curr.Best -and $curr.Best -ne "") { $curr.Best } else { "—" }
                Worst    = if ($curr.Worst -and $curr.Worst -ne "") { $curr.Worst } else { "—" }
                Streak   = if ($curr.Streak -and $curr.Streak -ne "") { $curr.Streak } else { "—" }
            }
        }

        $md += "## Останні 4 тижні — дайджест"
        $md += "| ISO-тиждень | Діапазон | Avg% (тренд) | DONE share (тренд) | Median | Best | Worst | Streak |"
        $md += "|---|---|---|---|---:|---|---|---:|"
        foreach ($r in $digest) {
            $md += "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f `
                $r.ISO, $r.Range, $r.AvgTrend, $r.DsTrend, $r.Median, $r.Best, $r.Worst, $r.Streak
        }
        $md += ""
    }

    # === Повна таблиця всіх тижнів ===
    $md += "## Всі тижні"
    $md += "| ISO-тиждень | Діапазон | Файл | Днів | Всього | Виконано | Залишилось | Avg% | Avg items/day | DONE days share | Median | Best | Worst | Streak |"
    $md += "|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|---|---|---:|"

    foreach ($r in $rows) {
        $md += "| {0} | {1} | [`{2}`]({2}) | {3} | {4} | {5} | {6} | {7}% | {8} | {9} | {10} | {11} | {12} | {13} |" -f `
            $r.ISO, $r.Range, $r.File, $r.Days, $r.Total, $r.Done, $r.Todo,
        $r.AvgPct, ($(if ($r.AvgItems -ne '' ) { $r.AvgItems }else { '—' })),
        ($(if ($r.DoneShare -ne '') { $r.DoneShare }else { '—' })),
        ($(if ($r.Median -ne '' ) { $r.Median }else { '—' })),
        ($(if ($r.Best -ne '' ) { $r.Best }else { '—' })),
        ($(if ($r.Worst -ne '' ) { $r.Worst }else { '—' })),
        ($(if ($r.Streak -ne '' ) { $r.Streak }else { '—' }))
    }

    $md += ""
    $md += "---"
    $md += "С.Ч."
    if (-not [string]::IsNullOrWhiteSpace($indexPath)) {
        Backup-TextFile -Path $indexPath -Root (Join-Path $FocusDir '.bak')
    }
    else {
        throw 'indexPath is empty (nothing to back up)'
    }
    Write-Host "✅ WEEKLY INDEX: $indexPath"

    # Лог у RestoreLog
    if ($WriteRestoreLog) {
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if (-not (Test-Path $RestoreLogPath)) {
            "# Restore Log ($((Get-Date).ToString('yyyy-MM-dd')))`n" | Set-Content -Path $RestoreLogPath -Encoding utf8BOM
        }
        Add-Content -Path $RestoreLogPath -Value ("- [$stamp] Weekly index rebuilt with KPI + 4-week digest: {0}" -f (Split-Path $indexPath -Leaf)) -Encoding utf8BOM
        Write-Host "🧭 RestoreLog оновлено"
    }

}
finally {
    Release-ChechaLock -Path $lock
}








