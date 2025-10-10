# ЗБЕРЕЖИ як: D:\CHECHA_CORE\C11\C11_AUTOMATION\tools\Lint-Scripts.ps1
[CmdletBinding()]
param(
  [string]$Root = 'D:\CHECHA_CORE',
  [string[]]$Scan = @('C11\tools','C11\C11_AUTOMATION\tools','C11\C11_AUTOMATION\steps'),
  [string]$LogDir = $null,
  [switch]$FailOnUnbalanced,
  [switch]$Quiet,
  [switch]$OpenLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Test-HereStrings([string]$File){
  $t = Get-Content $File -Raw -Encoding UTF8
  $sDQ = ([regex]::Matches($t,'(?m)^\s*@"\s*$')).Count      # початок  @" 
  $eDQ = ([regex]::Matches($t,'(?m)^\s*"\@\s*$')).Count     # кінець    "@
  $sSQ = ([regex]::Matches($t,"(?m)^\s*@'\s*$")).Count      # початок  @'
  $eSQ = ([regex]::Matches($t,"(?m)^\s*'@\s*$")).Count      # кінець    '@
  [pscustomobject]@{
    File     = $File
    StartDQ  = $sDQ; EndDQ = $eDQ
    StartSQ  = $sSQ; EndSQ = $eSQ
    Balanced = (($sDQ -eq $eDQ) -and ($sSQ -eq $eSQ))
  }
}

# 1) Таргет-папки
$targets = $Scan | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path $_ }

# 2) Збір результатів
$all = foreach($d in $targets){
  Get-ChildItem $d -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { Test-HereStrings $_.FullName }
}

# 3) Лог і підсумок
if (-not $LogDir) { $LogDir = Join-Path $Root 'C03\LOG\weekly_reports' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$log = Join-Path $LogDir ("lint_ps1_{0}.log" -f (Get-Date -f yyyyMMdd_HHmmss))

$all | Sort-Object Balanced,File | Format-Table -AutoSize | Out-String |
  Tee-Object -FilePath $log | Out-Null

$bad = $all | Where-Object { -not $_.Balanced }
if ($bad) {
  if (-not $Quiet) {
    Write-Warning "Unbalanced here-strings detected. See: $log"
    $bad | Format-Table File,StartDQ,EndDQ,StartSQ,EndSQ -AutoSize
  }
  if ($OpenLog) { notepad $log }
  if ($FailOnUnbalanced) { exit 1 } else { exit 0 }
} else {
  if (-not $Quiet) { Write-Host "✅ Lint OK. Details: $log" }
  if ($OpenLog) { notepad $log }
  exit 0
}
