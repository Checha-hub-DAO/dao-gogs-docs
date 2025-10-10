<#
  LightSpread-Compute.ps1
  Підрахунок LightSpread (гучність поширення джерела/тегів)
  без зовнішніх API. Працює на artifacts.csv.

  Вихід: нові колонки LightSpread, Spread_SourceCount, Spread_TagsMean
#>

[CmdletBinding()]
param(
  [string]$RepoRoot="D:\CHECHA_CORE",
  [string]$CsvPath,
  [int]$HoursWindow=24,
  [int]$DaysScope=7,
  [switch]$DryRun
)

function W([string]$m,[string]$lvl="INFO"){ $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m" }
function SplitTags([string]$s){ if([string]::IsNullOrWhiteSpace($s)){ @() } else { ($s -split '[,;|]+' | % { $_.Trim().ToLower() } | ? { $_ }) } }

try{
  if([string]::IsNullOrWhiteSpace($CsvPath)){ $CsvPath=Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
  if(!(Test-Path -LiteralPath $CsvPath)){ throw "Файл не знайдено: $CsvPath" }

  $rows = Import-Csv -LiteralPath $CsvPath
  if(-not $rows -or $rows.Count -eq 0){ throw "Порожній індекс" }

  $now=Get-Date
  $from=$now.AddDays(-[Math]::Abs($DaysScope))
  $A=@()
  foreach($r in $rows){
    $ts=$null; [datetime]::TryParse($r.timestamp,[ref]$ts)|Out-Null
    if($null -eq $ts -or $ts -lt $from){ continue }
    $A += [pscustomobject]@{timestamp=$ts; source=$r.source; tags=SplitTags $r.tags}
  }

  # Мапи лічильників за 24h
  $cut=$now.AddHours(-$HoursWindow)
  $inWin = $A | ? { $_.timestamp -ge $cut }
  $sourceCnt = @{}
  foreach($x in $inWin){ if($x.source){ $sourceCnt[$x.source]++ } }
  $tagCnt=@{}
  foreach($x in $inWin){ foreach($t in $x.tags){ if($t){ $tagCnt[$t]++ } } }

  # Медіани для нормалізації
  function Median($arr){ if(!$arr){ return 1 } $s=$arr|Sort-Object; $m=[int]($s.Count/2); if($s.Count%2){ return $s[$m] } else { return ($s[$m-1]+$s[$m])/2 } }
  $Ms=[double](Median ($sourceCnt.Values))
  $Mt=[double](Median ($tagCnt.Values))
  if($Ms -le 0){$Ms=1}; if($Mt -le 0){$Mt=1}
  W "Ms=$Ms Mt=$Mt (нормалізація)"

  # Обчислення LightSpread
  $out=@(); $updated=0
  foreach($r in $rows){
    $ts=$null; [datetime]::TryParse($r.timestamp,[ref]$ts)|Out-Null
    if($null -eq $ts){ $out += $r; continue }
    $Cs= if($r.source -and $sourceCnt.ContainsKey($r.source)){ $sourceCnt[$r.source] } else { 0 }
    $tags=SplitTags $r.tags
    $Ct= if($tags.Count -gt 0){ ($tags | % { if($tagCnt.ContainsKey($_)){ $tagCnt[$_] } else { 0 } } | Measure-Object -Average).Average } else { 0 }
    $Ls=0.6*($Cs/$Ms)+0.4*($Ct/$Mt)
    if($Ls -gt 1){ $Ls=1 }
    $r | Add-Member -NotePropertyName LightSpread -NotePropertyValue ([Math]::Round([double]$Ls,4)) -Force
    $r | Add-Member -NotePropertyName Spread_SourceCount -NotePropertyValue $Cs -Force
    $r | Add-Member -NotePropertyName Spread_TagsMean -NotePropertyValue ([Math]::Round([double]$Ct,2)) -Force
    $r | Add-Member -NotePropertyName Spread_WindowHours -NotePropertyValue $HoursWindow -Force
    $updated++
    $out+=$r
  }

  W "Оновлено: $updated рядків"

  if($DryRun){ W "DryRun: не записую CSV"; exit 0 }

  $bak="$CsvPath.bak"; Copy-Item $CsvPath $bak -Force
  $tmp=[System.IO.Path]::GetTempFileName()
  $out | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $tmp
  Move-Item $tmp $CsvPath -Force
  W "CSV оновлено: $CsvPath"

  $logDir=Join-Path $RepoRoot 'C03_LOG'; if(!(Test-Path $logDir)){ New-Item -ItemType Directory -Force -Path $logDir|Out-Null }
  Add-Content -Path (Join-Path $logDir 'RADAR_LIGHTSPREAD_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | Window={2}h | Scope={3}d | Updated={4}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$CsvPath,$HoursWindow,$DaysScope,$updated)

  exit 0
}
catch{
  W $_.Exception.Message "ERR"; exit 2
}
