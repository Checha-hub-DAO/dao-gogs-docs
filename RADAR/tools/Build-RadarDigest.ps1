<# 
.SYNOPSIS
  Генерує HTML-дайджест радaру з artifacts.csv

.PARAMETER RepoRoot
  Корінь CHECHA_CORE (де лежать RADAR\...)

.PARAMETER CsvPath
  Шлях до індексу артефактів (CSV). За замовчуванням: <RepoRoot>\RADAR\INDEX\artifacts.csv

.PARAMETER OutDir
  Каталог для HTML-звітів. За замовчуванням: <RepoRoot>\RADAR\REPORTS

.PARAMETER From
  Нижня межа часу включно (ISO 8601 або yyyy-MM-dd). Якщо не задано — 7 днів тому.

.PARAMETER To
  Верхня межа часу включно (ISO 8601 або yyyy-MM-dd). Якщо не задано — зараз.

.PARAMETER TopN
  Скільки топ-артефактів показати у основному блоці (за RadarScore). За замовчуванням: 25.

.PARAMETER Lang
  Фільтр мови ("uk","en", тощо) — необов'язково.

.PARAMETER MinScore
  Мінімальний RadarScore для включення у дайджест. За замовчуванням: 0.

.PARAMETER OpenWhenDone
  Відкрити HTML у браузері після генерації.

.NOTES
  UTF-8 BOM, без зовнішніх залежностей. Сумісний із pwsh/Windows PowerShell.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,
  [string]$OutDir,
  [string]$From,
  [string]$To,
  [int]$TopN = 25,
  [string]$Lang,
  [double]$MinScore = 0,
  [switch]$OpenWhenDone
)

#region Helpers
function Write-Log {
  param([string]$Message,[string]$Level="INFO")
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$Level] $ts $Message"
}
function Ensure-Dir([string]$path){
  if(-not $path){ return }
  if(!(Test-Path -LiteralPath $path)){ New-Item -ItemType Directory -Path $path -Force | Out-Null }
}
function Parse-Date([string]$s, [datetime]$fallback){
  if([string]::IsNullOrWhiteSpace($s)){ return $fallback }
  try{
    # підтримує ISO/yyy-MM-dd
    return [datetime]::Parse($s, $([System.Globalization.CultureInfo]::InvariantCulture))
  }catch{
    return $fallback
  }
}
#endregion Helpers

try {
  # 0) Шляхи за замовчуванням
  if([string]::IsNullOrWhiteSpace($CsvPath)){ $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if([string]::IsNullOrWhiteSpace($OutDir)){  $OutDir  = Join-Path $RepoRoot 'RADAR\REPORTS' }

  if(!(Test-Path -LiteralPath $CsvPath)){ throw "Індекс не знайдено: $CsvPath" }
  Ensure-Dir $OutDir

  # 1) Діапазон дат
  $now = Get-Date
  $fromDt = Parse-Date $From ($now.AddDays(-7))
  $toDt   = Parse-Date $To   $now

  Write-Log "CSV: $CsvPath"
  Write-Log "Діапазон: $($fromDt.ToString('yyyy-MM-dd HH:mm')) → $($toDt.ToString('yyyy-MM-dd HH:mm'))"
  if($Lang){ Write-Log "Фільтр мови: $Lang" }
  Write-Log "Поріг RadarScore: $MinScore; TopN=$TopN"

  # 2) Читання CSV (UTF-8)
  $rows = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){
    throw "В індексі відсутні записи."
  }

  # Перетворення типів
  $artifacts = foreach($r in $rows){
    # безпечне парсення дат і чисел
    $ts = $null
    $score = $null
    $tox = $null
    $sent = $null
    [datetime]::TryParse($r.timestamp, [ref]$ts)    | Out-Null
    [double]  ::TryParse( ($r.RadarScore  -replace ',','.'), [ref]$score) | Out-Null
    [double]  ::TryParse( ($r.toxicity_score -replace ',','.'), [ref]$tox) | Out-Null
    [double]  ::TryParse( ($r.sentiment_score -replace ',','.'), [ref]$sent)| Out-Null

    [pscustomobject]@{
      id        = $r.id
      timestamp = if($ts){ $ts } else { $null }
      source    = $r.source
      author    = $r.author
      lang      = $r.lang
      type      = $r.type
      title     = $r.title
      summary   = $r.summary
      confidence= $r.confidence
      sha256    = $r.sha256
      filepath  = $r.filepath
      tags      = $r.tags
      entities  = $r.entities
      sentiment = $sent
      toxicity  = $tox
      provenance= $r.provenance
      RadarScore= $score
    }
  }

  # 3) Фільтрація за часом/мовою/порогом
  $filtered = $artifacts | Where-Object {
    $_.timestamp -ge $fromDt -and $_.timestamp -le $toDt -and
    ($Lang ? ($_.lang -eq $Lang) : $true) -and
    ($_.RadarScore -ge $MinScore)
  }

  if(-not $filtered -or $filtered.Count -eq 0){
    Write-Log "За вказаний період немає записів, що проходять фільтр." "WARN"
  }

  # 4) Сортування за RadarScore і вибір TopN
  $top = $filtered | Sort-Object RadarScore -Descending | Select-Object -First $TopN

  # 5) Агрегати
  $countAll   = $filtered.Count
  $avgScore   = if($filtered){ [Math]::Round(($filtered | Measure-Object -Property RadarScore -Average).Average, 3) } else { 0 }
  $avgToxic   = if($filtered){ [Math]::Round(($filtered | Where-Object { $_.toxicity -ne $null } | Measure-Object -Property toxicity -Average).Average, 3) } else { 0 }
  $bySource   = $filtered | Group-Object source | Sort-Object Count -Descending | Select-Object -First 10
  $byTag      = $filtered | ForEach-Object {
                  if($_.tags){
                    $_.tags -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                  }
                } | Group-Object | Sort-Object Count -Descending | Select-Object -First 15

  # 6) Побудова HTML
  $stamp = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
  $rangeTag = "{0}_to_{1}" -f $fromDt.ToString('yyyy-MM-dd'), $toDt.ToString('yyyy-MM-dd')
  $outFile = Join-Path $OutDir ("RadarDigest_{0}_{1}.html" -f $rangeTag, $stamp)

  $htmlHeader = @"
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="utf-8">
<title>Radar Digest $rangeTag</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body{font-family: DejaVu Sans, Arial, sans-serif; margin:16px; line-height:1.4}
  h1,h2{margin:0.2em 0}
  .meta{color:#555}
  .kpi{display:flex; gap:24px; margin:12px 0 18px}
  .kpi div{background:#f5f7fb; padding:10px 14px; border-radius:10px; box-shadow:0 1px 2px rgba(0,0,0,.06)}
  table{border-collapse:collapse; width:100%; margin-top:10px}
  th,td{border:1px solid #e3e7ef; padding:8px; vertical-align:top}
  th{background:#f0f3f9; text-align:left}
  .score{font-weight:bold}
  .badge{display:inline-block; padding:2px 6px; border-radius:6px; background:#eef3ff; margin-right:6px}
  .low{color:#0a6}
  .mid{color:#b8860b}
  .hi{color:#b00}
  .small{font-size:12px; color:#666}
  .section{margin:24px 0}
</style>
</head>
<body>
<h1>Radar Digest — $rangeTag</h1>
<div class="meta">Згенеровано: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="kpi">
  <div><b>Артефактів:</b> $countAll</div>
  <div><b>Середній RadarScore:</b> $avgScore</div>
  <div><b>Середня токсичність:</b> $avgToxic</div>
</div>
"@

  $htmlTop = @()
  $htmlTop += '<div class="section"><h2>Топ артефактів</h2>'
  $htmlTop += '<table><thead><tr><th>#</th><th>Час</th><th>Заголовок</th><th>Джерело</th><th>Автор</th><th>Теги</th><th>Score</th></tr></thead><tbody>'
  $i = 0
  foreach($a in $top){
    $i++
    $scoreClass = if($a.RadarScore -ge 0.8){'hi'} elseif($a.RadarScore -ge 0.5){'mid'} else {'low'}
    $tagsHtml = if($a.tags){
      (($a.tags -split '[,;]+' | ForEach-Object{ $_.Trim() } | Where-Object {$_}) | ForEach-Object { '<span class="badge">'+[System.Web.HttpUtility]::HtmlEncode($_)+'</span>' }) -join ' '
    } else { '' }
    $title = if([string]::IsNullOrWhiteSpace($a.title)){ '(без назви)' } else { [System.Web.HttpUtility]::HtmlEncode($a.title) }
    $sum   = if([string]::IsNullOrWhiteSpace($a.summary)){ '' } else { '<div class="small">'+[System.Web.HttpUtility]::HtmlEncode($a.summary)+'</div>' }
    $src   = [System.Web.HttpUtility]::HtmlEncode($a.source)
    $aut   = [System.Web.HttpUtility]::HtmlEncode($a.author)
    $ts    = if($a.timestamp){ $a.timestamp.ToString('yyyy-MM-dd HH:mm') } else { '' }
    $fp    = if($a.filepath){ [System.Web.HttpUtility]::HtmlEncode($a.filepath) } else { '' }
    $sha   = if($a.sha256){ $a.sha256.Substring(0,[Math]::Min(12,$a.sha256.Length)) } else { '' }

    $titleCell = if($fp){
      "<b>$title</b>$sum<div class='small'>SHA: $sha · <code>$fp</code></div>"
    } else { "<b>$title</b>$sum" }

    $htmlTop += "<tr><td>$i</td><td>$ts</td><td>$titleCell</td><td>$src</td><td>$aut</td><td>$tagsHtml</td><td class='score $scoreClass'>$($a.RadarScore)</td></tr>"
  }
  $htmlTop += '</tbody></table></div>'

  $htmlSrc = @()
  $htmlSrc += '<div class="section"><h2>Джерела (топ-10)</h2><table><thead><tr><th>Джерело</th><th>К-сть</th></tr></thead><tbody>'
  foreach($g in $bySource){
    $name = [System.Web.HttpUtility]::HtmlEncode($g.Name)
    $htmlSrc += "<tr><td>$name</td><td>$($g.Count)</td></tr>"
  }
  $htmlSrc += '</tbody></table></div>'

  $htmlTags = @()
  $htmlTags += '<div class="section"><h2>Теги (топ-15)</h2><table><thead><tr><th>Тег</th><th>К-сть</th></tr></thead><tbody>'
  foreach($g in $byTag){
    $name = [System.Web.HttpUtility]::HtmlEncode($g.Name)
    $htmlTags += "<tr><td>$name</td><td>$($g.Count)</td></tr>"
  }
  $htmlTags += '</tbody></table></div>'

  $htmlFooter = @"
</body></html>
"@

  $content = $htmlHeader + ($htmlTop -join "`n") + ($htmlSrc -join "`n") + ($htmlTags -join "`n") + $htmlFooter

  # 7) Запис (UTF-8 BOM)
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($outFile, $content, $utf8Bom)

  Write-Log "HTML збережено: $outFile"
  if($OpenWhenDone){ Invoke-Item -LiteralPath $outFile }

  # 8) Лог у C03_LOG
  $logDir = Join-Path $RepoRoot 'C03_LOG'
  Ensure-Dir $logDir
  Add-Content -Path (Join-Path $logDir 'RADAR_DIGEST_LOG.md') -Encoding UTF8 `
    ("- [{0}] Digest: {1} | Range: {2} → {3} | Count={4} | AvgScore={5}" -f `
      (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $outFile, `
      $fromDt.ToString('yyyy-MM-dd'), $toDt.ToString('yyyy-MM-dd'), $countAll, $avgScore)

  exit 0
}
catch {
  Write-Log $_.Exception.Message "ERR"
  exit 1
}
