[CmdletBinding()]
param(
    [string]$Root = 'D:\\CHECHA_CORE',
    [int]$Hour = 21,
    [int]$Minute = 0
)


$ErrorActionPreference = 'Stop'
$TaskName = '\\Checha\\Cleanup-C11-Tools-Weekly'
$Pwsh = 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
$Script = Join-Path $Root 'C11\\tools\\Cleanup-C11-Tools.ps1'


if (-not (Test-Path $Pwsh)) { throw "Не знайдено PowerShell 7: $Pwsh" }
if (-not (Test-Path $Script)) { throw "Не знайдено Cleanup-скрипт: $Script" }


$time = "{0:D2}:{1:D2}" -f $Hour, $Minute
$Args = "-NoProfile -ExecutionPolicy Bypass -File `"$Script`" -Root `"$Root`""


try { schtasks /Delete /TN $TaskName /F | Out-Null } catch {}


$create = @(
    '/Create', '/SC', 'WEEKLY', '/D', 'SUN',
    '/TN', $TaskName,
    '/TR', '"' + $Pwsh + ' ' + $Args + '"',
    '/ST', $time,
    '/RL', 'LIMITED', '/F'
)


$s = Start-Process -FilePath schtasks.exe -ArgumentList $create -Wait -PassThru
if ($s.ExitCode -ne 0) { throw "Помилка створення задачі, exit=$($s.ExitCode)" }


Write-Host "✅ Зареєстровано: $TaskName (щонеділі о $time)" -ForegroundColor Green
schtasks /Query /TN $TaskName /V /FO LIST | Out-Host

