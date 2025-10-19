param(
    [string]$CsvPath = "D:\CHECHA_CORE\C07_ANALYTICS\MAT_BALANCE.csv",
    [string]$OutDir = "D:\CHECHA_CORE\C03_LOG",
    [datetime]$AnyDate,                 # Опційно: дата всередині потрібного тижня
    [double]$WarnTechGT = 0.70,
    [double]$WarnStratLT = 0.30
)

$ErrorActionPreference = 'Stop'
function Die($m) { Write-Host "[ERR] $m" -ForegroundColor Red; exit 1 }
function WeekBounds([datetime]$d) {
    # ISO-подібно: тиждень починається в понеділок
    $dow = [int]$d.DayOfWeek            # Mon=1 ... Sun=0
    if ($dow -eq 0) { $dow = 7 }          # Sun -> 7
    $monday = $d.Date.AddDays(1 - $dow)
    $sunday = $monday.AddDays(6)
    [pscustomobject]@{ From = $monday; To = $sunday }
}
function ParseDate($s) {
    if (-not $s) { return $null }
    foreach ($fmt in 'yyyy-MM-dd', 'yyyy/M/d', 'dd.MM.yyyy') { try { return [datetime]::ParseExact($s, $fmt, $null) } catch {} }
    try { return [datetime]$s } catch { return $null }
}

if (!(Test-Path $CsvPath)) { Die "CSV не знайдено: $CsvPath" }
$rows = Import-Csv $CsvPath
if (-not $rows -or $rows.Count -eq 0) { Die "CSV порожній." }

# Обчислюємо межі тижня
if (-not $AnyDate) { $AnyDate = (Get-Date) }
$wb = WeekBounds $AnyDate
$from = $wb.From; $to = $wb.To

# Нормалізація
$norm = foreach ($r in $rows) {
    $d = ParseDate $r.date
    if (-not $d) { continue }
    if ($d.Date -lt $from.Date -or $d.Date -gt $to.Date) { continue }
    $h = 0.0
    if ($null -ne $r.hours -and ("{0}" -f $r.hours).Trim() -ne "") {
        $h = ("{0}" -f $r.hours).Trim().Replace(',', '.')
        try { $h = [double]$h } catch { $h = 0.0 }
    }
    [pscustomobject]@{
        date     = $d.Date
        category = ("{0}" -f $r.category).Trim()
        hours    = $h
    }
}
if (-not $norm) { Die "За тиждень немає рядків ($($from.ToString('yyyy-MM-dd'))..$($to.ToString('yyyy-MM-dd')))" }

# Агрегація
$sumBy = $norm | Group-Object category | ForEach-Object {
    [pscustomobject]@{ Category = $_.Name; Hours = ($_.Group | Measure-Object hours -Sum).Sum }
}
function SumCat($n) { ($sumBy | Where-Object Category -EQ $n | Select-Object -First 1).Hours }

$hS = (SumCat 'Стратегія'); if (-not $hS) { $hS = 0 }
$hT = (SumCat 'Техніка'); if (-not $hT) { $hT = 0 }
$hH = (SumCat 'Гібрид'); if (-not $hH) { $hH = 0 }
$hR = (SumCat 'Відновлення'); if (-not $hR) { $hR = 0 }

$effS = $hS + ($hH * 0.5)
$effT = $hT + ($hH * 0.5)
$den = $effS + $effT
if ($den -le 0) { Die "Немає годин для розрахунку ефективного балансу." }

$pS = [math]::Round($effS / $den, 4)
$pT = [math]::Round($effT / $den, 4)

$warns = @()
if ($pT -gt $WarnTechGT) { $warns += "TechOverweight(>$([int]($WarnTechGT*100))%)" }
if ($pS -lt $WarnStratLT) { $warns += "StrategyLow(<$([int]($WarnStratLT*100))%)" }
$warnText = if ($warns) { $warns -join '; ' } else { 'OK' }

if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$isoWeek = (Get-Culture).Calendar.GetWeekOfYear($from, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
$md = @()
$md += "# Матриця Балансу — Тиждень $isoWeek"
$md += ""
$md += "**Діапазон:** $($from.ToString('yyyy-MM-dd')) … $($to.ToString('yyyy-MM-dd'))  "
$md += "**Стан:** $warnText"
$md += ""
$md += "## Агрегація годин"
$md += "| Категорія | Години |"
$md += "|---|---:|"
$md += ("| Стратегія | {0} |" -f ([math]::Round($hS, 2)))
$md += ("| Техніка | {0} |" -f ([math]::Round($hT, 2)))
$md += ("| Гібрид | {0} |" -f ([math]::Round($hH, 2)))
$md += ("| Відновлення | {0} |" -f ([math]::Round($hR, 2)))
$md += ""
$md += "## Баланс (з урахуванням 50/50 для Гібрид)"
$md += ("- Eff(Стратегія): **{0} h**" -f ([math]::Round($effS, 2)))
$md += ("- Eff(Техніка): **{0} h**" -f ([math]::Round($effT, 2)))
$md += ("- Частка Стратегії: **{0:p1}**" -f $pS)
$md += ("- Частка Техніки: **{0:p1}**" -f $pT)
$md += ""
$md += "> Пороги: Tech>$([int]($WarnTechGT*100))% або Strategy<$([int]($WarnStratLT*100))% → дисбаланс."
$md += ""
$md += "_С.Ч._"

$out = Join-Path $OutDir ("MAT_BALANCE_Weekly_{0}_W{1:00}.md" -f $to.ToString('yyyy'), $isoWeek)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($out, ($md -join [Environment]::NewLine), $Utf8)
Write-Host "[weekly] MD saved: $out" -ForegroundColor Cyan

if ($warnText -ne 'OK') { exit 2 } else { exit 0 }


