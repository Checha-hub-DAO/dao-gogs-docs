<# 
.SYNOPSIS
  Реєструє щомісячне планове завдання для автоматичного формування DAO-Academy Digest.

.PARAMETER Root
  Корінь системи CHECHA_CORE. За замовч.: D:\CHECHA_CORE

.PARAMETER TaskName
  Назва завдання у Task Scheduler. За замовч.: DAOAcademyDigest_Monthly

.PARAMETER At
  Час доби (HH:mm), коли запускати 1-го числа. За замовч.: 09:00

.PARAMETER Install
  Створити / оновити планове завдання (режим за замовчуванням).

.PARAMETER Uninstall
  Видалити планове завдання й runner-скрипт.

.PARAMETER RunNow
  Одноразово виконати генерацію дайджесту прямо зараз (для попереднього місяця).

.NOTES
  Працює з PowerShell 7+. Потрібні права користувача з доступом до Task Scheduler.
  Автор: С.Ч. / DAO-GOGS
#>

[CmdletBinding(DefaultParameterSetName='Install')]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string]$TaskName = "DAOAcademyDigest_Monthly",
  [string]$At = "09:00",
  [Parameter(ParameterSetName='Install')][switch]$Install,
  [Parameter(ParameterSetName='Uninstall')][switch]$Uninstall,
  [Parameter(ParameterSetName='RunNow')][switch]$RunNow
)

# --- Шляхи
$ToolsDir   = Join-Path $Root "TOOLS"
$ReportsDir = Join-Path $Root "C03_LOG\reports\DAO_Academy"
$AutoLogDir = Join-Path $Root "C03_LOG\automation"
$Builder    = Join-Path $ToolsDir "Build-DAOAcademyDigest.ps1"
$Runner     = Join-Path $ToolsDir "Build-DAOAcademyDigest.Runner.ps1"
$LogPath    = Join-Path $AutoLogDir "DAO_AcademyDigest.log"

# --- Перевірка оточення
if (!(Test-Path $Builder)) { throw "Не знайдено Builder: $Builder" }
if (!(Test-Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
if (!(Test-Path $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null }
if (!(Test-Path $AutoLogDir)) { New-Item -ItemType Directory -Path $AutoLogDir -Force | Out-Null }

# --- Створення runner-скрипта (завжди актуальний, викликає попередній місяць)
$runnerCode = @"
# Auto-generated runner for DAO-Academy Digest
param(
  [string]\$Root = "$Root",
  [string]\$LogPath = "$LogPath"
)
try {
  \$prevMonth = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
  \$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  if (!(Test-Path (Split-Path -Parent \$LogPath))) { New-Item -ItemType Directory -Path (Split-Path -Parent \$LogPath) -Force | Out-Null }
  "`\$ts :: START Digest for \$prevMonth" | Add-Content -LiteralPath \$LogPath
  pwsh -NoProfile -File (Join-Path \$Root 'TOOLS\Build-DAOAcademyDigest.ps1') -Root \$Root -Month \$prevMonth -Hash *>> \$LogPath
  "\$ts :: DONE  Digest for \$prevMonth" | Add-Content -LiteralPath \$LogPath
} catch {
  "\$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') :: ERROR :: \$($_.Exception.Message)" | Add-Content -LiteralPath \$LogPath
  throw
}
"@
[System.IO.File]::WriteAllText($Runner, $runnerCode, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[OK] Runner -> $Runner"

function Install-Task {
  param([string]$TimeStr = "09:00")
  # Тригер: щомісяця 1-го числа
  $t = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At ([datetime]::ParseExact($TimeStr,'HH:mm',$null))
  # Дія: запуск pwsh із runner-скриптом
  $a = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-NoProfile -File `"$Runner`""
  # Принципал: поточний користувач (без підвищення). За потреби можна задати -RunLevel Highest.
  $p = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive
  $s = New-ScheduledTask -Action $a -Trigger $t -Principal $p -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries)
  try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
      Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $TaskName -InputObject $s | Out-Null
    Write-Host "[OK] Зареєстровано завдання: $TaskName (щомісяця 1-го о $TimeStr)"
  } catch {
    throw "Помилка реєстрації завдання: $($_.Exception.Message)"
  }
}

function Uninstall-Task {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[OK] Видалено завдання: $TaskName"
  } else {
    Write-Host "[i] Завдання відсутнє: $TaskName"
  }
  if (Test-Path $Runner) {
    Remove-Item -LiteralPath $Runner -Force
    Write-Host "[OK] Видалено runner: $Runner"
  }
}

switch ($PSCmdlet.ParameterSetName) {
  'Uninstall' {
    Uninstall-Task
  }
  'RunNow' {
    # Одноразовий запуск на попередній місяць
    & pwsh -NoProfile -File $Runner
    Write-Host "[OK] Разовий запуск виконано. Лог: $LogPath"
  }
  default {
    # Install
    Install-Task -TimeStr $At
    Write-Host "[OK] Лог: $LogPath"
    Write-Host "[TIP] Перевірити запуск зараз:  pwsh -NoProfile -File `"$Runner`""
  }
}
