param(
  [string]$CsvPath = "D:\CHECHA_CORE\C07_ANALYTICS\MAT_BALANCE.csv",
  [string]$OutDir  = "D:\CHECHA_CORE\C03_LOG",
  [datetime]$Date,
  [datetime]$From,
  [datetime]$To,
  [double]$WarnTechGT = 0.70,   # попередження, якщо Tech > 70%
  [double]$WarnStratLT = 0.30,  # попередження, якщо Strategy < 30%
  [switch]$OutMd,               # згенерувати Markdown-звіт
  [switch]$SummaryOnly,         # показати тільки SUMMARY
  [switch]$Quiet                # мінімальний консольний вивід
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Die($msg){ Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }
function NowStamp(){ (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }

# 0) Перевіримо CSV
if (!(Test-Path -LiteralPath $CsvPath)) { Die "CSV не знайдено: $CsvPath" }

# 1) Зчитаємо CSV (UTF-8/BOM дружньо)
try {
  $rows = Import-Csv -LiteralPath $CsvPath
}
catch {
  Die "Помилка читання CSV: $($_.Exception.Message)"
}

if (-not $rows -or $rows.Count -eq 0) { Die "CSV порожній." }

# 2) Нормалізація і фільтрація за датою
function Parse-Date($s){
  if (-not $s) { return $null }
  foreach ($fmt in @('yyyy-MM-dd','yyyy/M/d','dd.MM.yyyy')){
    try { return [datetime]::ParseExact($s, $fmt, $null) } catch {}
  }
  # fall back
  try { return [datetime]$s } catch { return $null }
}

$rows2 = foreach($r in $rows){
  $d = Parse-Date $r.date
  $cat = ("{0}" -f $r.category).Trim()
  $h = 0.0
  if ($null -ne $r.hours -and ("{0}" -f $r.hours).Trim() -ne ""){
    # У разі використання коми як десяткового розділювача — замінимо на крапку
    $h = ("{0}" -f $r.hours).Trim().Replace(',','.')
    try { $h = [double]$h } catch { $h = 0.0 }
  }
  [pscustomobject]@{
    date          = $d
    category      = $cat
    hours         = $h
    indicator     = $r.indicator
    balance_score = $r.balance_score
  }
}

# Застосуємо фільтри дати
if ($PSBoundParameters.ContainsKey('Date') -and $null -ne $Date){
  $rows2 = $rows2 | Where-Object { $_.date -and $_.date.Date -eq $Date.Date }
}
elseif ($PSBoundParameters.ContainsKey('From') -or $PSBoundParameters.ContainsKey('To')){
  if ($PSBoundParameters.ContainsKey('From') -and $PSBoundParameters.ContainsKey('To')){
    $rows2 = $rows2 | Where-Object { $_.date -and $_.date -ge $From.Date -and $_.date -le $To.Date }
  } elseif ($PSBoundParameters.ContainsKey('From')){
    $rows2 = $rows2 | Where-Object { $_.date -and $_.date -ge $From.Date }
  } elseif ($PSBoundParameters.ContainsKey('To')){
    $rows2 = $rows2 | Where-Object { $_.date -and $_.date -le $To.Date }
  }
}

if (-not $rows2 -or $rows2.Count -eq 0){ Die "Після фільтрації немає рядків (перевір дати/CSV)." }

# 3) Агрегація годин
$sumBy = $rows2 | Group-Object category | ForEach-Object {
  [pscustomobject]@{
    Category = $_.Name
    Hours    = ($_.Group | Measure-Object hours -Sum).Sum
  }
}

function SumCat($name){
  ($sumBy | Where-Object { $_.Category -eq $name } | Select-Object -First 1).Hours
}

$hStrat   = (SumCat 'Стратегія');   if (-not $hStrat) { $hStrat = 0.0 }
$hTech    = (SumCat 'Техніка');     if (-not $hTech) { $hTech = 0.0 }
$hHybrid  = (SumCat 'Гібрид');      if (-not $hHybrid) { $hHybrid = 0.0 }
$hRestore = (SumCat 'Відновлення'); if (-not $hRestore) { $hRestore = 0.0 }

# 4) Ефективні години для балансу (ділимо Гібрид 50/50)
$effStrat = $hStrat + ($hHybrid * 0.5)
$effTech  = $hTech  + ($hHybrid * 0.5)
$den = $effStrat + $effTech
if ($den -le 0){ Die "Немає годин у категоріях Стратегія/Техніка/Гібрид для розрахунку балансу." }

$pStrat = [math]::Round(($effStrat / $den), 4)
$pTech  = [math]::Round(($effTech  / $den), 4)

# 5) Попередження про дисбаланс
$warns = @()
if ($pTech -gt $WarnTechGT)   { $warns += "TechOverweight(>$([int]($WarnTechGT*100))%)" }
if ($pStrat -lt $WarnStratLT) { $warns += "StrategyLow(<$([int]($WarnStratLT*100))%)" }
$warnText = if ($warns.Count -gt 0) { $warns -join '; ' } else { 'OK' }

# 6) Дата-діапазон для звіту
$minDate = ($rows2 | Where-Object { $_.date } | Measure-Object -Property date -Minimum).Minimum
$maxDate = ($rows2 | Where-Object { $_.date } | Measure-Object -Property date -Maximum).Maximum
$rangeText = if ($minDate -and $maxDate -and $minDate.Date -eq $maxDate.Date) { $minDate.ToString('yyyy-MM-dd') } else { "$($minDate.ToString('yyyy-MM-dd')) to $($maxDate.ToString('yyyy-MM-dd'))" }

# 7) Об'єкт результату (fixed Timestamp)
$result = [pscustomobject]@{
  DateRange        = $rangeText
  Hours_Strategy   = [math]::Round($hStrat,2)
  Hours_Tech       = [math]::Round($hTech,2)
  Hours_Hybrid     = [math]::Round($hHybrid,2)
  Hours_Restore    = [math]::Round($hRestore,2)
  Eff_Strategy     = [math]::Round($effStrat,2)
  Eff_Tech         = [math]::Round($effTech,2)
  Pct_Strategy     = "{0:p1}" -f $pStrat
  Pct_Tech         = "{0:p1}" -f $pTech
  Warning          = $warnText
  Timestamp        = $(NowStamp)
}

if (-not $Quiet){
  if (-not $SummaryOnly){
    $result | Format-List | Out-String | Write-Host
  }
  Write-Host ("SUMMARY: range={0} S={1}h T={2}h H={3}h R={4}h | EffS={5}h EffT={6}h | S={7} T={8} | {9}" -f `
    $result.DateRange, $result.Hours_Strategy, $result.Hours_Tech, $result.Hours_Hybrid, $result.Hours_Restore, `
    $result.Eff_Strategy, $result.Eff_Tech, $result.Pct_Strategy, $result.Pct_Tech, $result.Warning)
}

# 8) Markdown-звіт (опційно)
if ($OutMd){
  if (!(Test-Path -LiteralPath $OutDir)){ New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $mdPath = Join-Path $OutDir ("MAT_BALANCE_Report_{0}.md" -f $stamp)

  $md = @()
  $md += "# Матриця Балансу — звіт"
  $md += ""
  $md += "**Діапазон дат:** $($result.DateRange)  "
  $md += "**Час формування:** $($result.Timestamp)"
  $md += ""
  $md += "## Агрегація годин"
  $md += ""
  $md += "| Категорія | Години |"
  $md += "|---|---:|"
  $md += ("| Стратегія | {0} |" -f $result.Hours_Strategy)
  $md += ("| Техніка | {0} |" -f $result.Hours_Tech)
  $md += ("| Гібрид | {0} |" -f $result.Hours_Hybrid)
  $md += ("| Відновлення | {0} |" -f $result.Hours_Restore)
  $md += ""
  $md += "## Баланс (ефективні години з урахуванням 50/50 для Гібрид)"
  $md += ""
  $md += ("- Eff(Стратегія): **{0} h**" -f $result.Eff_Strategy)
  $md += ("- Eff(Техніка): **{0} h**" -f $result.Eff_Tech)
  $md += ("- Частка Стратегії: **{0}**" -f $result.Pct_Strategy)
  $md += ("- Частка Техніки: **{0}**" -f $result.Pct_Tech)
  $md += ""
  $md += "## Стан"
  $md += ""
  $md += ("- Попередження: **{0}**" -f $result.Warning)
  $md += ""
  $md += "> Пороги: Tech>{0}% або Strategy<{1}% → дисбаланс." -f ([int]($WarnTechGT*100)), ([int]($WarnStratLT*100))
  $md += ""
  $md += "_С.Ч._"

  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($mdPath, ($md -join [Environment]::NewLine), $Utf8NoBom)

  if (-not $Quiet){ Write-Host "[report] MD saved: $mdPath" -ForegroundColor Cyan }
}

# 9) Завершення з не-нульовим кодом якщо дисбаланс
if ($warnText -ne 'OK'){ exit 2 } else { exit 0 }
