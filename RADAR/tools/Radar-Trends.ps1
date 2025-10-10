<#
  Radar-Trends.ps1
  Збирає денні тренди за артефактами та генерує CSV/HTML-звіт.

  Вивід:
    - <RepoRoot>\RADAR\REPORTS\Radar-Trends_daily.csv
    - <RepoRoot>\RADAR\REPORTS\Radar-TopTags_daily.csv
    - <RepoRoot>\RADAR\REPORTS\Radar-Trends_<from>_to_<to>_<stamp>.html

  Параметри часу приймають ISO або yyyy-MM-dd.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,
  [string]$OutDir,
  [string]$From,                # нижня межа (якщо порожньо — 30 днів тому)
  [string]$To,                  # верхня межа (якщо порожньо — зараз)
  [string]$Lang,                # опційний фільтр мови
  [int]$TopNSources = 10,
  [int]$TopNTags = 15,
  [switch]$OpenWhenDone
)

function Write-Log([string]$Message,[string]$Level="INFO"){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$Level] $ts $Message"
}
function Ensure-Dir([string]$path){
  if(-not $path){ return }
  if(!(Test-Path -LiteralPath $path)){ New-Item -ItemType Directory -Path $path -Force | Out-Null }
}
function Parse-Date([string]$s, [datetime]$fallback){
  if([string]::IsNullOrWhiteSpace($s)){ return $fallback }
  try{ return [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) }
  catch{ return $fallback }
}
function TryNum([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return $null }
  $s2 = $s -replace ',','.'
  $n = 0.0
  if([double]::TryParse($s2, [ref]$n)){ return $n } else { return $null }
}

try{
  # 0) Шляхи
  if([string]::IsNullOrWhiteSpace($CsvPath)){ $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if([string]::IsNullOrWhiteSpace($OutDir)){  $OutDir  = Join-Path $RepoRoot 'RADAR\REPORTS' }
  if(!(Test-Path -LiteralPath $CsvPath)){ throw "Не знайдено індекс: $CsvPath" }
  Ensure-Dir $OutDir

  # 1) Діапазон дат
  $now = Get-Date
  $fromDt = Parse-Date $From ($now.AddDays(-30))
  $toDt   = Parse-Date $To   $now
  if($fromDt -gt $toDt){ $tmp=$fromDt; $fromDt=$toDt; $toDt=$tmp }

  Write-Log "CSV: $CsvPath"
  Write-Log "Діапазон: $($fromDt.ToString('yyyy-MM-dd HH:mm')) → $($toDt.ToString('yyyy-MM-dd HH:mm'))"
  if($Lang){ Write-Log "Фільтр мови: $Lang" }

  # 2) Завантаження CSV
  $raw = Import-Csv -LiteralPath $CsvPath
  if(-not $raw -or $raw.Count -eq 0){ throw "Порожній індекс артефактів." }

  # 3) Нормалізація записів
  $artifacts = foreach($r in $raw){
    $ts = $null; [datetime]::TryParse($r.timestamp, [ref]$ts) | Out-Null
    if($null -eq $ts){ continue }
    if($ts -lt $fromDt -or $ts -gt $toDt){ continue }
    if($Lang -and $r.lang -ne $Lang){ continue }

    $score = TryNum $r.RadarScore
    $tox   = TryNum $r.toxicity_score
    $tags  = @()
    if($r.tags){
      $tags = $r.tags -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    [pscustomobject]@{
      day        = $ts.Date
      timestamp  = $ts
      source     = $r.source
      lang       = $r.lang
      title      = $r.title
      summary    = $r.summary
      tags       = $tags
      score      = $score
      toxicity   = $tox
    }
  }

  if(-not $artifacts){ Write-Log "Немає записів у діапазоні." "WARN" }

  # 4) Денна агрегація
  $daily = $artifacts | Group-Object day | ForEach-Object {
    $items = $_.Group
    $cnt   = $items.Count
    $avgSc = ($items | Where-Object { $_.score -ne $null } | Measure-Object score -Average).Average
    $avgTx = ($items | Where-Object { $_.toxicity -ne $null } | Measure-Object toxicity -Average).Average
    if($avgSc -eq $null){ $avgSc = 0 }
    if($avgTx -eq $null){ $avgTx = 0 }

    # ТОП-джерела в межах дня
    $topSrc = ($items | Group-Object source | Sort-Object Count -Descending | Select-Object -First $TopNSources |
               ForEach-Object { "{0}({1})" -f $_.Name, $_.Count }) -join '; '

    # ТОП-теги в межах дня
    $allTags = @()
    foreach($it in $items){ if($it.tags){ $allTags += $it.tags } }
    $topTag = if($allTags){
      ($allTags | Group-Object | Sort-Object Count -Descending | Select-Object -First $TopNTags |
       ForEach-Object { "{0}({1})" -f $_.Name, $_.Count }) -join '; '
    } else { "" }

    [pscustomobject]@{
      Day             = $_.Name.ToString('yyyy-MM-dd')
      Count           = $cnt
      AvgRadarScore   = [Math]::Round([double]$avgSc, 4)
      AvgToxicity     = [Math]::Round([double]$avgTx, 4)
      TopSources      = $topSrc
      TopTags         = $topTag
    }
  } | Sort-Object Day

  # 5) Добова таблиця "топ-теги" (окремий CSV)
  $dailyTopTags = foreach($g in ($artifacts | Group-Object day)){
    $dayStr = $g.Name.ToString('yyyy-MM-dd')
    $allTags = @()
    foreach($it in $g.Group){ if($it.tags){ $allTags += $it.tags } }
    if(-not $allTags){ continue }
    $allTags | Group-Object | Sort-Object Count -Descending | Select-Object -First $TopNTags |
      ForEach-Object {
        [pscustomobject]@{
          Day  = $dayStr
          Tag  = $_.Name
          Count= $_.Count
        }
      }
  }

  # 6) Запис CSV
  $csvDailyPath   = Join-Path $OutDir 'Radar-Trends_daily.csv'
  $csvTagsPath    = Join-Path $OutDir 'Radar-TopTags_daily.csv'
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $daily | Export-Csv -LiteralPath $csvDailyPath -NoTypeInformation -Encoding UTF8
  $dailyTopTags | Export-Csv -LiteralPath $csvTagsPath -NoTypeInformation -Encoding UTF8

  Write-Log "Збережено: $csvDailyPath"
  Write-Log "Збережено: $csvTagsPath"

  # 7) HTML-огляд
  $rangeTag = "{0}_to_{1}" -f $fromDt.ToString('yyyy-MM-dd'), $toDt.ToString('yyyy-MM-dd')
  $stamp = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
  $htmlPath = Join-Path $OutDir ("Radar-Trends_{0}_{1}.html" -f $rangeTag,$stamp)

  $dailyRows = if($daily){
    ($daily | ForEach-Object {
      "<tr><td>$($_.Day)</td><td>$($_.Count)</td><td>$($_.AvgRadarScore)</td><td>$($_.AvgToxicity)</td><td>$([System.Web.HttpUtility]::HtmlEncode($_.TopSources))</td><td>$([System.Web.HttpUtility]::HtmlEncode($_.TopTags))</td></tr>"
    }) -join "`n"
  } else { "<tr><td colspan='6'>Немає даних</td></tr>" }

  $html = @"
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="utf-8">
<title>Radar Trends — $rangeTag</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body{font-family: DejaVu Sans, Arial, sans-serif; margin:16px; line-height:1.45}
  h1,h2{margin:0.3em 0}
  .meta{color:#555;margin-bottom:8px}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #e3e7ef;padding:8px;vertical-align:top}
  th{background:#f0f3f9;text-align:left}
  .kpi{display:flex;gap:20px;margin:12px 0 18px}
  .kpi div{background:#f5f7fb;padding:10px 14px;border-radius:10px;box-shadow:0 1px 2px rgba(0,0,0,.06)}
  .small{font-size:12px;color:#666}
</style>
</head>
<body>
<h1>Radar Trends — $rangeTag</h1>
<div class="meta">Згенеровано: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>

<div class="kpi">
  <div><b>Днів у вибірці:</b> $(@($daily).Count)</div>
  <div><b>Сумарно артефактів:</b> $( ($artifacts | Measure-Object).Count )</div>
  <div><b>Середній RadarScore (усереднений по днях):</b> $( if($daily){ [Math]::Round((($daily | Measure-Object AvgRadarScore -Average).Average), 4) } else { 0 } )</div>
</div>

<h2>Денні підсумки</h2>
<table>
  <thead>
    <tr>
      <th>День</th><th>К-сть</th><th>Avg RadarScore</th><th>Avg Toxicity</th><th>Топ-джерела</th><th>Топ-теги</th>
    </tr>
  </thead>
  <tbody>
    $dailyRows
  </tbody>
</table>

<div class="small" style="margin-top:10px">
  Файли: <code>$csvDailyPath</code>, <code>$csvTagsPath</code>
</div>

</body>
</html>
"@

  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($htmlPath, $html, $utf8Bom)
  Write-Log "HTML збережено: $htmlPath"
  if($OpenWhenDone){ Invoke-Item -LiteralPath $htmlPath }

  # 8) Логування в C03_LOG
  $logDir = Join-Path $RepoRoot 'C03_LOG'
  Ensure-Dir $logDir
  Add-Content -Path (Join-Path $logDir 'RADAR_TRENDS_LOG.md') -Encoding UTF8 `
    ("- [{0}] Range={1}→{2} | Days={3} | Artifacts={4} | CSV='{5}','{6}' | HTML='{7}'" -f `
      (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
      $fromDt.ToString('yyyy-MM-dd'), $toDt.ToString('yyyy-MM-dd'),
      @($daily).Count, (@($artifacts).Count), $csvDailyPath, $csvTagsPath, $htmlPath)

  exit 0
}
catch{
  Write-Log $_.Exception.Message "ERR"
  exit 1
}
