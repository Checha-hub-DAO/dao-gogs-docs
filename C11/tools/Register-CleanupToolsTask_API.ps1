<#!
.SYNOPSIS
  Реєстрація задачі через PowerShell API (без лапок у schtasks). Запускає Cleanup-c11-tools.ps1 і Check-C11-ToolsHealth.ps1.
.DESCRIPTION
  Більш надійний спосіб: New-ScheduledTaskAction/Trigger/SettingsSet.
#>
[CmdletBinding()]
Param(
  [string]$Root = 'D:\CHECHA_CORE',
  [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
  [string]$DayOfWeek = 'Sunday',
  [int]$Hour = 21,
  [int]$Minute = 0
)

$ErrorActionPreference = 'Stop'
$taskPath = '\Checha\'
$taskName = 'Cleanup-C11-Tools-Weekly'
$pwsh     = 'C:\Program Files\PowerShell\7\pwsh.exe'
$cleanup  = Join-Path $Root 'C11\tools\Cleanup-c11-tools.ps1'
$health   = Join-Path $Root 'C11\tools\Check-C11-ToolsHealth.ps1'

if(-not (Test-Path $pwsh))   { throw "Не знайдено PowerShell 7: $pwsh" }
if(-not (Test-Path $cleanup)){ throw "Не знайдено Cleanup-скрипт: $cleanup" }
if(-not (Test-Path $health)) { throw "Не знайдено Health-скрипт: $health" }

$scriptBlock = "& '$cleanup' -Root '$Root'; & '$health' -Root '$Root'"
$act = New-ScheduledTaskAction -Execute $pwsh -Argument ("-NoProfile -ExecutionPolicy Bypass -Command `"$scriptBlock`"")
$trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At ([datetime]::Today.Date.AddHours($Hour).AddMinutes($Minute).TimeOfDay)
$set = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries

Try { Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } Catch {}
Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Action $act -Trigger $trg -Settings $set -Description 'Cleanup + Health' -Force

Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName | Get-ScheduledTaskInfo | Format-List *
