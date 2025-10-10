<#!
.SYNOPSIS
  Надійна реєстрація задачі Windows Scheduler: послідовно запускає Cleanup-C11-Tools.ps1, далі Check-C11-ToolsHealth.ps1.
.DESCRIPTION
  Акуратне формування /TR з правильними лапками. Коректна перевірка exit-коду. Детальна діагностика у разі помилки.
.NOTES
  Потребує PowerShell 7 і права на створення задач. Типово — НД 21:00, Europe/Kyiv.
#>
[CmdletBinding()]
Param(
  [string]$Root = 'D:\\CHECHA_CORE',
  [ValidateSet('MON','TUE','WED','THU','FRI','SAT','SUN')]
  [string]$Day = 'SUN',
  [int]$Hour = 21,
  [int]$Minute = 0
)

$ErrorActionPreference = 'Stop'

$TaskName = "\\Checha\\Cleanup-C11-Tools-Weekly"
$Pwsh     = 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
$Cleanup  = Join-Path $Root 'C11\\tools\\Cleanup-C11-Tools.ps1'
$Health   = Join-Path $Root 'C11\\tools\\Check-C11-ToolsHealth.ps1'

if(-not (Test-Path $Pwsh))   { throw "Не знайдено PowerShell 7: $Pwsh" }
if(-not (Test-Path $Cleanup)){ throw "Не знайдено Cleanup-скрипт: $Cleanup" }
if(-not (Test-Path $Health)) { throw "Не знайдено Health-скрипт: $Health" }

# Формуємо /TR — весь аргумент у ОДНОМУ рядку з внутрішніми лапками
$cmdBody = "& '{0}' -Root '{2}'; & '{1}' -Root '{2}'" -f $Cleanup, $Health, $Root
$tr = ('"{0}" -NoProfile -ExecutionPolicy Bypass -Command "{1}"' -f $Pwsh, $cmdBody)

$time = ('{0:D2}:{1:D2}' -f $Hour,$Minute)

# Прибирання попередньої задачі
try { schtasks /Delete /TN $TaskName /F | Out-Null } catch {}

# Створення нової задачі
$create = @(
  '/Create','/SC','WEEKLY','/D',$Day,
  '/TN',$TaskName,
  '/TR',$tr,
  '/ST',$time,
  '/RL','LIMITED','/F'
)

Write-Host ('schtasks ' + ($create -join ' ')) -ForegroundColor DarkCyan
$s = Start-Process -FilePath schtasks.exe -ArgumentList $create -Wait -PassThru

if ($s.ExitCode -ne 0) {
  Write-Host "❌ Помилка створення (exit=$($s.ExitCode)). Деталізую через cmd…" -ForegroundColor Red
  & cmd.exe /c ("schtasks " + ($create -join ' '))
  throw "Помилка створення задачі, exit=$($s.ExitCode)"
}

Write-Host ("✅ Зареєстровано: {0} ({1} {2})" -f $TaskName, $Day, $time) -ForegroundColor Green

# Перевірка
schtasks /Query /TN $TaskName /V /FO LIST | Out-Host
