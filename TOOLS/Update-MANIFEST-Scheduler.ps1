# D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Scheduler.ps1
[CmdletBinding()]
param(
  [string]$ManifestPath = "D:\CHECHA_CORE\MANIFEST.md",
  [string]$TaskPath     = "\CHECHA\",
  [int]$MaxRows         = 12,
  [string]$LogPath      = "D:\CHECHA_CORE\C03_LOG\control\Update-MANIFEST-Scheduler.log"
)

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log([string]$m){ $l="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; $l; try{$l|Tee-Object -File $LogPath -Append|Out-Null}catch{} }

Ensure-Dir (Split-Path -Parent $ManifestPath)
Ensure-Dir (Split-Path -Parent $LogPath)
Log "START Update-MANIFEST-Scheduler"
Log "Manifest=$ManifestPath; TaskPath=$TaskPath"

# 1) Зібрати статуси задач
$rows = @()
try{
  $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop
  foreach($t in $tasks){
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $TaskPath
    $last = if($info.LastRunTime){ $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { '—' }
    $next = if($info.NextRunTime){ $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { '—' }
    $res  = $info.LastTaskResult
    $note = if($res -ne 0 -or -not $info.NextRunTime){ '⚠️' } else { '✅' }

    $rows += [pscustomobject]@{
      Name        = $t.TaskName
      State       = $t.State
      LastRun     = $last
      LastResult  = $res
      NextRun     = $next
      Note        = $note
    }
  }
} catch { Log "[ERR] $($_.Exception.Message)" }

$rows = $rows | Sort-Object Name | Select-Object -First $MaxRows

# 2) Побудувати секцію
$md = @()
$md += "<!-- BEGIN SCHEDULER -->"
$md += "## Scheduler Status"
$md += ""
if($rows.Count -gt 0){
  $md += "| Name | State | LastRun | LastResult | NextRun | Note |"
  $md += "|---|---|---|---:|---|:--:|"
  foreach($r in $rows){
    $md += ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $r.Name,$r.State,$r.LastRun,$r.LastResult,$r.NextRun,$r.Note)
  }
} else {
  $md += "_No tasks found under `\CHECHA\`_"
}
$md += "<!-- END SCHEDULER -->"
$blockText = ($md -join "`r`n")

# 3) Запис у MANIFEST.md
if(-not (Test-Path -LiteralPath $ManifestPath)){
  "# MANIFEST`r`n`r`n$blockText`r`n" | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
  Log "[NEW] Created MANIFEST with Scheduler section."
} else {
  $content = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
  $regex = New-Object System.Text.RegularExpressions.Regex('<!-- BEGIN SCHEDULER -->.*?<!-- END SCHEDULER -->',[System.Text.RegularExpressions.RegexOptions]::Singleline)
  if($regex.IsMatch($content)){
    $m=$regex.Match($content)
    $updated = $content.Substring(0,$m.Index) + $blockText + $content.Substring($m.Index+$m.Length)
    Log "[OK] Scheduler section updated (replace)."
  } else {
    $updated = $content.TrimEnd() + "`r`n`r`n" + $blockText + "`r`n"
    Log "[OK] Scheduler section appended."
  }
  Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding UTF8
}
Log "END Update-MANIFEST-Scheduler"
