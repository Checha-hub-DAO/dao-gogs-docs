<#
  RADAR-IndexRepair_Run.ps1
  Санітарія індексу artifacts.csv: час → sha256 → дублі.
  Кроки:
    1) RADAR-FixTimestamps.ps1
    2) RADAR-Fingerprint.ps1
    3) RADAR-Deduplicate.ps1

  Exit codes: 0 = OK, 1 = PARTIAL/WARN, 2 = FAIL
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = "D:\CHECHA_CORE",
    [string]$CsvPath,                 # якщо пусто → <RepoRoot>\RADAR\INDEX\artifacts.csv
    [string]$AssumeOffset = "+03:00", # Europe/Kyiv (EEST); взимку використай "+02:00"
    [switch]$ForceRecalcSha,          # перерахувати sha256 навіть якщо вже є
    [switch]$DryRun                   # лише виконати перевірки/проби, без перезапису CSV
)

#region Helpers
function Log([string]$m, [string]$lvl = "INFO") {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m"
}
function Ensure-Dir([string]$p) {
    if (-not $p) { return }
    if (!(Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
function Run-Step([string]$name, [string]$scriptPath, [string[]]$args) {
    Log ("— {0} — start" -f $name)
    if (!(Test-Path -LiteralPath $scriptPath)) { Log "Скрипт не знайдено: $scriptPath" "ERR"; return 2 }
    pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath @args
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($code -eq 0) { Log ("{0} — ok" -f $name) }
    elseif ($code -eq 1) { Log ("{0} — попередження (exit=1)" -f $name) "WARN" }
    else { Log ("{0} — помилка (exit={1})" -f $name, $code) "ERR" }
    return $code
}
#endregion Helpers

# 0) Шляхи та підготовка
$CsvPath = if ([string]::IsNullOrWhiteSpace($CsvPath)) { Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' } else { $CsvPath }
$ToolsRoot = Join-Path $RepoRoot 'RADAR\tools'
$LogDir = Join-Path $RepoRoot 'C03_LOG'
Ensure-Dir $LogDir

if (!(Test-Path -LiteralPath $CsvPath)) { Log "Не знайдено індекс: $CsvPath" "ERR"; exit 2 }

$FixTs = Join-Path $ToolsRoot 'RADAR-FixTimestamps.ps1'
$Finger = Join-Path $ToolsRoot 'RADAR-Fingerprint.ps1'
$Dedup = Join-Path $ToolsRoot 'RADAR-Deduplicate.ps1'

# 1) SelfCheck (за наявності) — необов’язково, але корисно
$SelfCheck = Join-Path $ToolsRoot 'RADAR-SelfCheck.ps1'
if (Test-Path -LiteralPath $SelfCheck) {
    pwsh -NoProfile -ExecutionPolicy Bypass -File $SelfCheck -RepoRoot $RepoRoot -CsvPath $CsvPath
    if ($LASTEXITCODE -eq 2) { Log "SelfCheck ERR — перериваю санацію." "ERR"; exit 2 }
    elseif ($LASTEXITCODE -eq 1) { Log "SelfCheck WARN — продовжую, але переглянь лог." "WARN" }
}

# 2) Кроки санації
$overall = 0
$details = @()

# 2.1) Нормалізація timestamp
$code1 = Run-Step "FixTimestamps" $FixTs @(
    "-RepoRoot", $RepoRoot, "-CsvPath", $CsvPath, "-AssumeOffset", $AssumeOffset
    $(if ($DryRun) { "-DryRun" })
)
$details += "FixTimestamps=$code1"; if ($code1 -gt $overall) { $overall = $code1 }

# 2.2) Хешування sha256 (з файлу або з контенту)
$code2 = Run-Step "Fingerprint" $Finger @(
    "-RepoRoot", $RepoRoot, "-CsvPath", $CsvPath
    $(if ($ForceRecalcSha) { "-ForceRecalc" })
    $(if ($DryRun) { "-DryRun" })
)
$details += "Fingerprint=$code2"; if ($code2 -gt $overall) { $overall = $code2 }

# 2.3) Дедуплікація (soft-mode)
$code3 = Run-Step "Deduplicate" $Dedup @(
    "-RepoRoot", $RepoRoot, "-CsvPath", $CsvPath
    $(if ($DryRun) { "-DryRun" })
)
$details += "Deduplicate=$code3"; if ($code3 -gt $overall) { $overall = $code3 }

# 3) Підсумок + лог
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$line = "- [$stamp] IndexRepair: File='$CsvPath' | $(($details -join '; ')) | Exit=$overall"
Add-Content -Path (Join-Path $LogDir 'RADAR_INDEXREPAIR_LOG.md') -Encoding UTF8 $line

if ($overall -eq 0) { Log "INDEX REPAIR — SUCCESS"; exit 0 }
elseif ($overall -eq 1) { Log "INDEX REPAIR — PARTIAL (warnings)" "WARN"; exit 1 }
else { Log "INDEX REPAIR — FAILED" "ERR"; exit 2 }


