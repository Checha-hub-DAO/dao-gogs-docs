[CmdletBinding()]
param(
  [string]$Module = 'SHIELD4_ODESA',
  [string]$Root   = '.',
  [switch]$Strict
)
Set-StrictMode -Version Latest
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Output "$ts Validate-Releases: OK (stub)  Module=$Module  Root=$Root  Strict=$($Strict.IsPresent)"
exit 0
