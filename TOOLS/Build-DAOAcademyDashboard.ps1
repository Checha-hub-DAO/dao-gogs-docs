<# 
.SYNOPSIS
  Генерує PNG-дашборд і агреговані CSV з освітніх метрик DAO-Академії (G29).

.DESCRIPTION
  Зчитує дані з:
    - C07_ANALYTICS\Education_Metrics.csv   (або DAO_Education_Metrics.csv)
    - C07_ANALYTICS\Cert_Registry.csv
    - C07_ANALYTICS\Mentorship_Metrics.csv (за наявності) або DAO_Mentorship_Registry.csv (фолбек)
  Агрегує по місяцях і формує:
    - PNG: EducationIndex, Certificates, Mentorship (окремі) + комбінований дашборд
    - CSV: зведені monthly-агрегації

.PARAMETER Root
  Корінь CHECHA_CORE. За замовч.: D:\CHECHA_CORE

.PARAMETER From
  Початок періоду YYYY-MM (включно). За замовч.: 6 місяців до поточної дати.

.PARAMETER To
  Кінець періоду YYYY-MM (включно). За замовч.: поточний місяць.

.NOTES
  Потребує Windows з .NET Charting:
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization
  Перевірено на PowerShell 7+ (Windows). На Core Linux/Mac — не підтримується Charting.
  Автор: С.Ч. / DAO-GOGS | Версія: 1.0 | Дата: 2025-11-06
#>

[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string]$From,
  [string]$To
)

# --- Підготовка середовища та шляхів
$AN = Join-Path $Root "C07_ANALYTICS"
$OUT = Join-Path $AN "Dashboard_Exports"
if (!(Test-Path $OUT)) { New-Item -ItemType Directory -Path $OUT -Force | Out-Null }

# Завантаження .NET Charting
try {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  Add-Type -AssemblyName System.Windows.Forms.DataVisualization | Out-Null
} catch {
  throw "Не вдалося завантажити Charting. Запускай на Windows PowerShell/PowerShell 7 у Windows."
}

# --- Вхідні файли (із фолбеком назв)
$eduCsv1 = Join-Path $AN "Education_Metrics.csv"
$eduCsv2 = Join-Path $AN "DAO_Education_Metrics.csv"
$eduCsv  = if (Test-Path $eduCsv1){ $eduCsv1 } elseif (Test-Path $eduCsv2){ $eduCsv2 } else { $null }

$certCsv = Join-Path $AN "Cert_Registry.csv"
$mentCsv = Join-Path $AN "Mentorship_Metrics.csv"
$mentReg = Join-Path $AN "DAO_Mentorship_Registry.csv"

if (-not $eduCsv) { Write-Warning "❌ Не знайдено Education_Metrics.csv або DAO_Education_Metrics.csv"; }
if (-not (Test-Path $certCsv)) { Write-Warning "❌ Не знайдено Cert_Registry.csv"; }
if (-not (Test-Path $mentCsv) -and -not (Test-Path $mentReg)) { Write-Warning "❌ Не знайдено ні Mentorship_Metrics.csv, ні DAO_Mentorship_Registry.csv"; }

# --- Діапазон дат
function Parse-YYYYMM($s){ [datetime]::ParseExact($s+"-01","yyyy-MM-dd",$null) }
$now  = Get-Date
if ([string]::IsNullOrWhiteSpace($To))   { $To   = $now.ToString("yyyy-MM") }
if ([string]::IsNullOrWhiteSpace($From)) { $From = $now.AddMonths(-5).ToString("yyyy-MM") } # останні 6 міс

$fromDt = Parse-YYYYMM $From
$toDt   = (Parse-YYYYMM $To).AddMonths(1).AddDays(-1) # кінець місяця

# --- Завантаження CSV
$edu = @()
if ($eduCsv) {
  $rawEdu = Import-Csv -LiteralPath $eduCsv
  foreach($r in $rawEdu){
    # очікувані поля: Date,Metric,Value,...
    $d = $null; [datetime]::TryParse($r.Date, [ref]$d) | Out-Null
    if ($d -eq $null) { continue }
    $v = $null; [double]::TryParse(("$($r.Value)" -replace ',','.'), [ref]$v) | Out-Null
    if ($v -eq $null) { continue }
    $edu += [pscustomobject]@{
      Date=$d; Month=$d.ToString("yyyy-MM"); Metric=$r.Metric; Value=[double]$v
    }
  }
}

$cert = @()
if (Test-Path $certCsv) {
  $rawCert = Import-Csv -LiteralPath $certCsv
  foreach($r in $rawCert){
    $d = $null; [datetime]::TryParse(($r.Issued,$r.Date | Where-Object {$_})[0], [ref]$d) | Out-Null
    if ($d -eq $null){ continue }
    $cert += [pscustomobject]@{ Date=$d; Month=$d.ToString("yyyy-MM") }
  }
}

$ment = @()
if (Test-Path $mentCsv) {
  $rawMent = Import-Csv -LiteralPath $mentCsv
  foreach($r in $rawMent){
    $d = $null; [datetime]::TryParse(($r.Date,$r.Period | Where-Object {$_})[0], [ref]$d) | Out-Null
    if ($d -eq $null){ continue }
    $val = $null; [double]::TryParse(("$($r.Value)" -replace ',','.'), [ref]$val) | Out-Null
    $ment += [pscustomobject]@{ Date=$d; Month=$d.ToString("yyyy-MM"); Metric=$r.Metric; Value=$val }
  }
} elseif (Test-Path $mentReg) {
  # Фолбек: просто рахуємо активні пари як snapshot на місяць, якщо є поле Date (або Created)
  $rawReg = Import-Csv -LiteralPath $mentReg
  foreach($r in $rawReg){
    $d = $null; [datetime]::TryParse(($r.Date, $r.Created, $r.StartDate | Where-Object {$_})[0], [ref]$d) | Out-Null
    if ($d -eq $null){ continue }
    $ment += [pscustomobject]@{ Date=$d; Month=$d.ToString("yyyy-MM"); Metric='ActivePairs'; Value=1 }
  }
}

# --- Фільтр періоду
if ($edu){ $edu = $edu | Where-Object { $_.Date -ge $fromDt -and $_.Date -le $toDt } }
if ($cert){ $cert = $cert | Where-Object { $_.Date -ge $fromDt -and $_.Date -le $toDt } }
if ($ment){ $ment = $ment | Where-Object { $_.Date -ge $fromDt -and $_.Date -le $toDt } }

# --- Агрегації по місяцях
function MonthRange($from,$to){
  $list=@(); $d = Get-Date -Date $from
  while ($d -le $to){
    $list += $d.ToString("yyyy-MM")
    $d = $d.AddMonths(1)
  }
  return $list
}
$months = MonthRange $fromDt $toDt

# EducationIndex: беремо з метрик 'EducationIndex' або 'MetaIndex' (фолбек — середнє нормованих)
$eduMonthly = @{}
foreach($m in $months){ $eduMonthly[$m] = $null }

if ($edu){
  $normSet = @('EducationIndex','MetaIndex','EPR','MR','AII','KSR','AwarenessIndex','CreativePulse')
  foreach($grp in ($edu | Group-Object Month)){
    $m = $grp.Name
    $ei = ($grp.Group | Where-Object {$_.Metric -eq 'EducationIndex'} | Measure-Object Value -Average).Average
    if ($ei){ $eduMonthly[$m] = [math]::Round($ei,3); continue }
    $mi = ($grp.Group | Where-Object {$_.Metric -eq 'MetaIndex'} | Measure-Object Value -Average).Average
    if ($mi){ $eduMonthly[$m] = [math]::Round($mi,3); continue }
    $pool = $grp.Group | Where-Object { $normSet -contains $_.Metric } | Select-Object -ExpandProperty Value
    if ($pool){ $eduMonthly[$m] = [math]::Round(($pool | Measure-Object -Average).Average,3) }
  }
}

# Certificates per month
$certMonthly = @{}
foreach($m in $months){ $certMonthly[$m] = 0 }
if ($cert){
  foreach($grp in ($cert | Group-Object Month)){
    $certMonthly[$grp.Name] = $grp.Count
  }
}

# Mentorship metric: беремо з Mentorship_Metrics (Metric='ActivePairs' або 'MentorshipActivity'), інакше — count з реєстру
$mentMonthly = @{}
foreach($m in $months){ $mentMonthly[$m] = $null }
if ($ment){
  $grouped = $ment | Group-Object Month
  foreach($g in $grouped){
    $v = ($g.Group | Where-Object { $_.Metric -in @('MentorshipActivity','ActivePairs','Pairs') } | Select-Object -ExpandProperty Value)
    if ($v){ $mentMonthly[$g.Name] = [math]::Round((($v | Measure-Object -Average).Average),2) }
    else { $mentMonthly[$g.Name] = $g.Count } # простий фолбек: кількість записів
  }
}

# --- Експорт агрегованих CSV
$agg = foreach($m in $months){
  [pscustomobject]@{
    Month=$m
    EducationIndex = $eduMonthly[$m]
    Certificates   = $certMonthly[$m]
    Mentorship     = $mentMonthly[$m]
  }
}
$aggCsv = Join-Path $OUT ("DAO_Academy_Aggregates_{0}-{1}.csv" -f $From, $To)
$agg | Export-Csv -LiteralPath $aggCsv -NoTypeInformation -Encoding UTF8

# --- Функція побудови графіка
function New-LineChart {
  param(
    [string]$title,
    [hashtable]$seriesMap,   # @{ 'SeriesName' = @{ X=@(...months...), Y=@(...values...) } ; ... }
    [string]$outPng,
    [int]$width=1280,
    [int]$height=720,
    [double]$yMin = [double]::NaN,
    [double]$yMax = [double]::NaN
  )
  $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
  $chart.Width  = $width
  $chart.Height = $height
  $ca = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea "Main"
  $chart.ChartAreas.Add($ca)
  $chart.Titles.Add($title) | Out-Null
  $chart.Titles[0].Font = New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold)

  # Оформлення осей
  $chart.ChartAreas["Main"].AxisX.Interval = 1
  $chart.ChartAreas["Main"].AxisX.MajorGrid.Enabled = $false
  $chart.ChartAreas["Main"].AxisY.MajorGrid.LineDashStyle = 'Dash'
  if (-not [double]::IsNaN($yMin)) { $chart.ChartAreas["Main"].AxisY.Minimum = $yMin }
  if (-not [double]::IsNaN($yMax)) { $chart.ChartAreas["Main"].AxisY.Maximum = $yMax }

  foreach($sName in $seriesMap.Keys){
    $s = New-Object System.Windows.Forms.DataVisualization.Charting.Series $sName
    $s.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Line
    $s.BorderWidth = 3
    $chart.Series.Add($s) | Out-Null
    $X = $seriesMap[$sName].X
    $Y = $seriesMap[$sName].Y
    for($i=0;$i -lt $X.Count;$i++){
      $val = $Y[$i]
      if ($null -ne $val){ [void]$s.Points.AddXY($X[$i], [double]$val) } else { [void]$s.Points.AddXY($X[$i], [double]::NaN) }
    }
  }
  $chart.SaveImage($outPng, "Png")
}

# --- Побудова окремих графіків
$monthsX = $months
function GetSeries($vals){ $monthsX | ForEach-Object { $vals[$_] } }

$pngEdu = Join-Path $OUT ("EducationIndex_{0}-{1}.png" -f $From, $To)
$pngCer = Join-Path $OUT ("Certificates_{0}-{1}.png"    -f $From, $To)
$pngMen = Join-Path $OUT ("Mentorship_{0}-{1}.png"      -f $From, $To)

New-LineChart -title "G29 · Education Index (Monthly)" `
  -seriesMap @{ "EducationIndex" = @{ X=$monthsX; Y=(GetSeries $eduMonthly) } } `
  -outPng $pngEdu -yMin 0 -yMax 1

New-LineChart -title "G29 · Certificates Issued (Monthly)" `
  -seriesMap @{ "Certificates" = @{ X=$monthsX; Y=(GetSeries $certMonthly) } } `
  -outPng $pngCer

New-LineChart -title "G29 · Mentorship Activity (Monthly)" `
  -seriesMap @{ "Mentorship" = @{ X=$monthsX; Y=(GetSeries $mentMonthly) } } `
  -outPng $pngMen

# --- Комбінований дашборд (3 серії на 2 осях: ліворуч 0-1, праворуч авто)
$dashPng = Join-Path $OUT ("DAO_Academy_Dashboard_{0}-{1}.png" -f $From, $To)
$chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$chart.Width  = 1400
$chart.Height = 800

$ca = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea "Main"
$chart.ChartAreas.Add($ca)
$chart.Titles.Add("DAO-Academy Dashboard · $From → $To") | Out-Null
$chart.Titles[0].Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold)

# Secondary Y for counts
$chart.ChartAreas["Main"].AxisX.Interval = 1
$chart.ChartAreas["Main"].AxisY2.Enabled = [System.Windows.Forms.DataVisualization.Charting.AxisEnabled]::True
$chart.ChartAreas["Main"].AxisY.Minimum = 0
$chart.ChartAreas["Main"].AxisY.Maximum = 1
$chart.ChartAreas["Main"].AxisY.Title = "Index (0..1)"
$chart.ChartAreas["Main"].AxisY2.Title = "Counts"

# EducationIndex (primary)
$s1 = New-Object System.Windows.Forms.DataVisualization.Charting.Series "EducationIndex"
$s1.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Line
$s1.BorderWidth = 3
$chart.Series.Add($s1) | Out-Null

# Certificates (secondary)
$s2 = New-Object System.Windows.Forms.DataVisualization.Charting.Series "Certificates"
$s2.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Column
$s2.YAxisType = [System.Windows.Forms.DataVisualization.Charting.AxisType]::Secondary
$chart.Series.Add($s2) | Out-Null

# Mentorship (secondary)
$s3 = New-Object System.Windows.Forms.DataVisualization.Charting.Series "Mentorship"
$s3.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Line
$s3.BorderDashStyle = 'Dash'
$s3.YAxisType = [System.Windows.Forms.DataVisualization.Charting.AxisType]::Secondary
$chart.Series.Add($s3) | Out-Null

for($i=0;$i -lt $monthsX.Count;$i++){
  $m = $monthsX[$i]
  [void]$s1.Points.AddXY($m, [double]($(if($eduMonthly[$m] -ne $null){$eduMonthly[$m]}else{[double]::NaN})))
  [void]$s2.Points.AddXY($m, [double]($(if($certMonthly[$m] -ne $null){$certMonthly[$m]}else{0})))
  [void]$s3.Points.AddXY($m, [double]($(if($mentMonthly[$m] -ne $null){$mentMonthly[$m]}else{[double]::NaN})))
}

$chart.SaveImage($dashPng, "Png")

# --- Вивід підсумків
Write-Host "[OK] Aggregates -> $aggCsv"
Write-Host "[OK] Chart -> $pngEdu"
Write-Host "[OK] Chart -> $pngCer"
Write-Host "[OK] Chart -> $pngMen"
Write-Host "[OK] Dashboard -> $dashPng"
