#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$BaseDir,
    [Parameter(Mandatory = $true)][string]$NewReleasePath,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter()][string[]]$ModulesToAdd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Manage SHIELD4 Release v2 (sanity) ==="
Write-Host "BaseDir:        $BaseDir"
Write-Host "NewReleasePath: $NewReleasePath"
Write-Host "Version:        $Version"
Write-Host "ModulesToAdd:   $($ModulesToAdd -join ', ')"

# Успішний вихід — щоб перевірити, що файл парситься і запускається
exit 0


