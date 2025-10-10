<# 
  RADAR-Pipeline_Run.ps1
  Оркестратор щоденного/щотижневого прогону: Recalc → Digest → Trends

  Послідовність:
    1) Перерахунок RadarScore у artifacts.csv
    2) Генерація HTML-дайджесту (за вікно From..To)
    3) Побудова трендів (daily CSV + HTML-огляд)

  Політика помилок:
    - Будь-який крок логиться. Якщо крок впав — pipeline продовжує, 
      але повертає підсумковий exit code = 1 (warning) або 2 (hard fail).
    - Якщо відсутній artifacts.csv — негайний hard fail (exit 2).

  Логи:
    D:\CHECHA_CORE\C03_LOG\RADAR_PIPELINE_LOG.md

  Запуск:
    pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CHECHA_CORE\RADAR\tools\RADAR-Pipeline_Run.ps1 `
      -RepoRoot D:\CHECHA_CORE -DaysBack 7 -Lang uk -TopN 30 -MinScore 0.2 -OpenDigest
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$CsvPath,                 # якщо пусто → <RepoRoot>\RADAR\INDEX\artifacts.csv
  [int]$DaysBack = 7,               # вікно для Digest/Trends: від сьогодні мінус N днів
  [string]$Lang,                    # фільтр мови (необов’язковий)
  [int]$TopN = 25,                  # для Digest
  [double]$MinScore = 0.0,          # поріг для Digest
  [switch]$OpenDigest,              # відкрити HTML-дайджест
  [switch]$OpenTrends               # відкрити HTML-тренди
)

#region Helpers
function Write-Log($msg, $lvl="INFO"){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$lvl] $ts $msg"
}
function Ensure-Dir([string]$path){
  if(-not $path){ return }
  if(!(Test-Path -LiteralPath $path)){ New-Item -ItemType Directory -Path $path -Force | Out-Null }
}
function Run-Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )
  Write-Log ("— {0} — start" -f $Name)
  $err = $null
  $code = 0
  try{
    & $Action
    $code = $LASTEXITCODE
    if($null -eq $code){ $code = 0 }
  } catch {
    $err = $_.Exception.Message
    $code = 2
  }
  if($code -ne 0){
    $lvl = ($code -eq 2) ? "ERR" : "WARN"
    Write-Log ("{0} — exit {1}{2}" -f $Name, $code, ($err ? " | $err" : "")) $lvl
  } else {
    Write-Log ("{0} — ok" -f $Name)
  }
  return $code
}
#endregion Helpers

# 0) Шляхи та попередні перевірки
$CsvPath    = if([string]::IsNullOrWhiteSpace($CsvPath)) { Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' } else { $CsvPath }
$ToolsRoot  = Join-Path $RepoRoot 'RADAR\tools'
$ReportsDir = Join-Path $RepoRoot 'RADAR\REPORTS'
$LogDir     = Join-Path $RepoRoot 'C03_LOG'
Ensure-Dir $ReportsDir
Ensure-Dir $LogDir

$ScoreRecalc = Join-Path $ToolsRoot 'Radar-ScoreRecalc.ps1'
$Digest      = Join-Path $ToolsRoot 'Build-RadarDigest.ps1'
$Trends      = Join-Path $ToolsRoot 'Radar-Trends.ps1'

if(!(Test-Path -LiteralPath $CsvPath)){ Write-Log "Не знайдено індекс: $CsvPath" "ERR"; exit 2 }
foreach($req in @($ScoreRecalc,$Digest,$Trends)){
  if(!(Test-Path -LiteralPath $req)){ Write-Log "Не знайдено скрипт: $req" "ERR"; exit 2 }
}

# 1) Вікно часу
$now    = Get-Date
$fromDt = $now.AddDays(-[Math]::Abs($DaysBack))
$toDt   = $now
$fromS  = $fromDt.ToString('yyyy-MM-dd')
$toS    = $toDt.ToString('yyyy-MM-dd')

Write-Log ("Pipeline window: {0} → {1} (Lang='{2}', TopN={3}, MinScore={4})" -f $fromS,$toS, ($Lang?$Lang:"*"), $TopN,$MinScore)

$overallExit = 0
$details = @()

# 2) Крок 1 — перерахунок RadarScore
$code1 = Run-Step -Name "ScoreRecalc" -Action {
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File $ScoreRecalc `
    -RepoRoot $RepoRoot `
    -CsvPath   $CsvPath
}
$details += "ScoreRecalc=$code1"
if($code1 -gt $overallExit){ $overallExit = $code1 }

# 3) Крок 2 — Digest (HTML)
$code2 = Run-Step -Name "Build-Digest" -Action {
  $args = @(
    "-File", $Digest,
    "-RepoRoot", $RepoRoot,
    "-CsvPath",  $CsvPath,
    "-From",     $fromS,
    "-To",       $toS,
    "-TopN",     $TopN,
    "-MinScore", $MinScore
  )
  if($Lang){ $args += @("-Lang",$Lang) }
  if($OpenDigest){ $args += "-OpenWhenDone" }
  pwsh -NoProfile -ExecutionPolicy Bypass @args
}
$details += "Digest=$code2"
if($code2 -gt $overallExit){ $overallExit = $code2 }

# 4) Крок 3 — Trends (CSV + HTML)
$code3 = Run-Step -Name "Build-Trends" -Action {
  $args = @(
    "-File", $Trends,
    "-RepoRoot", $RepoRoot,
    "-CsvPath",  $CsvPath,
    "-From",     $fromS,
    "-To",       $toS
  )
  if($Lang){ $args += @("-Lang",$Lang) }
  if($OpenTrends){ $args += "-OpenWhenDone" }
  pwsh -NoProfile -ExecutionPolicy Bypass @args
}
$details += "Trends=$code3"
if($code3 -gt $overallExit){ $overallExit = $code3 }

# 5) Підсумок та лог
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$line = "- [$stamp] Window=$fromS→$toS | $(($details -join '; ')) | Exit=$overallExit"
Add-Content -Path (Join-Path $LogDir 'RADAR_PIPELINE_LOG.md') -Encoding UTF8 $line

if($overallExit -eq 0){
  Write-Log "PIPELINE — SUCCESS"
  exit 0
} elseif($overallExit -eq 1){
  Write-Log "PIPELINE — PARTIAL (warnings)" "WARN"
  exit 1
} else {
  Write-Log "PIPELINE — FAILED" "ERR"
  exit 2
}
