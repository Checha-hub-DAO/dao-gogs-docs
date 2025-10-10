param(
  [string]$CsvPath = "D:\CHECHA_CORE\C07_ANALYTICS\MAT_BALANCE.csv",
  [string]$OutPath = "D:\CHECHA_CORE\DOCS\MAT_BALANCE_Panel.md",
  [int]$Days = 7
)

$ErrorActionPreference = 'Stop'
function ParseDate($s){
  foreach($fmt in 'yyyy-MM-dd','yyyy/M/d','dd.MM.yyyy'){
    try { return [datetime]::ParseExact($s,$fmt,$null) } catch {}
  }
  try { return [datetime]$s } catch { return $null }
}

if(!(Test-Path $CsvPath)){ throw "CSV не знайдено: $CsvPath" }
$rows = Import-Csv $CsvPath
$since = (Get-Date).Date.AddDays(-($Days-1))

# Нормалізація
$norm = foreach($r in $rows){
  $d = ParseDate $r.date
  if(-not $d){ continue }
  if($d.Date -lt $since){ continue }
  $cat = ("{0}" -f $r.category).Trim()
  $h = ("{0}" -f $r.hours).Trim().Replace(',','.')
  try { $h = [double]$h } catch { $h = 0.0 }
  [pscustomobject]@{ date=$d.Date; category=$cat; hours=$h }
}

# Агреґація по днях
$byDay = @()
$dates = ($norm | Select-Object -ExpandProperty date -Unique | Sort-Object)
foreach($d in $dates){
  $slice = $norm | Where-Object date -eq $d
  $sum = $slice | Group-Object category | ForEach-Object {
    [pscustomobject]@{ Category=$_.Name; Hours=($_.Group | Measure-Object hours -Sum).Sum }
  }
  function S($n){ ($sum | Where-Object Category -eq $n | Select-Object -First 1).Hours }
  $hS = (S 'Стратегія');   if(-not $hS){ $hS=0 }
  $hT = (S 'Техніка');     if(-not $hT){ $hT=0 }
  $hH = (S 'Гібрид');      if(-not $hH){ $hH=0 }
  $hR = (S 'Відновлення'); if(-not $hR){ $hR=0 }

  $effS = $hS + ($hH*0.5)
  $effT = $hT + ($hH*0.5)
  $den  = $effS + $effT
  if($den -le 0){ $pS=0; $pT=0 } else { $pS=[math]::Round($effS/$den*100,1); $pT=[math]::Round($effT/$den*100,1) }
  $note = if($pT -gt 70 -or $pS -lt 30){ "WARN" } else { "OK" }

  $byDay += [pscustomobject]@{
    Date  = $d.ToString('yyyy-MM-dd')
    S     = [math]::Round($hS,2)
    T     = [math]::Round($hT,2)
    H     = [math]::Round($hH,2)
    R     = [math]::Round($hR,2)
    EffS  = [math]::Round($effS,2)
    EffT  = [math]::Round($effT,2)
    PctS  = $pS
    PctT  = $pT
    Note  = $note
  }
}

# Рендер у Markdown (UTF-8 без BOM)
$md = @()
$md += "# MAT_BALANCE — 7-Day Panel"
$md += ""
$md += "| Date       | S (h) | T (h) | H (h) | R (h) | EffS | EffT | S%  | T%  | Note |"
$md += "|------------|-------|-------|-------|-------|------|------|-----|-----|------|"
foreach($r in ($byDay | Sort-Object Date)){
  $md += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f `
    $r.Date,$r.S,$r.T,$r.H,$r.R,$r.EffS,$r.EffT,("{0:N1}" -f $r.PctS),("{0:N1}" -f $r.PctT),$r.Note)
}
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutPath, ($md -join [Environment]::NewLine), $Utf8)
Write-Host "[panel] MD saved: $OutPath" -ForegroundColor Cyan
