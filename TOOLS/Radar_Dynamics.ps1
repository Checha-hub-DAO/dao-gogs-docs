# Radar_Dynamics.ps1 — v1.0
# Призначення: зчитати поточний CheCha_Radar_Summary_YYYY-MM-DD.csv,
#   дописати ряд у Radar_Dynamics.csv та згенерувати Radar_Dynamics.html (SVG-графік)
# Сумісність: PowerShell 5.1 / 7.x

param(
  [string]$RepoRoot   = "D:\CHECHA_CORE",
  [string]$Analytics  = "",         # якщо пусто -> RepoRoot\C07_ANALYTICS
  [string]$Version    = "v1.0",
  [string]$DateTag    = (Get-Date).ToString('yyyy-MM-dd'),
  [switch]$Strict     # якщо true — кине помилку, якщо summary не знайдено
)

# ---------- helpers ----------
function Ensure-Dir([string]$p){
  $d = Split-Path -Parent $p
  if($d -and -not (Test-Path -LiteralPath $d)){
    New-Item -ItemType Directory -Path $d -Force | Out-Null
  }
}
function Read-CsvMap([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ return @{} }
  $rows = Import-Csv -LiteralPath $path
  $map = @{}
  foreach($r in $rows){
    if($r.Metric -and $r.Value -ne $null){
      $map[$r.Metric] = [double]$r.Value
    }
  }
  return $map
}
function Write-Text([string]$path,[string]$text){
  Ensure-Dir $path
  [System.IO.File]::WriteAllText($path,$text,[System.Text.Encoding]::UTF8)
}
function Append-Text([string]$path,[string]$text){
  Ensure-Dir $path
  [System.IO.File]::AppendAllText($path,$text,[System.Text.Encoding]::UTF8)
}

# ---------- resolve paths ----------
if(-not $Analytics){ $Analytics = Join-Path $RepoRoot 'C07_ANALYTICS' }
if(-not (Test-Path -LiteralPath $Analytics)){ New-Item -ItemType Directory -Path $Analytics -Force | Out-Null }

$summaryName = ("CheCha_Radar_Summary_{0}.csv" -f $DateTag)
$summaryPath = Join-Path $Analytics $summaryName
$dynamicsCsv = Join-Path $Analytics 'Radar_Dynamics.csv'
$dynamicsHtml = Join-Path $Analytics 'Radar_Dynamics.html'

# ---------- load today's summary ----------
$metrics = Read-CsvMap $summaryPath
if($metrics.Count -eq 0){
  # спробуємо знайти найсвіжіший summary за останні 7 днів
  $cands = Get-ChildItem -LiteralPath $Analytics -Filter 'CheCha_Radar_Summary_*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  if($cands -and $cands.Count -gt 0){
    $summaryPath = $cands[0].FullName
    $metrics = Read-CsvMap $summaryPath
    # оновимо DateTag з імені файла, якщо змогли
    $bn = Split-Path -Leaf $summaryPath
    if($bn -match 'CheCha_Radar_Summary_(\d{4}-\d{2}-\d{2})\.csv'){
      $DateTag = $Matches[1]
    }
  }
}

if($metrics.Count -eq 0){
  if($Strict){
    throw "Не знайдено актуальний CheCha_Radar_Summary_*.csv у $Analytics"
  } else {
    Write-Host "[WARN] Summary не знайдено. Завершення без оновлення динаміки."
    exit 0
  }
}

# ---------- extract five metrics ----------
$st = $metrics['SystemStability']
$cl = $metrics['InfoCleanliness']
$sy = $metrics['CommSync']
$ed = $metrics['EducationActivity']
$an = $metrics['AnalyticIntegration']

if($null -eq $st -or $null -eq $cl -or $null -eq $sy -or $null -eq $ed -or $null -eq $an){
  throw "У summary відсутні потрібні метрики (SystemStability, InfoCleanliness, CommSync, EducationActivity, AnalyticIntegration)."
}

# середній інтегральний індекс для графіка
$avg = [math]::Round( ($st + $cl + $sy + $ed + $an) / 5.0, 3 )

# ---------- append to Radar_Dynamics.csv ----------
$needHeader = -not (Test-Path -LiteralPath $dynamicsCsv)
if($needHeader){
  $header = 'Date,Stability,Clean,Sync,Edu,Anal,AvgIndex'
  Write-Text $dynamicsCsv ($header + "`r`n")
}
$line = ("{0},{1},{2},{3},{4},{5},{6}" -f $DateTag, $st, $cl, $sy, $ed, $an, $avg)
Append-Text $dynamicsCsv ($line + "`r`n")

# ---------- read all rows for chart ----------
$rows = Import-Csv -LiteralPath $dynamicsCsv
if(-not $rows -or $rows.Count -eq 0){ exit 0 }

# підготуємо масив точок для AvgIndex
$pts = @()
$minY = 1.0
$maxY = 0.0
$i = 0
foreach($r in $rows){
  $v = [double]$r.AvgIndex
  if($v -lt $minY){ $minY = $v }
  if($v -gt $maxY){ $maxY = $v }
  $pts += [pscustomobject]@{ idx=$i; val=$v; date=$r.Date }
  $i++
}
if($pts.Count -lt 2){ $minY = 0.0; $maxY = [math]::Max(1.0,$maxY) }

# нормування в координати SVG
$width = 900
$height = 260
$padL = 60
$padR = 20
$padT = 20
$padB = 40
$plotW = $width - $padL - $padR
$plotH = $height - $padT - $padB

$minY = [math]::Min($minY, 0.0)
$maxY = [math]::Max($maxY, 1.0)
$ySpan = [math]::Max(0.0001, $maxY - $minY)

# polyline points
$ptStrings = @()
$n = [double]([math]::Max(1, $pts.Count - 1))
foreach($p in $pts){
  $x = $padL + ($plotW * ($p.idx / $n))
  $y = $padT + $plotH * (1.0 - (($p.val - $minY) / $ySpan))
  $ptStrings += ("{0},{1}" -f ([int]$x), ([int]$y))
}
$pointsAttr = [string]::Join(' ', $ptStrings)

# grid / axes ticks (0, 0.5, 1.0)
$gy0 = $padT + $plotH * (1.0 - ((0 - $minY)/$ySpan))
$gy5 = $padT + $plotH * (1.0 - ((0.5 - $minY)/$ySpan))
$gy1 = $padT + $plotH * (1.0 - ((1.0 - $minY)/$ySpan))

# labels
$lastDate = $pts[-1].date
$subTitle = "AvgIndex trend — " + $pts.Count + " pts; last: " + $lastDate

# ---------- build HTML (без here-strings) ----------
$html = @()
$html += '<!DOCTYPE html>'
$html += '<html lang="uk"><head><meta charset="utf-8"/>'
$html += '<meta name="viewport" content="width=device-width, initial-scale=1"/>'
$html += '<title>CheCha Radar Dynamics</title>'
$html += '<style>'
$html += 'body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:16px;color:#111}'
$html += '.wrap{max-width:980px;margin:0 auto}'
$html += 'h1{font-size:22px;margin:0 0 6px} .muted{color:#666;font-size:13px;margin-bottom:10px}'
$html += 'table{border-collapse:collapse;margin-top:16px} th,td{border:1px solid #ddd;padding:6px 8px}'
$html += '</style></head><body><div class="wrap">'
$html += '<h1>CheCha Radar — Dynamics</h1>'
$html += '<div class="muted">' + $subTitle + '</div>'
$html += ('<svg width="{0}" height="{1}" viewBox="0 0 {0} {1}" xmlns="http://www.w3.org/2000/svg">' -f $width,$height)

# axes
$html += ('<rect x="{0}" y="{1}" width="{2}" height="{3}" fill="#fafafa" stroke="#ccc"/>' -f $padL,$padT,$plotW,$plotH)
$html += ('<line x1="{0}" y1="{1}" x2="{2}" y2="{1}" stroke="#ccc" stroke-dasharray="4,4"/>' -f $padL,[int]$gy0,($padL+$plotW))
$html += ('<line x1="{0}" y1="{1}" x2="{2}" y2="{1}" stroke="#ccc" stroke-dasharray="4,4"/>' -f $padL,[int]$gy5,($padL+$plotW))
$html += ('<line x1="{0}" y1="{1}" x2="{2}" y2="{1}" stroke="#ccc" stroke-dasharray="4,4"/>' -f $padL,[int]$gy1,($padL+$plotW))
$html += ('<text x="{0}" y="{1}" font-size="12" fill="#444">0.0</text>' -f ($padL-40),([int]$gy0+4))
$html += ('<text x="{0}" y="{1}" font-size="12" fill="#444">0.5</text>' -f ($padL-40),([int]$gy5+4))
$html += ('<text x="{0}" y="{1}" font-size="12" fill="#444">1.0</text>' -f ($padL-40),([int]$gy1+4))

# polyline
$html += ('<polyline fill="none" stroke="#1f77b4" stroke-width="2" points="{0}"/>' -f $pointsAttr)

# last point marker + label
$last = $pts[-1]
$lx = $padL + ($plotW * ($last.idx / $n))
$ly = $padT + $plotH * (1.0 - (($last.val - $minY) / $ySpan))
$html += ('<circle cx="{0}" cy="{1}" r="3" fill="#d62728"/>' -f ([int]$lx),([int]$ly))
$html += ('<text x="{0}" y="{1}" font-size="12" fill="#d62728">avg={2}</text>' -f ([int]$lx+8),([int]$ly-8),$avg)

$html += '</svg>'

# small table with last values
$html += '<table><thead><tr><th>Date</th><th>Stab</th><th>Clean</th><th>Sync</th><th>Edu</th><th>Anal</th><th>Avg</th></tr></thead><tbody>'
$lastRow = $rows[-1]
$html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td></tr>' -f `
  $lastRow.Date, $lastRow.Stability, $lastRow.Clean, $lastRow.Sync, $lastRow.Edu, $lastRow.Anal, $lastRow.AvgIndex)
$html += '</tbody></table>'

$html += '</div></body></html>'

$doc = [string]::Join([Environment]::NewLine, $html)
Write-Text $dynamicsHtml $doc

# done
exit 0
