function Alert-Enable { schtasks /Change /TN "\CheCha_Alert_15m" /Enable  | Out-Null }
function Alert-Disable{ schtasks /Change /TN "\CheCha_Alert_15m" /Disable | Out-Null }
function Alert-Status { schtasks /Query /TN "\CheCha_Alert_15m" /V /FO LIST }
function Show-AlertNext {
  param([string]$StateFile="D:\CHECHA_CORE\C07_ANALYTICS\.alert_state.json",[int]$Minutes=30)
  $j = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
  $last = [datetime]::ParseExact($j.lastTs,'yyyy-MM-dd HH:mm:ss',$null)
  $next = $last.AddMinutes($Minutes)
  [pscustomobject]@{
    lastOverall=$j.lastOverall; lastTs=$last; nextAllowed=$next; now=(Get-Date)
    remaining = if($next -gt (Get-Date)) { [timespan]($next-(Get-Date)) } else { [timespan]::Zero }
  } | Format-List
}
