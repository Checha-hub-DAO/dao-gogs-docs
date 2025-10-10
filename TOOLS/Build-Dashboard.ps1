# D:\CHECHA_CORE\TOOLS\Build-Dashboard.ps1
[CmdletBinding()]
param(
  [string]$OutPath          = "D:\CHECHA_CORE\Dashboard.md",
  [string]$ManifestPath     = "D:\CHECHA_CORE\MANIFEST.md",
  [string]$WeeklyRoot       = "D:\CHECHA_CORE\REPORTS\WEEKLY",
  [string]$ScoreCsv         = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
  [string]$C13LatestMd      = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
  [string]$ControlLogDir    = "D:\CHECHA_CORE\C03_LOG\control",
  [int]$ScoreHistory        = 3,
  [int]$ArchiveShow         = 5,
  [string]$TaskPath         = "\CHECHA\",
  [string]$LogPath          = "D:\CHECHA_CORE\C03_LOG\control\Build-Dashboard.log"
)

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l; try{$l|Tee-Object -File $LogPath -Append|Out-Null}catch{} }
Ensure-Dir (Split-Path -Parent $OutPath); Ensure-Dir (Split-Path -Parent $LogPath)

Log "START Build-Dashboard"

# ---------- 1) IntegrityScore ----------
$scoreLine = "- IntegrityScore: n/a"
$scoreTable = @()
if (Test-Path -LiteralPath $ScoreCsv) {
  try {
    $rows = Import-Csv -LiteralPath $ScoreCsv | ForEach-Object {
      $dt=$_.Date; try{$dt=[datetime]::Parse($_.Date)}catch{}
      [pscustomobject]@{ Date=$dt; Weeks=$_.WeeksChecked; Ok=$_.Ok; Score=($_.Score ?? $_.IntegrityScore); Source=$_.SourceCsv }
    } | Sort-Object Date -Descending
    if($rows){
      $last=$rows[0]
      $when = if($last.Date){ $last.Date.ToString('yyyy-MM-dd HH:mm:ss') } else { $last.Date }
      $scoreLine = ("- IntegrityScore: **{0}** (at {1})" -f $last.Score, $when)
      $scoreTable += '| Date | Score | Weeks | OK |'
      $scoreTable += '|---|---:|---:|:--:|'
      foreach($r in ($rows | Select-Object -First $ScoreHistory)){
        $d= if($r.Date){ $r.Date.ToString('yyyy-MM-dd HH:mm') } else { $r.Date }
        $ok= if("$($r.Ok)" -match '^(True|true)$'){ '✓' } else { '—' }
        $scoreTable += ("| {0} | {1} | {2} | {3} |" -f $d,$r.Score,$r.Weeks,$ok)
      }
    }
  } catch { Log "[WARN] Score parse: $($_.Exception.Message)" }
} else { Log "[INFO] Score CSV not found: $ScoreCsv" }

# ---------- 2) C13 snapshot ----------
$c13Block = @("_C13: n/a_")
if(Test-Path -LiteralPath $C13LatestMd){
  try{
    $raw = Get-Content -LiteralPath $C13LatestMd
    $summaryIdx = ($raw | Select-String -Pattern '^\s*##\s*Summary' -SimpleMatch).LineNumber
    if($summaryIdx){
      $slice = $raw[($summaryIdx-1) .. ([math]::Min($raw.Length-1, $summaryIdx-1 + 8))]
      $bul = $slice | Where-Object { $_ -match '^\s*- ' -or $_ -match '^## ' }
      if($bul){ $c13Block = $bul }
    } else {
      $c13Block = ($raw | Where-Object { $_ -match '^\s*- ' } | Select-Object -First 6)
      if(-not $c13Block){ $c13Block = @("_C13 summary not found_") }
    }
  } catch { Log "[WARN] C13 read: $($_.Exception.Message)" }
}

# ---------- 3) Archive (latest) ----------
$year = (Get-Date).ToString('yyyy')
$archiveDir = Join-Path $WeeklyRoot ("ARCHIVE\{0}" -f $year)
$archLines = @("- (нема файлів за $year)")
if(Test-Path -LiteralPath $archiveDir){
  $zips = Get-ChildItem -LiteralPath $archiveDir -File -Filter *.zip -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First $ArchiveShow
  if($zips){
    $archLines = @()
    foreach($z in $zips){
      $sha = "$($z.FullName).sha256"
      $shaTag = (Test-Path -LiteralPath $sha) ? " | sha256: $(Split-Path $sha -Leaf)" : " | sha256: —"
      $archLines += ("- {0} ({1:yyyy-MM-dd HH:mm}){2}" -f (Split-Path $z.FullName -Leaf), $z.LastWriteTime, $shaTag)
    }
  }
}

# ---------- 4) Scheduler status ----------
$sched = @("| Name | State | LastRun | LastResult | NextRun | Note |"; "|---|---|---|---:|---|:--:|")
try{
  $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop
  foreach($t in ($tasks | Sort-Object TaskName)){
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $TaskPath
    $last = if($info.LastRunTime){ $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { '—' }
    $next = if($info.NextRunTime){ $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { '—' }
    $res  = $info.LastTaskResult
    $note = if($res -ne 0 -or -not $info.NextRunTime){ '⚠️' } else { '✅' }
    $sched += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $t.TaskName,$t.State,$last,$res,$next,$note)
  }
} catch { $sched = @("_No tasks under `\CHECHA\`_"); Log "[WARN] Scheduler: $($_.Exception.Message)" }

# ---------- 5) Last ControlSummary ----------
$lastSummary = "-"
if(Test-Path -LiteralPath $ControlLogDir){
  $mds = Get-ChildItem -LiteralPath $ControlLogDir -Filter "ControlSummary_*.md" -File |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($mds){ $lastSummary = (Resolve-Path $mds.FullName).Path }
}

# ---------- 6) Build Dashboard.md ----------
$md = @()
$md += "# CheCha — Dashboard"
$md += ""
$md += "**Updated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$md += ""
$md += "## Metrics"
$md += $scoreLine
if($scoreTable){ $md += ""; $md += $scoreTable }
$md += ""
$md += "## C13 — Learning Feedback (snapshot)"
$md += $c13Block
$md += ""
$md += "## Archive (latest $ArchiveShow)"
$md += $archLines
$md += ""
$md += "## Scheduler Status"
$md += $sched
$md += ""
$md += "## Links"
$md += ("- MANIFEST: `{0}`" -f $ManifestPath)
$md += ("- Last ControlSummary: `{0}`" -f $lastSummary)

$mdText = ($md -join "`r`n")
$mdText | Set-Content -LiteralPath $OutPath -Encoding UTF8
Log "[OK] Wrote: $OutPath"

# ---------- 7) Optional: hash dashboard ----------
try{
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath
  "{0}  {1}" -f $h.Hash,(Split-Path $OutPath -Leaf) | Set-Content -LiteralPath "$OutPath.sha256" -Encoding ASCII
  Log ("[OK] SHA256: {0}.sha256" -f $OutPath)
} catch { Log "[WARN] Hash Dashboard: $($_.Exception.Message)" }

Log "END Build-Dashboard"
