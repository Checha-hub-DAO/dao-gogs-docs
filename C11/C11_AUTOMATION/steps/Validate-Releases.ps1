param(
    [string]$Root = "D:\CHECHA_CORE",
    [switch]$All
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ok = $true

# G43 health
$tool = Join-Path $Root 'C11\C11_AUTOMATION\tools\Check-G43-Health.ps1'
if (!(Test-Path $tool)) { Write-Error "Health tool not found: $tool"; exit 2 }
& $tool -Root $Root *>&1
if ($LASTEXITCODE -ne 0) { $ok = $false }

# (за потреби сюди додаси інші модулі/перевірки)

if ($ok) { Write-Host "Validate-Releases: OK"; exit 0 }
else { Write-Host "Validate-Releases: FAIL"; exit 1 }


