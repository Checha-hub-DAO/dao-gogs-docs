# D:\CHECHA_CORE\TOOLS\Build-Dashboard.ps1
# CheCha: Build Dashboard (safe strings)

[CmdletBinding()]
param(
    [string]$OutPath = "D:\CHECHA_CORE\Dashboard.md",
    [string]$ManifestPath = "D:\CHECHA_CORE\MANIFEST.md",
    [string]$WeeklyRoot = "D:\CHECHA_CORE\REPORTS\WEEKLY",
    [string]$ScoreCsv = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv",
    [string]$C13LatestMd = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md",
    [string]$ControlLogDir = "D:\CHECHA_CORE\C03_LOG\control",
    [int]   $ArchiveShow = 5,
    [string]$TaskPath = "\CHECHA\",
    [string]$LogPath = "D:\CHECHA_CORE\C03_LOG\control\Build-Dashboard.log"
)

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line | Tee-Object -FilePath $LogPath -Append
}

function Add-MdBullet {
    param([ref]$buf, [string]$text)
    $buf.Value += "- $text`n"
}

function Get-LastControlSummary([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -Filter 'ControlSummary_*.md' -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-LastIntegrityScore([string]$csv) {
    if (-not (Test-Path -LiteralPath $csv)) { return $null }
    try {
        $row = Import-Csv -LiteralPath $csv | Sort-Object { [datetime]$_.Date } -Descending | Select-Object -First 1
        if ($row) { return [pscustomobject]@{ Score = $row.Score; Date = $row.Date } }
    }
    catch {}
    $null
}

function Get-LatestArchives([string]$weeklyRoot, [int]$take) {
    $yr = Get-Date -Format 'yyyy'
    $dir = Join-Path $weeklyRoot ("ARCHIVE\{0}" -f $yr)
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $zips = Get-ChildItem -LiteralPath $dir -Filter *.zip -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First $take
    foreach ($z in $zips) {
        $sha = "$($z.FullName).sha256"
        [pscustomobject]@{
            Name = $z.Name
            Time = $z.LastWriteTime
            Sha  = (Test-Path -LiteralPath $sha) ? (Split-Path $sha -Leaf) : $null
        }
    }
}

function Read-FirstLines([string]$path, [int]$take = 10) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try { Get-Content -LiteralPath $path -TotalCount $take } catch { @() }
}

try {
    Write-Log "START Build-Dashboard"
    $md = ""

    # Header
    $md += "# CheCha — Dashboard`n`n"
    $md += ("**Updated:** {0}`n`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

    # Links
    $md += "## Links`n"
    if (Test-Path -LiteralPath $ManifestPath) {
        Add-MdBullet -buf ([ref]$md) -text ("MANIFEST: `{0}`" -f $ManifestPath)
  } else {
    Add-MdBullet -buf ([ref]$md) -text "MANIFEST: (not found)"
  }
  $md += "`n"

  # Summary
  $md += "## Summary`n"
  $lastSummary = Get-LastControlSummary -dir $ControlLogDir
  if($lastSummary){
    Add-MdBullet -buf ([ref]$md) -text ("Last ControlSummary: `{0
        }`" -f $lastSummary.Name)
}
else {
    Add-MdBullet -buf ([ref]$md) -text "Last ControlSummary: —"
}

$score = Get-LastIntegrityScore -csv $ScoreCsv
if ($score) {
    Add-MdBullet -buf ([ref]$md) -text ("Last IntegrityScore: {0} (at {1})" -f $score.Score, $score.Date)
}
else {
    Add-MdBullet -buf ([ref]$md) -text "Last IntegrityScore: n/a"
}
Add-MdBullet -buf ([ref]$md) -text ("Dashboard generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$md += "`n"

# C13 preview
$md += "## C13 Learning Feedback (preview)`n"
$c13 = Read-FirstLines -path $C13LatestMd -take 10
if ($c13.Count -gt 0) { $md += ($c13 -join "`n") + "`n" } else { $md += "_No C13 preview available._`n" }
$md += "`n"

# Archives
$md += ("## Archive (latest {0})`n" -f $ArchiveShow)
$list = @(Get-LatestArchives -weeklyRoot $WeeklyRoot -take $ArchiveShow)
if ($list.Count -gt 0) {
    foreach ($a in $list) {
        $tail = ($a.Sha) ? (" | sha256: {0}" -f $a.Sha) : " | sha256: —"
        Add-MdBullet -buf ([ref]$md) -text ("{0} ({1:yyyy-MM-dd HH:mm}){2}" -f $a.Name, $a.Time, $tail)
    }
}
else {
    Add-MdBullet -buf ([ref]$md) -text ("(no archives in {0})" -f (Join-Path $WeeklyRoot ("ARCHIVE\{0}" -f (Get-Date -Format 'yyyy'))))
}
$md += "`n"

# Scheduler
$md += "## Scheduler (\\CHECHA\\)`n"
try {
    $tasks = Get-ScheduledTask -TaskPath $TaskPath
    if ($tasks) {
        $md += "| Name | State | NextRun |`n|---|---|---|`n"
        foreach ($t in ($tasks | Sort-Object TaskName)) {
            $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $TaskPath
            $next = if ($info.NextRunTime) { $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { '—' }
            $md += ("| {0} | {1} | {2} |`n" -f $t.TaskName, $t.State, $next)
        }
    }
    else {
        $md += "_No tasks found under `\\CHECHA\\`._`n"
    }
}
catch {
    $md += ("_Scheduler read error: {0}._`n" -f $_.Exception.Message)
}
$md += "`n"

# Note
$md += "## Note`n"
$md += "> ""Знання без контролю — як світло без спрямування.`n> Контроль без етики — як тінь без суті."" — С.Ч.`n"

# Write file + sha
$outDir = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$md | Set-Content -LiteralPath $OutPath -Encoding UTF8
try {
    $h = Get-FileHash -Algorithm SHA256 -LiteralPath $OutPath
    ("{0}  {1}" -f $h.Hash, (Split-Path $OutPath -Leaf)) | Set-Content -LiteralPath "$OutPath.sha256" -Encoding ASCII
}
catch {}

Write-Log ("WROTE: {0}" -f $OutPath)
Write-Log "END Build-Dashboard"
exit 0
}
catch {
    Write-Log ("[ERR] {0}" -f $_.Exception.Message)
    exit 1
}

