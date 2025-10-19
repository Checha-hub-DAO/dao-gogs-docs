# ===========================================
# Register-ChechaScheduledTasks.ps1
# ===========================================

[CmdletBinding()]
param(
    [string] $RepoRoot = 'D:\CHECHA_CORE',

    # Щотижнева задача (за замовч. Нд 20:00)
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string] $WeeklyDay = 'Sunday',
    [string] $WeeklyTime = '20:00',

    # (Опційно) щоденна перевірка о 09:00
    [switch] $EnableDaily,
    [string] $DailyTime = '09:00'
)

$ErrorActionPreference = 'Stop'

# --- Paths
$runner = "D:\CHECHA_CORE\TOOLS\Run-WeeklyPipeline.ps1"

if (!(Test-Path -LiteralPath $runner)) {
    throw "Runner not found: $runner"
}

# --- pwsh path (platform-agnostic find)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) {
    # fallback to Windows PowerShell if pwsh missing
    $pwsh = (Get-Command powershell -ErrorAction Stop).Source
}

Write-Host "[INFO] Using shell: $pwsh"

# --- Common principal (current user; runs when user is logged on)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType InteractiveToken

# --- Weekly task
$weeklyName = "CHECHA_Weekly_Publish"
$weeklyArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -RepoRoot `"$RepoRoot`""
$weeklyAction = New-ScheduledTaskAction  -Execute $pwsh -Argument $weeklyArgs -WorkingDirectory $RepoRoot
$weeklyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $WeeklyDay -At ([datetime]::Parse($WeeklyTime))

# Make / update
if (Get-ScheduledTask -TaskName $weeklyName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $weeklyName -Confirm:$false
}
Register-ScheduledTask -TaskName $weeklyName -Action $weeklyAction -Trigger $weeklyTrigger -Principal $principal -Description "CHECHA weekly pipeline (Europe/Kyiv logic)"

Write-Host "[OK] Weekly task registered: $weeklyName  ($WeeklyDay @ $WeeklyTime)"

# --- Daily (optional)
if ($EnableDaily) {
    $dailyName = "CHECHA_Daily_Check"
    $dailyArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"Import-Module 'D:\CHECHA_CORE\TOOLS\Utils.Core\Utils.Core.psd1' -Force; (Get-KyivDate).ToString('yyyy-MM-dd HH:mm:ss')|Write-Output`""
    $dailyAction = New-ScheduledTaskAction  -Execute $pwsh -Argument $dailyArgs -WorkingDirectory $RepoRoot
    $dailyTrigger = New-ScheduledTaskTrigger -Daily  -At ([datetime]::Parse($DailyTime))

    if (Get-ScheduledTask -TaskName $dailyName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $dailyName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $dailyName -Action $dailyAction -Trigger $dailyTrigger -Principal $principal -Description "CHECHA daily sanity-check (Kyiv time stamp)"

    Write-Host "[OK] Daily task registered: $dailyName  (@ $DailyTime)"
}

# --- On-Demand launcher (no trigger)
$onDemandName = "CHECHA_Weekly_OnDemand"
$onDemandArgs = $weeklyArgs
$onDemandAction = New-ScheduledTaskAction -Execute $pwsh -Argument $onDemandArgs -WorkingDirectory $RepoRoot

if (Get-ScheduledTask -TaskName $onDemandName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $onDemandName -Confirm:$false
}
Register-ScheduledTask -TaskName $onDemandName -Action $onDemandAction -Principal $principal -Description "CHECHA weekly pipeline (no trigger; run on demand)"

Write-Host "[OK] On-demand task registered: $onDemandName"
Write-Host "[DONE] Use 'Start-ScheduledTask -TaskName ""$onDemandName""' to run manually."

