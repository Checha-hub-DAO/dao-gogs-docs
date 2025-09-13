[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter()][string]$Notes = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Roots
$C11Root  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $C11Root "..")).Path

# Paths
$BaseDir = Join-Path $RepoRoot "C11\SHIELD4_ODESA"
$Release = Join-Path $BaseDir "Release"
$Archive = Join-Path $BaseDir "Archive"
$Chk     = Join-Path $Archive "CHECKSUMS.txt"

# 1) CHECKSUMS (перегенеруємо)
New-Item -ItemType Directory -Force -Path $Archive | Out-Null
New-Item -ItemType File -Force -Path $Chk | Out-Null
Clear-Content -LiteralPath $Chk
Get-ChildItem $Release -Filter *.zip -File | ForEach-Object {
  $h = Get-FileHash $_.FullName -Algorithm SHA256
  "$($h.Hash) *$($_.Name)" | Add-Content -LiteralPath $Chk
}
Write-Host "[ OK ] CHECKSUMS updated → $Chk"

# 2) Валідація (STRICT локально; у CI ти вже керуєш через -Strict у воркфлоу)
& pwsh -NoProfile -File (Join-Path $C11Root "tools\Validate-Releases.ps1") -All -Strict
if ($LASTEXITCODE -ne 0) { throw "Validation failed" }
Write-Host "[ OK ] Validation passed"

# 3) Збираємо активи
$assets = @()
$assets += (Get-ChildItem $Release -Filter *.zip -File | ForEach-Object { $_.FullName })
$assets += $Chk
if (-not $assets) { throw "No assets to upload" }

# 4) Repo для gh (CI-aware)
$repo = $env:GITHUB_REPOSITORY  # "owner/name" у GitHub Actions
$repoArgs = @()
if ($repo) { $repoArgs = @('--repo', $repo) }

# 5) Create-or-update реліз
# Перевіряємо наявність
$exists = $false
try {
  & gh release view $Version @repoArgs 1>$null 2>$null
  if ($LASTEXITCODE -eq 0) { $exists = $true }
} catch { $exists = $false }

if (-not $exists) {
  # створюємо новий реліз
  & gh release create $Version @repoArgs --title $Version --notes $Notes --latest @assets | Out-Host
  Write-Host "[ OK ] Release $Version created and assets uploaded"
} else {
  # оновлюємо існуючий: перезаливаємо активи + підправляємо нотатки/тайтл
  & gh release upload $Version @repoArgs @assets --clobber | Out-Host
  & gh release edit   $Version @repoArgs --title $Version --notes $Notes | Out-Host
  Write-Host "[ OK ] Release $Version updated (assets + notes)"
}
