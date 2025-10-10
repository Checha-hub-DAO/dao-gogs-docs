<#
  Radar-ScoreRecalc.ps1
  Перерахунок RadarScore з урахуванням LightSpread і LightNovelty.
  - Бере найкраще зі стовпців: Trust/SourceTrust, Toxicity/toxicity_score, Spread/LightSpread, Novelty/LightNovelty, Relevance
  - Параметризовані ваги; клемп до [0;1]
  - .bak копія, лог у C03_LOG\RADAR_SCORE_LOG.md

  Рекомендований порядок у пайплайні:
    1) RADAR-IndexRepair_Run.ps1
    2) RADAR-SourceTrust_Apply.ps1
    3) RADAR-TagMap_Apply.ps1 -WriteRelevance
    4) LightSpread-Compute.ps1
    5) LightNovelty-Compute.ps1
    6) Radar-ScoreRecalc.ps1  ← (цей крок)
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,

  # Ваги (можна підкрутити під профіль "якість/ризик")
  [double]$WTrust        = 0.30,   # Trust або SourceTrust
  [double]$WSpread       = 0.10,   # класичний Spread (якщо є)
  [double]$WLightSpread  = 0.15,   # нова метрика LightSpread
  [double]$WNovelty      = 0.15,   # класична Novelty (якщо є)
  [double]$WLightNovelty = 0.15,   # нова метрика LightNovelty
  [double]$WRelevance    = 0.10,   # Relevance (із GModule/TagMap)
  [double]$WToxicity     = 0.15,   # віднімається

  # Налаштування
  [switch]$Clamp01,                # cтрого обрізати результат до [0;1] (рекомендовано)
  [switch]$DryRun                  # лише підрахувати/вивести статистику, без перезапису CSV
)

function Write-Log($msg, $lvl="INFO"){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$lvl] $ts $msg"
}
function TryNum([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return $null }
  $s2 = $s -replace ',','.'
  $n = 0.0
  if([double]::TryParse($s2, [ref]$n)){ return $n } else { return $null }
}
function Clamp01f([double]$x){
  if($x -lt 0){ return 0.0 }
  if($x -gt 1){ return 1.0 }
  return $x
}
function Prefer($r, [string[]]$names){
  foreach($n in $names){
    if($r.PSObject.Properties.Name -contains $n){
      $v = TryNum $r.$n
      if($v -ne $null){ return $v }
    }
  }
  return $null
}

try{
  if([string]::IsNullOrWhiteSpace($CsvPath)){
    $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv'
  }
  if(!(Test-Path -LiteralPath $CsvPath)){ throw "CSV не знайдено: $CsvPath" }

  $rows = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){ throw "Порожній CSV: $CsvPath" }

  $changed = 0
  $total   = $rows.Count

  $out = foreach($r in $rows){

    # 1) Збір ознак з пріоритетами
    # Trust: SourceTrust > Trust
    $trust   = Prefer $r @('SourceTrust','Trust')
    if($trust -eq $null){ $trust = 0.0 }

    # Spread: LightSpread (новий канал) має власну вагу; Spread (legacy) — окремо
    $spread_legacy = Prefer $r @('Spread')
    if($spread_legacy -eq $null){ $spread_legacy = 0.0 }

    $lightSpread   = Prefer $r @('LightSpread')
    if($lightSpread -eq $null){ $lightSpread = 0.0 }

    # Novelty: LightNovelty (новий канал) + Novelty (legacy, якщо є)
    $novelty_legacy = Prefer $r @('Novelty')
    if($novelty_legacy -eq $null){ $novelty_legacy = 0.0 }

    $lightNovelty   = Prefer $r @('LightNovelty')
    if($lightNovelty -eq $null){ $lightNovelty = 0.0 }

    # Relevance
    $relevance = Prefer $r @('Relevance')
    if($relevance -eq $null){ $relevance = 0.0 }

    # Toxicity
    $toxicity = Prefer $r @('toxicity_score','Toxicity')
    if($toxicity -eq $null){ $toxicity = 0.0 }

    # 2) Зважена сума
    $score = 0.0
    $score += $WTrust        * $trust
    $score += $WSpread       * $spread_legacy
    $score += $WLightSpread  * $lightSpread
    $score += $WNovelty      * $novelty_legacy
    $score += $WLightNovelty * $lightNovelty
    $score += $WRelevance    * $relevance
    $score -= $WToxicity     * $toxicity

    if($Clamp01){ $score = Clamp01f([double]$score) }

    # 3) Оновити/дописати RadarScore і дисагрегати (для аудиту)
    $prev = TryNum $r.RadarScore
    if($prev -eq $null -or [Math]::Abs($prev - $score) -gt 1e-9){ $changed++ }

    $r | Add-Member -NotePropertyName RadarScore          -NotePropertyValue ([Math]::Round([double]$score, 6)) -Force
    $r | Add-Member -NotePropertyName Score_Factors       -NotePropertyValue ('trust,spread_legacy,lightSpread,novelty_legacy,lightNovelty,relevance,toxicity') -Force
    $r | Add-Member -NotePropertyName Score_Weights       -NotePropertyValue ("$WTrust,$WSpread,$WLightSpread,$WNovelty,$WLightNovelty,$WRelevance,-$WToxicity") -Force
    $r | Add-Member -NotePropertyName Score_FeatureVector -NotePropertyValue ("{0},{1},{2},{3},{4},{5},{6}" -f `
        ([Math]::Round($trust,4)),
        ([Math]::Round($spread_legacy,4)),
        ([Math]::Round($lightSpread,4)),
        ([Math]::Round($novelty_legacy,4)),
        ([Math]::Round($lightNovelty,4)),
        ([Math]::Round($relevance,4)),
        ([Math]::Round($toxicity,4))) -Force

    $r
  }

  Write-Log ("Рядків: {0}; змінено/додано RadarScore: {1}" -f $total, $changed)

  if($DryRun){
    Write-Log "DryRun: CSV не перезаписано"
    exit 0
  }

  # 4) Запис оновленого CSV (UTF-8 без BOM)
  $bak = "$CsvPath.bak"
  Copy-Item -LiteralPath $CsvPath -Destination $bak -Force

  $header = $rows[0].PSObject.Properties.Name
  foreach($need in @('RadarScore','Score_Factors','Score_Weights','Score_FeatureVector')){
    if($header -notcontains $need){ $header += $need }
  }

  $tmp = [System.IO.Path]::GetTempFileName()
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine(($header -join ','))

  foreach($r in $out){
    $vals = foreach($h in $header){
      $v = $r.$h
      if($null -eq $v){ "" }
      else {
        $s = [string]$v
        if($s -match '[,"\r\n]'){ '"' + ($s -replace '"','""') + '"' } else { $s }
      }
    }
    [void]$sb.AppendLine(($vals -join ','))
  }
  [System.IO.File]::WriteAllText($tmp, $sb.ToString(), $utf8)
  Move-Item -LiteralPath $tmp -Destination $CsvPath -Force

  # 5) Лог
  $logDir = Join-Path $RepoRoot 'C03_LOG'
  if(!(Test-Path -LiteralPath $logDir)){ New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
  Add-Content -Path (Join-Path $logDir 'RADAR_SCORE_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Rows={2} | Changed={3} | Weights=Trust:{4},Spread:{5},LightSpread:{6},Novelty:{7},LightNovelty:{8},Relevance:{9},Toxicity:{10} | Clamp01={11}" -f `
      (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
      $CsvPath, $total, $changed,
      $WTrust, $WSpread, $WLightSpread, $WNovelty, $WLightNovelty, $WRelevance, $WToxicity, $Clamp01.IsPresent)

  Write-Log "CSV оновлено: $CsvPath"
  exit 0
}
catch{
  Write-Log $_.Exception.Message "ERR"
  exit 2
}
