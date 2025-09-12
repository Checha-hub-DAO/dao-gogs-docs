<#
.SYNOPSIS
  Реєструє щотижневу перевірку DAO‑модулів у Планувальнику з параметрами.
.DESCRIPTION
  Копіює/створює раннер Run-DAOModule-VerifyWeekly.ps1 і реєструє завдання \Checha\DAOModule-VerifyWeekly.
.PARAMETER Root
  Корінь CHECHA_CORE (D:\CHECHA_CORE за замовч.).
.PARAMETER Modules
  Список модулів (напр., "G35,G37,G43" або -Modules G35,G37,G43). За замовч.: G35,G37,G43.
.PARAMETER Hour
  Година запуску (локальний час), 0–23. За замовч.: 9.
.PARAMETER Minute
  Хвилина запуску, 0–59. За замовч.: 0.
.PARAMETER Day
  День тижня (MON,TUE,WED,THU,FRI,SAT,SUN). За замовч.: SUN.
.PARAMETER UseRegisterScheduledTask
  Використовувати модуль ScheduledTasks замість schtasks.exe.
#>
[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string[]]$Modules = @('G35','G37','G43'),
  [ValidateRange(0,23)][int]$Hour = 9,
  [ValidateRange(0,59)][int]$Minute = 0,
  [ValidateSet('MON','TUE','WED','THU','FRI','SAT','SUN')][string]$Day = 'SUN',
  [switch]$UseRegisterScheduledTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DirIfMissing([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)){
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

# Normalize modules to comma-separated for CLI passing
if ($Modules.Count -eq 1 -and $Modules[0] -match ','){
  $Modules = $Modules[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
$modulesArg = ($Modules -join ',')

# Paths
$toolsAuto = Join-Path $Root "C11\C11_AUTOMATION\tools"
$tools     = Join-Path $Root "C11\tools"
$runnerDst = Join-Path $toolsAuto "Run-DAOModule-VerifyWeekly.ps1"
$taskName  = "\Checha\DAOModule-VerifyWeekly"

# Ensure dirs
New-DirIfMissing $toolsAuto
New-DirIfMissing $tools

# Ensure runner exists (ми не перезаписуємо, якщо вже є — очікуємо, що ти вручну поклав v3)
if (-not (Test-Path -LiteralPath $runnerDst)) {
  @'
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string[]]$Modules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $Modules -or $Modules.Count -eq 0) {
  $Modules = @('G35','G37','G43')
} elseif ($Modules.Count -eq 1 -and $Modules[0] -match ',') {
  $Modules = $Modules[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$toolsDir = Join-Path $Root "C11\tools"
$integrator = Join-Path $toolsDir "Integrate-DAOModule_v1.ps1"

$logDir   = Join-Path $Root "C03\LOG"
$weekly   = Join-Path $logDir "verify_weekly.log"
$coreLog  = Join-Path $logDir "LOG.md"

function New-DirIfMissing([string]$Path){
  if (-not (Test-Path -LiteralPath $Path)){
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}
function Ensure-CoreLog([string]$File){
  if (-not (Test-Path -LiteralPath $File)){
    Set-Content -LiteralPath $File -Value "# CORE LOG`r`n" -Encoding UTF8
  }
}
function Write-CoreLog([string]$File,[string]$Message,[string]$Level = "INFO"){
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -LiteralPath $File -Value "$stamp [$Level] $Message"
}

if (-not (Test-Path -LiteralPath $integrator)){
  throw "Не знайдено інтегратор: $integrator"
}
New-DirIfMissing $logDir
Ensure-CoreLog $coreLog

$ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Add-Content -LiteralPath $weekly -Value "$ts [INFO] Start weekly verify (modules: $($Modules -join ', '))"

$results = @()
foreach($m in $Modules){
  $ok = $false; $sha = ""; $chk = "UNKNOWN"; $err = $null
  try {
    $out = & $integrator -Module $m -VerifyOnly -Root $Root 2>&1
    Add-Content -LiteralPath $weekly -Value ($out -join "`r`n")
    foreach($line in $out){
      if ($line -match 'SHA256\s*=\s*([A-Fa-f0-9]{40,64})'){ $sha = $Matches[1].ToUpper() }
      if ($line -match 'У CHECKSUMS\.txt\s+(ЗНАЙДЕНО|НЕ ЗНАЙДЕНО)'){ $chk = $Matches[1] }
    }
    $ok = $true
  } catch {
    $err = $_.Exception.Message
    Add-Content -LiteralPath $weekly -Value "$ts [ERR ] $m verify failed: $err"
  }
  $results += [pscustomobject]@{ Module=$m; OK=$ok; SHA=$sha; Checks=$chk; Error=$err }
}
$summaryLines = @()
foreach($r in $results){
  $sym = if($r.OK -and $r.Checks -eq 'ЗНАЙДЕНО'){'🟢'} elseif($r.OK){'🟡'} else {'🔴'}
  $shaShort = if([string]::IsNullOrWhiteSpace($r.SHA)){"—"} else {$r.SHA.Substring(0,[Math]::Min(12,$r.SHA.Length))}
  $checksTxt = if($r.Checks){$r.Checks} else {'UNKNOWN'}
  $msg = "{0} VERIFY {1}: SHA={2} CHECKS={3}{4}" -f $sym, $r.Module, $shaShort, $checksTxt, $(if($r.Error){" | ERR: " + $r.Error}else{""})
  $summaryLines += $msg
}
$stampEnd = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Add-Content -LiteralPath $weekly -Value ($summaryLines -join "`r`n")
Add-Content -LiteralPath $weekly -Value "$stampEnd [INFO] End weekly verify"
foreach($line in $summaryLines){ Write-CoreLog -File $coreLog -Message $line -Level "VERIFY" }
'@ | Set-Content -LiteralPath $runnerDst -Encoding UTF8
}

# PowerShell 7 path
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) {
  $pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"
}

# Build time string HH:MM
$time = "{0:D2}:{1:D2}" -f $Hour, $Minute

Write-Host "🔧 Register weekly verify task"
Write-Host "  Root: $Root"
Write-Host "  Runner: $runnerDst"
Write-Host "  Time: $time | Day: $Day | Modules: $modulesArg"
Write-Host "  Task: $taskName"
Write-Host "  pwsh: $pwsh"

# Remove old task if exists
if ($UseRegisterScheduledTask) {
  try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
  $act = New-ScheduledTaskAction -Execute $pwsh -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`" -Root `"{1}`" -Modules `"{2}`"" -f $runnerDst, $Root, $modulesArg)
  $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At ([datetime]::ParseExact($time,'HH:mm',$null))
  $folder = "\Checha"
  try {
    $null = Register-ScheduledTask -TaskName ($taskName -replace '^\\Checha\\','') -Action $act -Trigger $trg -Description "Weekly DAO module verify" -TaskPath $folder
  } catch { throw $_ }
} else {
  # schtasks.exe path registration
  $args = @(
    "/Create","/F",
    "/SC","WEEKLY",
    "/D",$Day,
    "/TN",$taskName,
    "/TR", ("`"{0}`" -NoProfile -ExecutionPolicy Bypass -File `"{1}`" -Root `"{2}`" -Modules `"{3}`"" -f $pwsh, $runnerDst, $Root, $modulesArg),
    "/ST",$time
  )
  $proc = Start-Process -FilePath schtasks.exe -ArgumentList $args -NoNewWindow -Wait -PassThru
  if ($proc.ExitCode -ne 0) { throw "schtasks.exe повернув код $($proc.ExitCode)" }
}

Write-Host "✅ Зареєстровано. Перевірити статус:"
Write-Host "  schtasks /Query /TN $taskName /V /FO LIST"
