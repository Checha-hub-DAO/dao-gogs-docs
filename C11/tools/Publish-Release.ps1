# Publish-Release.ps1
[CmdletBinding()]
Param(
  [Parameter(Mandatory)] [string]$Version,                  # v0.1.1
  [string]$Repo = 'Checha-hub-DAO/checha-core',
  [string]$Rel  = 'D:\CHECHA_CORE\C11\SHIELD4_ODESA\Release',
  [string]$Chk  = 'D:\CHECHA_CORE\C11\SHIELD4_ODESA\Archive\CHECKSUMS.txt',
  [string]$Notes = "Automated release"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 1) Переконатись, що є ZIP'и
$assets = @(Get-ChildItem $Rel -Filter *.zip -File | % { $_.FullName })
if (-not $assets -or $assets.Count -eq 0) { throw "No *.zip in $Rel" }

# 2) Оновити CHECKSUMS.txt
New-Item -ItemType File -Force -Path $Chk | Out-Null
Clear-Content -LiteralPath $Chk
$assets | % {
  $h = Get-FileHash $_ -Algorithm SHA256
  "$($h.Hash) *$(Split-Path $_ -Leaf)" | Add-Content -LiteralPath $Chk
}
Write-Host "[ OK ] CHECKSUMS updated → $Chk" -ForegroundColor Green

# 3) Валідація
& pwsh -NoProfile -File "D:\CHECHA_CORE\C11\tools\Validate-Releases.ps1" -All
if ($LASTEXITCODE -ne 0) { throw "Validation failed with code $LASTEXITCODE" }
Write-Host "[ OK ] Validation passed" -ForegroundColor Green

# 4) Створити реліз і завантажити активи
$upload = @($assets + $Chk)
gh release create $Version --repo $Repo --title $Version --notes $Notes --latest @upload
Write-Host "[ OK ] Release $Version created and assets uploaded" -ForegroundColor Green
