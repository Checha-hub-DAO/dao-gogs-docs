<#
.SYNOPSIS
  Єдиний оркестратор для сценаріїв CHECHA_CORE (Daily/Weekly/Monthly/Rolling/Init/Publish)
  v1.3: стабільний запуск підскриптів (Run-Native), без $using:, FailOnMissingTools, детальний дамп винятків.
#>

[CmdletBinding()]
Param(
  [ValidateSet('Daily','Weekly','Monthly','Rolling','Init','Publish')]
  [string]$Mode = 'Daily',
  [string]$Root = 'C:\CHECHA_CORE',
  [switch]$ForceRun,
  [switch]$DryRun,
  [switch]$Quiet,
  [switch]$FailOnMissingTools,
  [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths & Logging ---------------------------------------------------------
$LogDir = Join-Path $Root 'C03\LOG'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
if (-not $LogFile) { $LogFile = Join-Path $LogDir 'orchestrator.log' }
$ErrorsLog = Join-Path $LogDir 'orchestrator.errors.log'

function Write-Log {
  param(
    [ValidateSet('INFO','WARN','ERROR')]
    [string]$Level = 'INFO',
    [Parameter(Mandatory)][string]$Message
  )
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = "{0} [{1,-5}] {2}" -f $ts, $Level.ToUpper(), $Message
  if (-not $Quiet) { Write-Host $line }
  $line | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log INFO ("BEGIN Orchestrator Mode={0}; Root={1}; ForceRun={2}; DryRun={3}; FailOnMissingTools={4}" -f $Mode,$Root,$ForceRun,$DryRun,$FailOnMissingTools)

# --- Helpers -----------------------------------------------------------------
$script:MissingTools = @()

function Note-Missing([string]$name){
  $script:MissingTools += $name
  Write-Log INFO ("{0} not found (skipped)" -f $name)
}

function Find-Tool {
  param(
    [Parameter(Mandatory)][string]$RelPath,
    [string[]]$Alternates
  )
  $candidates = @()
  $candidates += (Join-Path $Root $RelPath)
  if ($Alternates) { $candidates += $Alternates }
  foreach ($p in $candidates) {
    if (Test-Path $p) { return (Resolve-Path $p).Path }
  }
  return $null
}

# Надійний запуск нативного процесу зі збором stdout/stderr
function Run-Native {
  param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Args,
    [string]$Name = $Exe
  )
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Args
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($stdout) { Write-Log INFO  ("[{0}] OUT: {1}" -f $Name, $stdout.Trim()) }
    if ($stderr) { Write-Log ERROR ("[{0}] ERR: {1}" -f $Name, $stderr.Trim()) }
    return $p.ExitCode
  } catch {
    Write-Log ERROR ("[{0}] Exception: {1}" -f $Name, $_.Exception.Message)
    return 98
  }
}

function Invoke-Step {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Script,
    [int]$AcceptExitCode = 0
  )
  Write-Log INFO (">> STEP: {0}" -f $Name)
  if ($DryRun) { Write-Log INFO ("DryRun: {0} (skipped)" -f $Name); return 0 }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    & $Script
    $code = $LASTEXITCODE
    if (-not $code) { $code = 0 }
    $sw.Stop()
    if ($code -eq $AcceptExitCode) {
      Write-Log INFO ("<< OK: {0} ({1})" -f $Name,$sw.Elapsed)
      return 0
    } else {
      Write-Log ERROR ("<< FAIL: {0} exit={1} ({2})" -f $Name,$code,$sw.Elapsed)
      return $code
    }
  } catch {
    $sw.Stop()
    $err = $_
    "=== {0} === {1}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Name | Out-File -Append -FilePath $ErrorsLog -Encoding utf8
    $err | Format-List * -Force | Out-File -Append -FilePath $ErrorsLog -Encoding utf8
    if ($err.Exception) { $err.Exception | Format-List * -Force | Out-File -Append -FilePath $ErrorsLog -Encoding utf8 }
    if ($err.ScriptStackTrace) { "ScriptStackTrace:`n$($err.ScriptStackTrace)" | Out-File -Append -FilePath $ErrorsLog -Encoding utf8 }
    Write-Log ERROR ("<< EXCEPTION in {0}: {1}" -f ${Name}, $err.Exception.Message)
    return 99
  }
}

# --- Load Profile (optional) -------------------------------------------------
$ProfilePath = Find-Tool -RelPath 'C11\C11_AUTOMATION\tools\Checha.Profile.ps1'
if ($ProfilePath) {
  Write-Log INFO ("Load profile: {0}" -f $ProfilePath)
  . $ProfilePath
} else {
  Write-Log INFO "Profile NOT found (optional)."
}

# --- Tools -------------------------------------------------------------------
$T_DailyCreate = Find-Tool -RelPath 'C11\C11_AUTOMATION\tools\Create-StrategicTemplate.ps1'
$T_WeeklyPlan  = Find-Tool -RelPath 'C11\C11_AUTOMATION\tools\Start-Planning.ps1'
$T_MonthlyRep  = Find-Tool -RelPath 'C11\C11_AUTOMATION\tools\Checha-SessionMonthlyReport.ps1'
$T_ValidateRel = Find-Tool -RelPath 'C11\C11_AUTOMATION\tools\Validate-Releases.ps1' -Alternates @(
  (Join-Path $Root 'G\G45\RELEASES\Validate-Releases.ps1')
)
$T_ArchiveWork = Find-Tool -RelPath 'G\G45\RELEASES\Archive-Work.ps1'
$T_GitBookPub  = Find-Tool -RelPath 'C11\C11_AUTOMATION\tools\GitBookStdPack\Publish-GitBook-Submodule.ps1'

# --- Step builders ------------------------------------------------------------
function Step-Daily {
  $steps = @()

  if (Get-Command -Name crun -ErrorAction SilentlyContinue) {
    $steps += { Invoke-Step -Name 'Daily:Create-StrategicTemplate(crun)' -Script { crun; $global:LASTEXITCODE = 0 } }
  } elseif ($script:T_DailyCreate) {
    $steps += { Invoke-Step -Name 'Daily:Create-StrategicTemplate.ps1' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}"' -f $script:T_DailyCreate)
      $code = Run-Native -Exe $pw -Args $args -Name 'Create-StrategicTemplate'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Create-StrategicTemplate.ps1'
  }

  if ($script:T_ValidateRel) {
    $steps += { Invoke-Step -Name 'Daily:Validate-Releases -Quiet -All' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -All -Quiet' -f $script:T_ValidateRel)
      $code = Run-Native -Exe $pw -Args $args -Name 'Validate-Releases'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Validate-Releases.ps1'
  }

  if ($script:T_ArchiveWork) {
    $steps += { Invoke-Step -Name 'Daily:Archive-Work -DaysOld 0' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -DaysOld 0 -QuarantineKeepDays 14' -f $script:T_ArchiveWork)
      $code = Run-Native -Exe $pw -Args $args -Name 'Archive-Work'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Archive-Work.ps1'
  }

  return $steps
}

function Step-Weekly {
  $steps = @()

  if ($script:T_WeeklyPlan) {
    $steps += { Invoke-Step -Name 'Weekly:Start-Planning.ps1' -Script {
      $pw   = (Get-Command pwsh).Source
      $arg  = ('-NoProfile -File "{0}"' -f $script:T_WeeklyPlan)
      if ($script:ForceRun) { $arg += ' -ForceRun' }
      $code = Run-Native -Exe $pw -Args $arg -Name 'Start-Planning'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Start-Planning.ps1'
  }

  if ($script:T_ValidateRel) {
    $steps += { Invoke-Step -Name 'Weekly:Validate-Releases -All' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -All' -f $script:T_ValidateRel)
      $code = Run-Native -Exe $pw -Args $args -Name 'Validate-Releases'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Validate-Releases.ps1'
  }

  return $steps
}

function Step-Monthly {
  $steps = @()

  if ($script:T_MonthlyRep) {
    $steps += { Invoke-Step -Name 'Monthly:Checha-SessionMonthlyReport.ps1' -Script {
      $pw   = (Get-Command pwsh).Source
      $arg  = ('-NoProfile -File "{0}" -Mode Calendar' -f $script:T_MonthlyRep)
      if ($script:ForceRun) { $arg += ' -ForceRun' }
      $code = Run-Native -Exe $pw -Args $arg -Name 'SessionMonthlyReport'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Checha-SessionMonthlyReport.ps1'
  }

  if ($script:T_ValidateRel) {
    $steps += { Invoke-Step -Name 'Monthly:Validate-Releases -All -Quiet' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -All -Quiet' -f $script:T_ValidateRel)
      $code = Run-Native -Exe $pw -Args $args -Name 'Validate-Releases'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Validate-Releases.ps1'
  }

  return $steps
}

function Step-Rolling {
  $daily  = Step-Daily
  $weekly = @()
  if ($script:T_WeeklyPlan) {
    $weekly += { Invoke-Step -Name 'Rolling:Weekly(soft)' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -Soft' -f $script:T_WeeklyPlan)
      $code = Run-Native -Exe $pw -Args $args -Name 'Start-Planning(soft)'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Start-Planning.ps1'
  }
  return ($daily + $weekly)
}

function Step-Init {
  $steps = @()

  if ($script:T_DailyCreate) {
    $steps += { Invoke-Step -Name 'Init:DailyTemplateSeed' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -Seed' -f $script:T_DailyCreate)
      $code = Run-Native -Exe $pw -Args $args -Name 'DailyTemplateSeed'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Create-StrategicTemplate.ps1'
  }

  if ($script:T_ValidateRel) {
    $steps += { Invoke-Step -Name 'Init:Validate-Releases' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -All -Quiet' -f $script:T_ValidateRel)
      $code = Run-Native -Exe $pw -Args $args -Name 'Validate-Releases'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Validate-Releases.ps1'
  }

  return $steps
}

function Step-Publish {
  $steps = @()
  if ($script:T_GitBookPub) {
    $steps += { Invoke-Step -Name 'Publish:GitBook-Submodule' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -CommitMsg "orchestrator: publish batch"' -f $script:T_GitBookPub)
      $code = Run-Native -Exe $pw -Args $args -Name 'GitBook-Submodule'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Publish-GitBook-Submodule.ps1'
  }

  if ($script:T_ValidateRel) {
    $steps += { Invoke-Step -Name 'Publish:Validate-Releases' -Script {
      $pw   = (Get-Command pwsh).Source
      $args = ('-NoProfile -File "{0}" -All -Quiet' -f $script:T_ValidateRel)
      $code = Run-Native -Exe $pw -Args $args -Name 'Validate-Releases'
      $global:LASTEXITCODE = $code
    } }
  } else {
    Note-Missing 'Validate-Releases.ps1'
  }

  return $steps
}

# --- Build pipeline by mode --------------------------------------------------
$pipeline = @()
switch ($Mode) {
  'Daily'   { $pipeline = Step-Daily }
  'Weekly'  { $pipeline = Step-Weekly }
  'Monthly' { $pipeline = Step-Monthly }
  'Rolling' { $pipeline = Step-Rolling }
  'Init'    { $pipeline = Step-Init }
  'Publish' { $pipeline = Step-Publish }
}

# Строгий режим: якщо бракує тулів — провалюємо запуск
if ($FailOnMissingTools -and $script:MissingTools.Count -gt 0) {
  Write-Log ERROR ("Missing tools: {0}" -f ($script:MissingTools -join ', '))
  Write-Log ERROR "FailOnMissingTools is set → exit 10"
  exit 10
}

if (-not $pipeline -or $pipeline.Count -eq 0) {
  Write-Log INFO ("No steps resolved for Mode={0} (nothing to do)" -f $Mode)
  exit 0
}

# --- Execute -----------------------------------------------------------------
$total = 0
$executed = 0
foreach ($step in $pipeline) {
  $code = & $step
  $executed++
  if ($code -ne 0) { $total = $code } # пам’ятаємо останній ненульовий
}

if ($executed -eq 0) {
  Write-Log INFO ("No steps executed for Mode={0} (nothing to do). Returning 0." -f $Mode)
  exit 0
}

Write-Log INFO ("END Orchestrator Mode={0} exit={1}" -f $Mode,$total)
exit $total
