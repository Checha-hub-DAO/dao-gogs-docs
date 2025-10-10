param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$Version  = "v1.0",
  [switch]$PublishMeta
)

# ---------- helpers ----------
function Write-Text([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if(!(Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $Text | Out-File -Encoding UTF8 -FilePath $Path
}
function BoolTo([bool]$b,[string]$ok,[string]$nok){ if($b){$ok}else{$nok} }
function N01([object]$x){
  $ci=[System.Globalization.CultureInfo]::InvariantCulture
  if($null -eq $x){ return 0.0 }
  $s=([string]$x).Trim() -replace ',', '.'
  if($s -eq ''){ return 0.0 }
  try { $v=[double]::Parse($s,$ci) } catch { return 0.0 }
  if($v -gt 1){ $v=$v/100.0 }
  if($v -lt 0){ $v=0.0 } elseif($v -gt 1){ $v=1.0 }
  return $v
}
function Fmt([double]$v,[int]$d=2){ $ci=[System.Globalization.CultureInfo]::InvariantCulture; $v.ToString(("F{0}" -f $d),$ci) }
function Avg5([double]$a,[double]$b,[double]$c,[double]$d,[double]$e){
  $v = ($a+$b+$c+$d+$e)/5.0
  if($v -lt 0){$v=0}elseif($v -gt 1){$v=1}
  [math]::Round($v,3)
}

# ---------- paths ----------
$Analytics   = Join-Path $RepoRoot 'C07_ANALYTICS'
$healthTxt   = Join-Path $Analytics 'HEALTH.txt'
$statusJson  = Join-Path $Analytics 'Status.json'
$jsonLast    = Join-Path $Analytics 'Radar_Last.json'
$today       = (Get-Date).ToString('yyyy-MM-dd')

# ---------- read metrics (Dynamics -> Summary -> JSON) ----------
$last = $null
$dynCsv = Join-Path $Analytics 'Radar_Dynamics.csv'
if(Test-Path -LiteralPath $dynCsv){
  try{
    $rows = Import-Csv -LiteralPath $dynCsv
    if($rows){ $r=$rows[-1]; $last=[pscustomobject]@{
      Date=[string]$r.Date; Stability=$r.Stability; Clean=$r.Clean; Sync=$r.Sync; Edu=$r.Edu; Anal=$r.Anal; Version=$Version
    } }
  }catch{}
}
if(-not $last){
  $sum = Get-ChildItem -LiteralPath $Analytics -Filter 'CheCha_Radar_Summary_*.csv' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($sum){
    try{
      $map=@{}
      foreach($row in (Import-Csv -LiteralPath $sum.FullName)){ if($row.Metric){ $map[$row.Metric]=$row.Value } }
      $dstr = ([Regex]::Match($sum.Name,'CheCha_Radar_Summary_(\d{4}-\d{2}-\d{2})\.csv')).Groups[1].Value
      $last=[pscustomobject]@{
        Date=$dstr
        Stability=$map['SystemStability']; Clean=$map['InfoCleanliness']; Sync=$map['CommSync']; Edu=$map['EducationActivity']; Anal=$map['AnalyticIntegration']
        Version=$Version
      }
    }catch{}
  }
}
if(-not $last -and (Test-Path -LiteralPath $jsonLast)){ try{ $last=Get-Content -LiteralPath $jsonLast -Raw | ConvertFrom-Json }catch{} }
if(-not $last){ $last=[pscustomobject]@{ Date=$today; Stability=0; Clean=0; Sync=0; Edu=0; Anal=0; Version=$Version } }

# ---------- normalize + compute avg ONLY from components ----------
$stN = N01 $last.Stability
$clN = N01 $last.Clean
$syN = N01 $last.Sync
$edN = N01 $last.Edu
$anN = N01 $last.Anal
$avg = Avg5 $stN $clN $syN $edN $anN

# ---------- artifacts & overall ----------
$haveSummary = (Get-ChildItem -LiteralPath $Analytics -Filter ("CheCha_Radar_Summary_{0}.csv" -f $today) -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
$haveMd      = (Get-ChildItem -LiteralPath $Analytics -Filter ("CheCha_Radar_{0}_*.md" -f $today)      -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
$haveHtml    = (Get-ChildItem -LiteralPath $Analytics -Filter ("CheCha_Radar_{0}_*.html" -f $today)    -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
$haveSig     = (Get-ChildItem -LiteralPath $Analytics -Filter ("SIG-MATRIX_{0}.csv" -f $today)         -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
$haveDynCsv  = Test-Path -LiteralPath $dynCsv
$haveDigest  = (Get-ChildItem -LiteralPath $Analytics -Filter ("Radar_Digest_{0}.html" -f $today)      -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
$okRadar     = $haveSummary -and $haveMd -and $haveHtml -and $haveSig
$okDyn       = $haveDynCsv
$okDigest    = $haveDigest
if($okRadar -and $okDyn -and $okDigest){ $overall="OK" } elseif($okRadar -and $okDyn){ $overall="DEGRADED" } else { $overall="WARN" }

# ---------- console report ----------
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "[CHECHA_STATUS] $ts"
Write-Host ("Radar:    " + (BoolTo $okRadar  "OK" "NOT READY"))
Write-Host ("Dynamics: " + (BoolTo $okDyn    "OK" "NOT READY"))
Write-Host ("Digest:   " + (BoolTo $okDigest "OK" "NOT READY"))
Write-Host ("Last: {0}  Avg={1}  (Stab {2}, Clean {3}, Sync {4}, Edu {5}, Anal {6})" -f `
  $last.Date, (Fmt $avg 3), (Fmt $stN 2), (Fmt $clN 2), (Fmt $syN 2), (Fmt $edN 2), (Fmt $anN 2))

# ---------- HEALTH.txt ----------
$lines=@()
$lines += "[CHECHA_STATUS] $ts  Version=$Version"
$lines += "OVERALL=$overall"
$lines += "Radar="    + (BoolTo $okRadar  "OK" "NOT_READY")
$lines += "Dynamics=" + (BoolTo $okDyn    "OK" "NOT_READY")
$lines += "Digest="   + (BoolTo $okDigest "OK" "NOT_READY")
$lines += ("Last Avg={0}  Stab={1} Clean={2} Sync={3} Edu={4} Anal={5}  Date={6}" -f `
  (Fmt $avg 3),(Fmt $stN 2),(Fmt $clN 2),(Fmt $syN 2),(Fmt $edN 2),(Fmt $anN 2),$last.Date)
Write-Text $healthTxt ([string]::Join([Environment]::NewLine,$lines))

# ---------- Status.json ----------
$payload = [pscustomobject]@{
  Version   = $Version
  Timestamp = $ts
  Overall   = $overall
  Today     = $today
  Artifacts = [pscustomobject]@{
    HaveSummary=$haveSummary; HaveMd=$haveMd; HaveHtml=$haveHtml; HaveSIG=$haveSig
    HaveDynamicsCsv=$haveDynCsv; HaveRadarLast=$true; HaveDigestHtml=$haveDigest
  }
  LastMetrics = [pscustomobject]@{ Date=$last.Date; Stability=$stN; Clean=$clN; Sync=$syN; Edu=$edN; Anal=$anN; Avg=$avg; Version=$Version }
}
$payload | ConvertTo-Json -Depth 6 | Out-File -Encoding UTF8 -FilePath $statusJson

# ---------- Radar_Last.json (normalized) ----------
[pscustomobject]@{
  Date=$last.Date; Stability=$stN; Clean=$clN; Sync=$syN; Edu=$edN; Anal=$anN; Avg=$avg; Version=$Version
} | ConvertTo-Json -Depth 3 | Out-File -Encoding UTF8 -FilePath $jsonLast

# ---------- META (optional) ----------
if($PublishMeta){
  $meta="D:\CHECHA_CORE\TOOLS\Write-MetaLayerEntry.ps1"
  if(Test-Path -LiteralPath $meta){
    $obs = "Статус: Radar=" + (BoolTo $okRadar "OK" "NOK") + ", Dyn=" + (BoolTo $okDyn "OK" "NOK") + ", Digest=" + (BoolTo $okDigest "OK" "NOK")
    & $meta -Event ("CheCha_Status " + $Version) -Intent "Щоденна перевірка конвеєра" `
      -Observation $obs -Insight "HEALTH/Status/Last оновлено" -EmotionalTone "спокій" -BalanceShift 0.1 -MetaIndex $avg `
      -Tags Analytic,Tech,Balance
  }
}
