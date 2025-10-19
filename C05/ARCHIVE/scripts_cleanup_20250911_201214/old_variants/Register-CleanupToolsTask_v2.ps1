<#!
.SYNOPSIS
  Реєстрація задачі Windows Scheduler: запускає Cleanup-c11-tools.ps1 і Check-C11-ToolsHealth.ps1.
.DESCRIPTION
  Створює Weekly-задачу у гілці \\Checha (типово: НД 21:00, Europe/Kyiv).
  Використовує pwsh.exe, правильне цитування /TR і перевірку exit‑коду.
.NOTES
  PowerShell 7+ і права на створення задач.
.EXAMPLE
  pwsh -NoProfile -File .\Register-CleanupToolsTask_v2.ps1 -Root 'D:\\CHECHA_CORE' -Hour 21 -Minute 10
#>
[CmdletBinding()]
param(
    [string]$Root = 'D:\\CHECHA_CORE',
    [ValidateSet('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')]
    [string]$Day = 'SUN',
    [int]$Hour = 21,
    [int]$Minute = 0
)

$ErrorActionPreference = 'Stop'

$TaskName = "\\Checha\\Cleanup-C11-Tools-Weekly"
$Pwsh = 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
$Cleanup = Join-Path $Root 'C11\\tools\\Cleanup-c11-tools.ps1'
$Health = Join-Path $Root 'C11\\tools\\Check-C11-ToolsHealth.ps1'

if (-not (Test-Path $Pwsh)) { throw "Не знайдено PowerShell 7: $Pwsh" }
if (-not (Test-Path $Cleanup)) { throw "Не знайдено Cleanup-скрипт: $Cleanup" }
if (-not (Test-Path $Health)) { throw "Не знайдено Health-скрипт: $Health" }

$time = "{0:D2}:{1:D2}" -f $Hour, $Minute

# /TR одним рядком: pwsh + -Command { Cleanup; Health }
$cmdBody = "& '{0}' -Root '{2}'; & '{1}' -Root '{2}'" -f $Cleanup, $Health, $Root
$tr = ('"{0}" -NoProfile -ExecutionPolicy Bypass -Command "{1}"' -f $Pwsh, $cmdBody)

# Видаляємо стару задачу, якщо була
try { schtasks /Delete /TN $TaskName /F | Out-Null } catch {}

# Створюємо нову
$create = @(
    '/Create', '/SC', 'WEEKLY', '/D', $Day,
    '/TN', $TaskName,
    '/TR', $tr,
    '/ST', $time,
    '/RL', 'LIMITED', '/F'
)

Write-Host ('schtasks ' + ($create -join ' ')) -ForegroundColor DarkCyan
$s = Start-Process -FilePath schtasks.exe -ArgumentList $create -Wait -PassThru

if ($s.ExitCode -ne 0) {
    Write-Host "❌ Помилка створення (exit=$($s.ExitCode))." -ForegroundColor Red
    & cmd.exe /c ("schtasks " + ($create -join ' '))
    throw "Не вдалося створити задачу: $TaskName"
}

Write-Host "✅ Зареєстровано: $TaskName ($Day $time)" -ForegroundColor Green
schtasks /Query /TN $TaskName /V /FO LIST | Out-Host


