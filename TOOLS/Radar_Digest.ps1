# Radar_Digest.ps1 — v1.0
# Призначення: згенерувати короткий дайджест Radar (MD/HTML) з Radar_Last.json або останнього Summary CSV.
# Вивід: C07_ANALYTICS\Radar_Digest_<YYYY-MM-DD>.md / .html
# Опціонально: META-лог події (PublishMeta), авто-відкриття HTML (OpenAfter)

param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$Analytics = "",
  [string]$Version = "v1.0",
  [string]$DateTag = (Get-Date).ToString('yyyy-MM-dd'),
  [switch]$OpenAfter,
  [switch]$PublishMeta
)

# ---------- helpers ----------
function Ensure-Dir([string]$p){
  $d = Split-Path -Parent $p
  if($d -and -not (Test-Path -LiteralPath $d)){
    New-Item -ItemType Directory -Path $d -Force | Out-Null
  }
}
function Write-Text([string]$path,[string]$text){
  Ensure-Dir $path
  [System.IO.File]::WriteAllText($path,$text,[System.Text.Encoding]::UTF8)
}
function Read-Json([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ return $null }
  try {
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  } catch { return $null }
}
function Read-CsvMap([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ return @{} }
  $rows = Import-Csv -LiteralPath $path
  $map = @{}
  foreach($r in $rows){ if($r.Metric -and $r.Value -ne $null){ $map[$r.Metric] = [double]$r.Value } }
  return $map
}
function ToFixed([double]$v,[int]$d=2){ return ("{0:N$($d)}" -f $v) }

# ---------- resolve paths ----------
if(-not $Analytics){ $Analytics = Join-Path $RepoRoot 'C07_ANALYTICS' }
if(-not (Test-Path -LiteralPath $Analytics)){ New-Item -ItemType Directory -Path $Analytics -Force | Out-Null }

$jsonPath   = Join-Path $Analytics 'Radar_Last.json'
$mdOut      = Join-Path $Analytics ("Radar_Digest_{0}.md" -f $DateTag)
$htmlOut    = Join-Path $Analytics ("Radar_Digest_{0}.html" -f $DateTag)

# ---------- load last metrics ----------
$data = Read-Json $jsonPath
$from = "json"
if($null -eq $data){
  # fallback: найсвіжіший summary
  $cands = Get-ChildItem -LiteralPath $Analytics -Filter 'CheCha_Radar_Summary_*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  if(-not $cands -or $cands.Count -eq 0){
    throw "Немає Radar_Last.json та CheCha_Radar_Summary_*.csv у $Analytics"
  }
  $summaryPath = $cands[0].FullName
  $map = Read-CsvMap $summaryPath
  if($map.Count -eq 0){ throw "Порожній summary: $summaryPath" }
  $dateFromName = (Split-Path -Leaf $summaryPath) -replace 'CheCha_Radar_Summary_','' -replace '\.csv$',''
  $data = [pscustomobject]@{
    Date = $dateFromName
    Stability = $map['SystemStability']
    Clean     = $map['InfoCleanliness']
    Sync      = $map['CommSync']
    Edu       = $map['EducationActivity']
    Anal      = $map['AnalyticIntegration']
    Avg       = [math]::Round( ($map['SystemStability']+$map['InfoCleanliness']+$map['CommSync']+$map['EducationActivity']+$map['AnalyticIntegration'])/5.0, 3 )
    Version   = $Version
  }
  $from = "csv"
}

# нормалізація значень
$dt  = [string]$data.Date
$st  = [double]$data.Stability
$cl  = [double]$data.Clean
$sy  = [double]$data.Sync
$ed  = [double]$data.Edu
$an  = [double]$data.Anal
$avg = if($data.PSObject.Properties.Name -contains 'Avg'){ [double]$data.Avg } else { [math]::Round(($st+$cl+$sy+$ed+$an)/5.0,3) }

# ---------- build Markdown ----------
$md = @()
$md += '# 📡 CheCha Radar — Digest'
$md += ('**Дата:** ' + $dt + '  ')
$md += ('**Версія:** ' + $Version + '  ')
$md += ('**Джерело даних:** ' + $from)
$md += ''
$md += '## Індекси (останній зріз)'
$md += '| Показник | Значення |'
$md += '|---|---:|'
$md += ('| Стабільність системи | ' + (ToFixed $st 2) + ' |')
$md += ('| Інформаційна чистота | ' + (ToFixed $cl 2) + ' |')
$md += ('| Комунікаційна синхронізація | ' + (ToFixed $sy 2) + ' |')
$md += ('| Освітня активність | ' + (ToFixed $ed 2) + ' |')
$md += ('| Аналітична інтеграція | ' + (ToFixed $an 2) + ' |')
$md += ''
$md += ('**Середній індекс (AvgIndex):** ' + (ToFixed $avg 3))
$md += ''
$md += '## Коментар (шаблон)'
$md += '- Стан системи стабільний, дані узгоджені.'
$md += '- Рекомендація: розширити карти інструментів і сигналів для глибшого тренду.'
$md += ''
$md += '_Автоматично згенеровано CheCha CORE • ITETA_'
Write-Text $mdOut ([string]::Join("`r`n",$md))

# ---------- build HTML (легкий шаблон) ----------
$html = @()
$html += '<!DOCTYPE html><html lang="uk"><head><meta charset="utf-8"/>'
$html += '<meta name="viewport" content="width=device-width,initial-scale=1"/>'
$html += '<title>CheCha Radar — Digest</title>'
$html += '<style>body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:20px;color:#111}'
$html += '.wrap{max-width:860px;margin:0 auto}'
$html += 'h1{font-size:22px;margin:0 0 8px} .muted{color:#666;font-size:13px;margin:0 0 14px}'
$html += 'table{border-collapse:collapse;margin:12px 0} th,td{border:1px solid #ddd;padding:6px 10px} th{text-align:left}'
$html += '.kpi{font-size:16px;margin-top:8px}'
$html += '</style></head><body><div class="wrap">'
$html += '<h1>CheCha Radar — Digest</h1>'
$html += ('<div class="muted">Дата: '+$dt+' · Версія: '+$Version+' · Джерело: '+$from+'</div>')
$html += '<table><thead><tr><th>Показник</th><th>Значення</th></tr></thead><tbody>'
$html += ('<tr><td>Стабільність системи</td><td>'+ (ToFixed $st 2) +'</td></tr>')
$html += ('<tr><td>Інформаційна чистота</td><td>'+ (ToFixed $cl 2) +'</td></tr>')
$html += ('<tr><td>Комунікаційна синхронізація</td><td>'+ (ToFixed $sy 2) +'</td></tr>')
$html += ('<tr><td>Освітня активність</td><td>'+ (ToFixed $ed 2) +'</td></tr>')
$html += ('<tr><td>Аналітична інтеграція</td><td>'+ (ToFixed $an 2) +'</td></tr>')
$html += '</tbody></table>'
$html += ('<div class="kpi"><strong>Середній індекс (AvgIndex):</strong> '+ (ToFixed $avg 3) +'</div>')
$html += '<h2>Коментар (шаблон)</h2>'
$html += '<ul><li>Стан системи стабільний, дані узгоджені.</li><li>Рекомендація: розширити карти інструментів і сигналів для глибшого тренду.</li></ul>'
$html += '<div class="muted">Автоматично згенеровано CheCha CORE • ITETA</div>'
$html += '</div></body></html>'
Write-Text $htmlOut ([string]::Join([Environment]::NewLine,$html))

# ---------- optional META log ----------
if($PublishMeta){
  $meta = "D:\CHECHA_CORE\TOOLS\Write-MetaLayerEntry.ps1"
  if(Test-Path -LiteralPath $meta){
    & $meta -Event ("Radar_Digest " + $Version) -Intent "Публікація дайджесту Radar" `
      -Observation ("Збережено MD/HTML для "+$dt) `
      -Insight "Короткий зріз стану доступний для розсилки/архіву" `
      -EmotionalTone "потік" -BalanceShift 0.1 -MetaIndex $avg `
      -Tags Analytic,Tech,Spirit
  }
}

# ---------- optional open ----------
if($OpenAfter){ Start-Process -FilePath $htmlOut }

exit 0
