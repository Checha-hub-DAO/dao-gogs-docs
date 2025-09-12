<#!
.SYNOPSIS
  Post-install для пакета CHECHA CORE C11\tools: розпакувати ZIP, розгорнути скрипти, зареєструвати задачу, зробити перший прогін cleanup+health.
.DESCRIPTION
  - Шукає ZIP автоматично (Downloads або поточна папка) або приймає шлях через -ZipPath
  - Розпаковує в D:\\CHECHA_CORE\\C11\\tools (або інший -Root)
  - Створює «аліас» Cleanup-C11-Tools.ps1 → Cleanup-c11-tools.ps1 для сумісності
  - Реєструє задачу (метод: API або SCHTASKS)
  - Одразу запускає Cleanup + Health і показує хвости логів
.PARAMETER Root
  Корінь CHECHA_CORE (типово D:\\CHECHA_CORE)
.PARAMETER ZipPath
  Шлях до ZIP (якщо не задано — шукаємо CHECHA_CORE_C11_tools_suite_*.zip у Downloads та поточній директорії)
.PARAMETER RegisterMethod
  'API' (рекомендовано) або 'SCHTASKS'. Типово: API
.PARAMETER DayOfWeek
  День тижня для задачі (Monday..Sunday). Типово: Sunday
.PARAMETER Hour
  Година старту. Типово: 21
.PARAMETER Minute
  Хвилина старту. Типово: 0
.PARAMETER SkipFirstRun
  Не виконувати перший прогін cleanup+health.
.EXAMPLE
  pwsh -NoProfile -File .\\PostInstall-C11Suite.ps1 -Root 'D:\\CHECHA_CORE'
.EXAMPLE
  pwsh -NoProfile -File .\\PostInstall-C11Suite.ps1 -ZipPath "$env:USERPROFILE\\Downloads\\CHECHA_CORE_C11_tools_suite_*.zip" -RegisterMethod API -DayOfWeek Sunday -Hour 21 -Minute 0
#>
[CmdletBinding()]
Param(
  [string]$Root = 'D:\\CHECHA_CORE',
  [string]$ZipPath,
  [ValidateSet('API','SCHTASKS')]
  [string]$RegisterMethod = 'API',
  [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
  [string]$DayOfWeek = 'Sunday',
  [int]$Hour = 21,
  [int]$Minute = 0,
  [switch]$SkipFirstRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-ZipPath([string]$Path){
  if($Path){
    $c = Get-ChildItem -Path $Path -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if(-not $c){ throw "ZIP не знайдено: $Path" }
    return $c.FullName
  }
  $cands = @()
  $dl = Join-Path $env:USERPROFILE 'Downloads'
  foreach($p in @($PWD.Path,$dl)){
    if(Test-Path $p){ $cands += Get-ChildItem -Path $p -Filter 'CHECHA_CORE_C11_tools_suite_*.zip' -ErrorAction SilentlyContinue }
  }
  $pick = $cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $pick){ throw "Не знайдено ZIP (CHECHA_CORE_C11_tools_suite_*.zip) у $($PWD.Path) або $dl. Задай -ZipPath." }
  return $pick.FullName
}

function Ensure-Dir([string]$Path){ if(-not (Test-Path $Path)){ New-Item -ItemType Directory -Path $Path | Out-Null } }
function Tail([string]$Path,[int]$N=30){ if(Test-Path $Path){ Get-Content -Path $Path -Tail $N } }

$tools = Join-Path $Root 'C11\\tools'
$logDir = Join-Path $Root 'C03\\LOG'
$archive = Join-Path $Root 'C05\\ARCHIVE'
Ensure-Dir $tools; Ensure-Dir $logDir; Ensure-Dir $archive

# 1) Знайти та розпакувати ZIP
$zip = Resolve-ZipPath $ZipPath
Write-Host "[PostInstall] ZIP: $zip" -ForegroundColor Cyan
Expand-Archive -Path $zip -DestinationPath $tools -Force
Get-ChildItem $tools -Filter '*.ps1' -File | Unblock-File | Out-Null

# 2) Сумісність назв: створюємо копію Cleanup-C11-Tools.ps1
$canonLower = Join-Path $tools 'Cleanup-c11-tools.ps1'
$canonUpper = Join-Path $tools 'Cleanup-C11-Tools.ps1'
if ((Test-Path $canonLower) -and -not (Test-Path $canonUpper)) { Copy-Item $canonLower $canonUpper -Force }

# 3) Реєстрація задачі
$taskPath = '\\Checha\\'
$taskName = 'Cleanup-C11-Tools-Weekly'
$pwshEXE  = 'C:\\Program Files\\PowerShell\\7\\pwsh.exe'
if(-not (Test-Path $pwshEXE)) { $pwshEXE = (Get-Command pwsh).Source }
$cleanup  = Join-Path $tools 'Cleanup-c11-tools.ps1'
$health   = Join-Path $tools 'Check-C11-ToolsHealth.ps1'

if(-not (Test-Path $cleanup)){ throw "Очікуваний файл відсутній: $cleanup" }
if(-not (Test-Path $health)) { throw "Очікуваний файл відсутній: $health" }

if($RegisterMethod -eq 'API'){
  Write-Host '[PostInstall] Реєстрація (API)...' -ForegroundColor Green
  $scriptBlock = "& '$cleanup' -Root '$Root'; & '$health' -Root '$Root'"
  $act = New-ScheduledTaskAction -Execute $pwshEXE -Argument ("-NoProfile -ExecutionPolicy Bypass -Command `"$scriptBlock`"")
  $days = [System.DayOfWeek]::$(if($DayOfWeek){$DayOfWeek}else{'Sunday'})
  $runAt = (Get-Date).Date.AddHours($Hour).AddMinutes($Minute)
  $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $runAt
  $set = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries
  try { Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
  Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Action $act -Trigger $trg -Settings $set -Description 'Cleanup + Health' -Force | Out-Null
} else {
  Write-Host '[PostInstall] Реєстрація (SCHTASKS)...' -ForegroundColor Green
  $map = @{Monday='MON';Tuesday='TUE';Wednesday='WED';Thursday='THU';Friday='FRI';Saturday='SAT';Sunday='SUN'}
  $day3 = $map[$DayOfWeek]
  $cmdBody = "& '{0}' -Root '{2}'; & '{1}' -Root '{2}'" -f $cleanup,$health,$Root
  $tr = ('"{0}" -NoProfile -ExecutionPolicy Bypass -Command "{1}"' -f $pwshEXE, $cmdBody)
  try { schtasks /Delete /TN ($taskPath + $taskName) /F | Out-Null } catch {}
  $timeStr = ('{0:D2}:{1:D2}' -f $Hour,$Minute)
  $args = @('/Create','/SC','WEEKLY','/D',$day3,'/TN',($taskPath + $taskName),'/TR',$tr,'/ST',$timeStr,'/RL','LIMITED','/F')
  $p = Start-Process -FilePath schtasks.exe -ArgumentList $args -Wait -PassThru
  if($p.ExitCode -ne 0){ & cmd.exe /c ("schtasks " + ($args -join ' ')); throw "SCHTASKS створення завершилось помилкою: exit=$($p.ExitCode)" }
}

# 4) Перший прогін (якщо не пропущено)
if(-not $SkipFirstRun){
  Write-Host '[PostInstall] Перший прогін CLEANUP...' -ForegroundColor Yellow
  & $pwshEXE -NoProfile -ExecutionPolicy Bypass -File $cleanup -Root $Root
  Write-Host '[PostInstall] Перший прогін HEALTH...' -ForegroundColor Yellow
  & $pwshEXE -NoProfile -ExecutionPolicy Bypass -File $health -Root $Root
}

# 5) Звіти
$clog = Join-Path $logDir 'cleanup_tools.log'
$hlog = Join-Path $logDir 'cleanup_health.log'
Write-Host "\n--- cleanup_tools.log (tail) ---" -ForegroundColor DarkCyan
Tail $clog 40
Write-Host "\n--- cleanup_health.log (tail) ---" -ForegroundColor DarkCyan
Tail $hlog 40

Write-Host ("\n✅ Готово. Задача: " + ($taskPath + $taskName)) -ForegroundColor Green
try { (Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName | Get-ScheduledTaskInfo) | Format-List LastRunTime,LastTaskResult,NextRunTime | Out-Host } catch {}



