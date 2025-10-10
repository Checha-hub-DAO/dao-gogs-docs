# D:\CHECHA_CORE\TOOLS\Install-CheChaProfile.ps1
[CmdletBinding()]
param(
  [string]$CoreRoot     = "D:\CHECHA_CORE",
  [string]$ToolsDir     = "D:\CHECHA_CORE\TOOLS",
  [string]$DashPath     = "D:\CHECHA_CORE\Dashboard.md",
  [switch]$NoAutoOpen,          # не відкривати Dashboard при старті
  [switch]$NoAliases,           # не створювати аліаси/функції
  [switch]$AddToolsToModulePath # додати TOOLS в PSModulePath поточного користувача
)

function Ensure-Dir([string]$p){
  if(-not (Test-Path -LiteralPath $p)){
    New-Item -ItemType Directory -Path $p -Force | Out-Null
  }
}

function Add-Once($Path, [string]$Marker, [string]$Snippet){
  if(-not (Test-Path -LiteralPath $Path)){ New-Item -ItemType File -Path $Path -Force | Out-Null }
  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
  if($raw -notmatch [regex]::Escape($Marker)){
    Add-Content -LiteralPath $Path -Value "`r`n# $Marker`r`n$Snippet`r`n"
    return $true
  }
  return $false
}

function Write-IfMissing([string]$path, [string]$content, [string]$name){
  if(Test-Path -LiteralPath $path){
    Write-Host "[SKIP] $name існує: $path"
  } else {
    Ensure-Dir (Split-Path -Parent $path)
    $content | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "[OK] Створено $name: $path"
  }
}

Write-Host "[CHECHA] Installing profile & ensuring toolchain…"
Ensure-Dir $CoreRoot; Ensure-Dir $ToolsDir

# --- 0) Мінімальні заглушки (якщо раптом бракує) ---

$tpl_UpdateMetrics = @'
[CmdletBinding()]
param(
  [string]$ManifestPath = "D:\CHECHA_CORE\MANIFEST.md",
  [string]$ScoreCsv     = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
  [string]$C13LatestMd  = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
  [int]$ScoreHistory    = 3,
  [int]$C13Lines        = 6,
  [string]$LogPath      = "D:\CHECHA_CORE\C03_LOG\control\Update-MANIFEST-Metrics.log"
)
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l | Tee-Object -File $LogPath -Append }
$score='- IntegrityScore: n/a'
if(Test-Path $ScoreCsv){ try{ $r=Import-Csv $ScoreCsv|Sort-Object Date -Descending|Select-Object -First 1; if($r){ $score=("- IntegrityScore: **{0}** (at {1})" -f $r.Score,$r.Date) } }catch{} }
$blk=@("<!-- BEGIN METRICS -->","## Metrics",$score,"<!-- END METRICS -->") -join "`r`n"
$content = if(Test-Path $ManifestPath){ Get-Content $ManifestPath -Raw } else { "# MANIFEST`r`n" }
if($content -match '<!-- BEGIN METRICS -->.*?<!-- END METRICS -->'s){
  $updated=[regex]::Replace($content,'<!-- BEGIN METRICS -->.*?<!-- END METRICS -->',$blk,'Singleline')
}else{ $updated=$content.TrimEnd()+"`r`n`r`n$blk`r`n" }
$updated | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
Log "Metrics updated."
'@

$tpl_UpdatePaths = @'
[CmdletBinding()]
param(
  [string]$ManifestPath="D:\CHECHA_CORE\MANIFEST.md",
  [string]$WeeklyRoot  ="D:\CHECHA_CORE\REPORTS\WEEKLY",
  [int]$ShowLatestArchives=5,
  [string]$LogPath="D:\CHECHA_CORE\C03_LOG\control\Update-MANIFEST-SystemPaths.log"
)
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l | Tee-Object -File $LogPath -Append }
$yr=Get-Date -Format 'yyyy'
$dir=Join-Path $WeeklyRoot ("ARCHIVE\$yr")
$lines=@()
if(Test-Path $dir){
  $z=Get-ChildItem $dir -File -Filter *.zip | Sort-Object LastWriteTime -Descending | Select-Object -First $ShowLatestArchives
  foreach($f in $z){ $s="$($f.FullName).sha256"; $tag=(Test-Path $s)?" | sha256: $(Split-Path $s -Leaf)":" | sha256: —"; $lines+=("- {0} ({1:yyyy-MM-dd HH:mm}){2}" -f (Split-Path $f -Leaf),$f.LastWriteTime,$tag) }
}else{ $lines+= "- (нема файлів за $yr)" }
$sec=@("<!-- BEGIN SYSTEM PATHS -->","## System Paths","- Reports: `REPORTS\WEEKLY\<YYYY>\*`","- Archives: `REPORTS\WEEKLY\ARCHIVE\<YYYY>\*.zip` + `*.zip.sha256`","",
"### Archive (latest $ShowLatestArchives)") + $lines + "<!-- END SYSTEM PATHS -->"
$blk=($sec -join "`r`n")
$body = if(Test-Path $ManifestPath){ Get-Content $ManifestPath -Raw } else { "# MANIFEST`r`n" }
if($body -match '<!-- BEGIN SYSTEM PATHS -->.*?<!-- END SYSTEM PATHS -->'s){
  $out=[regex]::Replace($body,'<!-- BEGIN SYSTEM PATHS -->.*?<!-- END SYSTEM PATHS -->',$blk,'Singleline')
}else{ $out=$body.TrimEnd()+"`r`n`r`n$blk`r`n" }
$out | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
Log "System Paths updated."
'@

$tpl_UpdateSched = @'
[CmdletBinding()]
param(
  [string]$ManifestPath="D:\CHECHA_CORE\MANIFEST.md",
  [string]$TaskPath="\CHECHA\",
  [int]$MaxRows=12,
  [string]$LogPath="D:\CHECHA_CORE\C03_LOG\control\Update-MANIFEST-Scheduler.log"
)
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l | Tee-Object -File $LogPath -Append }
$rows=@()
try{
  $t=Get-ScheduledTask -TaskPath $TaskPath
  foreach($x in $t){ $i=Get-ScheduledTaskInfo -TaskName $x.TaskName -TaskPath $TaskPath
    $rows+=[pscustomobject]@{Name=$x.TaskName;State=$x.State;Last=if($i.LastRunTime){$i.LastRunTime.ToString('yyyy-MM-dd HH:mm')}else{'—'}
      ;Res=$i.LastTaskResult;Next=if($i.NextRunTime){$i.NextRunTime.ToString('yyyy-MM-dd HH:mm')}else{'—'}
      ;Note= if($i.LastTaskResult -ne 0 -or -not $i.NextRunTime){'⚠️'}else{'✅'} } }
}catch{}
$rows=$rows|Sort-Object Name|Select-Object -First $MaxRows
$tbl=@("| Name | State | LastRun | LastResult | NextRun | Note |","|---|---|---|---:|---|:--:|")
foreach($r in $rows){ $tbl+=("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $r.Name,$r.State,$r.Last,$r.Res,$r.Next,$r.Note) }
$blk=@("<!-- BEGIN SCHEDULER -->","## Scheduler Status","") + ($tbl.Count?$tbl:@("_No tasks under `\CHECHA\`_")) + "<!-- END SCHEDULER -->"
$body = if(Test-Path $ManifestPath){ Get-Content $ManifestPath -Raw } else { "# MANIFEST`r`n" }
if($body -match '<!-- BEGIN SCHEDULER -->.*?<!-- END SCHEDULER -->'s){
  $out=[regex]::Replace($body,'<!-- BEGIN SCHEDULER -->.*?<!-- END SCHEDULER -->',($blk -join "`r`n"),'Singleline')
}else{ $out=$body.TrimEnd()+"`r`n`r`n"+($blk -join "`r`n")+"`r`n" }
$out | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
Log "Scheduler updated."
'@

$tpl_BuildManifest = @'
[CmdletBinding()]
param(
  [string]$ManifestPath="D:\CHECHA_CORE\MANIFEST.md",
  [string]$WeeklyRoot  ="D:\CHECHA_CORE\REPORTS\WEEKLY",
  [string]$ScoreCsv    ="D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
  [string]$C13LatestMd ="D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
  [int]$ScoreHistory=3,[int]$C13Lines=6,[int]$ShowLatestArchives=5,
  [switch]$NoHash,[string]$LogPath="D:\CHECHA_CORE\C03_LOG\control\Build-MANIFEST.log"
)
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l | Tee-Object -File $LogPath -Append }
$u1="D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Metrics.ps1"
$u2="D:\CHECHA_CORE\TOOLS\Update-MANIFEST-SystemPaths.ps1"
$u3="D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Scheduler.ps1"
if(-not (Test-Path $ManifestPath)){ "# MANIFEST`r`n" | Set-Content $ManifestPath -Encoding UTF8; Log "[NEW] Created MANIFEST.md" }
if(Test-Path $u1){ pwsh -NoProfile -ExecutionPolicy Bypass -File $u1 -ManifestPath $ManifestPath -ScoreCsv $ScoreCsv -C13LatestMd $C13LatestMd -ScoreHistory $ScoreHistory -C13Lines $C13Lines -LogPath (Join-Path (Split-Path $LogPath -Parent) "Update-MANIFEST-Metrics.log") }
if(Test-Path $u2){ pwsh -NoProfile -ExecutionPolicy Bypass -File $u2 -ManifestPath $ManifestPath -WeeklyRoot $WeeklyRoot -ShowLatestArchives $ShowLatestArchives -LogPath (Join-Path (Split-Path $LogPath -Parent) "Update-MANIFEST-SystemPaths.log") }
if(Test-Path $u3){ pwsh -NoProfile -ExecutionPolicy Bypass -File $u3 -ManifestPath $ManifestPath -TaskPath "\CHECHA\" -MaxRows 12 -LogPath (Join-Path (Split-Path $LogPath -Parent) "Update-MANIFEST-Scheduler.log") }
if(-not $NoHash -and (Test-Path $ManifestPath)){ $h=Get-FileHash -Algorithm SHA256 -LiteralPath $ManifestPath; "{0}  {1}" -f $h.Hash,(Split-Path $ManifestPath -Leaf) | Set-Content "$ManifestPath.sha256" -Encoding ASCII; Log "[OK] SHA256 created." }
Log "END Build-MANIFEST"
'@

$tpl_BuildDash = @'
[CmdletBinding()]
param(
  [string]$OutPath      ="D:\CHECHA_CORE\Dashboard.md",
  [string]$ManifestPath ="D:\CHECHA_CORE\MANIFEST.md",
  [string]$WeeklyRoot   ="D:\CHECHA_CORE\REPORTS\WEEKLY",
  [string]$ScoreCsv     ="D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
  [string]$C13LatestMd  ="D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
  [string]$ControlLogDir="D:\CHECHA_CORE\C03_LOG\control",
  [int]$ScoreHistory=3,[int]$ArchiveShow=5,
  [string]$TaskPath="\CHECHA\",
  [string]$LogPath="D:\CHECHA_CORE\C03_LOG\control\Build-Dashboard.log"
)
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l | Tee-Object -File $LogPath -Append }
$updated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$md=@("# CheCha — Dashboard","","**Updated:** $updated","","## Links","- MANIFEST: `$ManifestPath`")
$md -join "`r`n" | Set-Content -LiteralPath $OutPath -Encoding UTF8
try{ $h=Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath; "{0}  {1}" -f $h.Hash,(Split-Path $OutPath -Leaf) | Set-Content "$OutPath.sha256" -Encoding ASCII }catch{}
Log "END Build-Dashboard"
'@

# файли-цілі
$paths = @{
  "Update-MANIFEST-Metrics.ps1"    = $tpl_UpdateMetrics
  "Update-MANIFEST-SystemPaths.ps1"= $tpl_UpdatePaths
  "Update-MANIFEST-Scheduler.ps1"  = $tpl_UpdateSched
  "Build-MANIFEST.ps1"             = $tpl_BuildManifest
  "Build-Dashboard.ps1"            = $tpl_BuildDash
}

foreach($k in $paths.Keys){
  Write-IfMissing -path (Join-Path $ToolsDir $k) -content $paths[$k] -name $k
}

# --- 1) Профіль: автівка Dashboard (один раз за сесію) ---
$profilePath = $PROFILE
if(-not $NoAutoOpen){
  $marker1 = "CheCha: auto-open dashboard"
  $snippet1 = @"
`$dash = "$DashPath"
try {
  if (Test-Path -LiteralPath `$dash) {
    if (-not (Get-Variable -Name CheChaDashOpened -Scope Global -ErrorAction SilentlyContinue)) {
      `$global:CheChaDashOpened = `$true
      Start-Process -FilePath `$dash
    }
  }
} catch {}
"@
  if(Add-Once -Path $profilePath -Marker $marker1 -Snippet $snippet1){ Write-Host "[OK] Auto-open dashboard added" } else { Write-Host "[OK] Auto-open dashboard already present" }
}

# --- 2) Аліаси/утиліти ---
if(-not $NoAliases){
  $marker2 = "CheCha: aliases & helpers"
  $snippet2 = @"
function Invoke-CheChaDashboard {
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\Build-Dashboard.ps1"
  if (Test-Path "$DashPath") { Invoke-Item "$DashPath" }
}
function Invoke-CheChaManifest {
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\Build-MANIFEST.ps1"
  if (Test-Path "$CoreRoot\MANIFEST.md") { Invoke-Item "$CoreRoot\MANIFEST.md" }
}
Set-Alias checha-dash Invoke-CheChaDashboard -ErrorAction SilentlyContinue
Set-Alias checha-man  Invoke-CheChaManifest  -ErrorAction SilentlyContinue
"@
  if(Add-Once -Path $profilePath -Marker $marker2 -Snippet $snippet2){ Write-Host "[OK] Aliases added (checha-dash / checha-man)" } else { Write-Host "[OK] Aliases already present" }
}

# --- 3) (опц.) Tools → PSModulePath ---
if($AddToolsToModulePath){
  $marker3 = "CheCha: PSModulePath (TOOLS)"
  $snippet3 = @"
try {
  if (-not (`$env:PSModulePath -split ';' | Where-Object { `$_ -ieq "$ToolsDir" })) {
    `$env:PSModulePath = "$ToolsDir;" + `$env:PSModulePath
  }
} catch {}
"@
  if(Add-Once -Path $profilePath -Marker $marker3 -Snippet $snippet3){ Write-Host "[OK] TOOLS added to PSModulePath" } else { Write-Host "[OK] PSModulePath snippet already present" }
}

# --- 4) Перезавантажити профіль і зробити первинну збірку ---
. $profilePath
Write-Host "[CHECHA] Profile reloaded."

# первинна збірка, щоб користувач одразу бачив результат
pwsh -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\Build-MANIFEST.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\Build-Dashboard.ps1"

Write-Host "[CHECHA] Install finished."
