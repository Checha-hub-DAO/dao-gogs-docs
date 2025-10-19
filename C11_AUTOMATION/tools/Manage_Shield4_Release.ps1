[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path $_ })][string]$BaseDir,
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path $_ })][string]$NewReleasePath,
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$ModulesToAdd,
    [switch]$NoUnpack,
    [switch]$NoIndexUpdate
)
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
function Ok([string]$m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Inf([string]$m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }

$relDir = Join-Path $BaseDir 'Release'
$modDir = Join-Path $BaseDir 'Modules'
$workDir = Join-Path $BaseDir ('work_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $relDir, $modDir, $workDir | Out-Null

$destZip = Join-Path $relDir (Split-Path $NewReleasePath -Leaf)
Copy-Item -LiteralPath $NewReleasePath -Destination $destZip -Force
Ok "Release ZIP: $destZip"

if ($ModulesToAdd) {
    foreach ($m in $ModulesToAdd) { if (Test-Path $m) { Copy-Item $m $modDir -Force } }
    Ok "Modules copied → $modDir"
}

if (-not $NoUnpack) {
    $unpackDir = Join-Path $workDir "unpacked_$($Version)"
    New-Item -Type Directory -Force -Path $unpackDir | Out-Null
    Expand-Archive -LiteralPath $destZip -DestinationPath $unpackDir -Force
    Ok "Unpacked → $unpackDir"
}

if (-not $NoIndexUpdate) {
    $index = Join-Path $BaseDir 'INDEX.md'
    $line = "* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') — $Version — $(Split-Path $destZip -Leaf)"
    Add-Content -LiteralPath $index -Value $line
    Ok "INDEX.md updated"
}
Ok "Done: $Version"


