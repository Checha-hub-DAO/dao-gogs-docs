param(
  [string]$Root = "D:\CHECHA_CORE",
  [string[]]$Modules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Resolve modules list (supports comma-separated)
if (-not $Modules -or $Modules.Count -eq 0) {
  $Modules = @('G35','G37','G43')
} elseif ($Modules.Count -eq 1 -and $Modules[0] -match ',') {
  $Modules = $Modules[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

# --- Config
$toolsDir = Join-Path $Root "C11\tools"
$integrator = Join-Path $toolsDir "Integrate-DAOModule_v1.ps1"

$logDir   = Join-Path $Root "C03\LOG"
$weekly   = Join-Path $logDir "verify_weekly.log"
$coreLog  = Join-Path $logDir "LOG.md"
$csvFile  = Join-Path $logDir "verify_weekly.csv"

# --- Helpers
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

# --- Prep
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
    # append raw output to weekly log
    Add-Content -LiteralPath $weekly -Value ($out -join "`r`n")

    # parse SHA and CHECKSUMS status
    foreach($line in $out){
      if ($line -match 'SHA256\s*=\s*([A-Fa-f0-9]{40,64})'){
        $sha = $Matches[1].ToUpper()
      }
      if ($line -match 'У CHECKSUMS\.txt\s+(ЗНАЙДЕНО|НЕ ЗНАЙДЕНО)'){
        $chk = $Matches[1]
      }
    }
    $ok = $true
  } catch {
    $err = $_.Exception.Message
    Add-Content -LiteralPath $weekly -Value "$ts [ERR ] $m verify failed: $err"
  }

  $results += [pscustomobject]@{
    Module = $m
    OK     = $ok
    SHA    = $sha
    Checks = $chk
    Error  = $err
  }
}

# --- Traffic-light summary
$summaryLines = @()
foreach($r in $results){
  $sym = if($r.OK -and $r.Checks -eq 'ЗНАЙДЕНО'){'🟢'} elseif($r.OK){'🟡'} else {'🔴'}
  $shaShort = if([string]::IsNullOrWhiteSpace($r.SHA)){"—"} else {$r.SHA.Substring(0,[Math]::Min(12,$r.SHA.Length))}
  $checksTxt = if($r.Checks){$r.Checks} else {'UNKNOWN'}
  $msg = "{0} VERIFY {1}: SHA={2} CHECKS={3}{4}" -f $sym, $r.Module, $shaShort, $checksTxt, $(if($r.Error){" | ERR: " + $r.Error}else{""})
  $summaryLines += $msg
}

# Write summary to weekly log
$stampEnd = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Add-Content -LiteralPath $weekly -Value ($summaryLines -join "`r`n")
Add-Content -LiteralPath $weekly -Value "$stampEnd [INFO] End weekly verify"

# Mirror summary to CORE LOG with timestamped lines
foreach($line in $summaryLines){
  Write-CoreLog -File $coreLog -Message $line -Level "VERIFY"
}

# --- CSV export (append with header if new)
$csvRows = @()
foreach($r in $results){
  $status = if($r.OK -and $r.Checks -eq 'ЗНАЙДЕНО'){'OK'} elseif($r.OK){'WARN'} else {'ERR'}
  $csvRows += [pscustomobject]@{
    Timestamp = $stampEnd
    Module    = $r.Module
    Status    = $status
    SHA       = $r.SHA
    Checks    = $r.Checks
    Error     = $r.Error
  }
}

if (Test-Path -LiteralPath $csvFile) {
  $csvRows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Append -Encoding utf8
} else {
  $csvRows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding utf8
}

# Also print to console
$summaryLines -join "`r`n"
