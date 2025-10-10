# Test-CheChaTasks.ps1
[CmdletBinding()]
param(
  [string]$TaskPath = "\CHECHA\",
  [string]$LogPath  = "D:\CHECHA_CORE\C03_LOG\control\Test-CheChaTasks.log"
)

function Log($msg){
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  Add-Content -LiteralPath $LogPath -Value $line
}

Log "=== START Test-CheChaTasks ==="
try {
  $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop
  if (-not $tasks) {
    Log "[WARN] No tasks found under $TaskPath"
    exit
  }

  $report = foreach ($t in $tasks) {
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $TaskPath
    [PSCustomObject]@{
      Name           = $t.TaskName
      State          = $t.State
      LastRunTime    = $info.LastRunTime
      LastResult     = $info.LastTaskResult
      NextRunTime    = $info.NextRunTime
      Warning        = if ($info.LastTaskResult -ne 0 -or -not $info.NextRunTime) { "⚠️" } else { "✅" }
    }
  }

  $report | Format-Table Name, State, LastRunTime, LastResult, NextRunTime, Warning -Auto
  $report | Export-Csv -LiteralPath ($LogPath -replace '.log$', '.csv') -NoTypeInformation -Encoding UTF8
  Log ("Saved report → {0}" -f ($LogPath -replace '.log$', '.csv'))
}
catch {
  Log "[ERROR] $($_.Exception.Message)"
}
Log "=== END Test-CheChaTasks ==="
