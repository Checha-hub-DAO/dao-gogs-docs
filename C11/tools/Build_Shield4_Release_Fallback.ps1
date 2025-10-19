param(
    [Parameter(Mandatory = $true)][string]$BaseDir,
    [Parameter(Mandatory = $true)][string]$NewReleasePath,
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$ModulesToAdd = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (!(Test-Path $BaseDir)) { throw "BaseDir not found: $BaseDir" }
if (!(Test-Path $NewReleasePath)) { throw "NewReleasePath not found: $NewReleasePath" }

$releases = Join-Path $BaseDir 'releases'
$work = Join-Path $releases $Version
$modsDir = Join-Path $work 'modules'
$metaDir = Join-Path $work 'meta'

New-Item -ItemType Directory -Force -Path $releases, $work, $modsDir, $metaDir | Out-Null

$baseName = Split-Path $NewReleasePath -Leaf
Copy-Item -LiteralPath $NewReleasePath -Destination (Join-Path $work $baseName) -Force

foreach ($m in $ModulesToAdd) {
    if (Test-Path $m) {
        Copy-Item -LiteralPath $m -Destination (Join-Path $modsDir (Split-Path $m -Leaf)) -Force
    }
    else {
        Write-Warning "Модуль не знайдено: $m"
    }
}

# Перелік файлів після копій
$files = Get-ChildItem $work -Recurse -File

# CHECKSUMS
$chk = foreach ($f in $files) {
    $h = Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256
    '{0}  {1}' -f $h.Hash, ($f.FullName.Substring($work.Length + 1))
}
$chk | Set-Content -LiteralPath (Join-Path $work 'CHECKSUMS.txt') -Encoding UTF8

# MANIFEST.json
$manifest = [pscustomobject]@{
    version  = $Version
    built_at = (Get-Date).ToString('s')
    base_zip = $baseName
    modules  = ($ModulesToAdd | ForEach-Object { Split-Path $_ -Leaf })
    files    = ($files | ForEach-Object { $_.FullName.Substring($work.Length + 1) })
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $metaDir 'MANIFEST.json') -Encoding UTF8

# ZIP out
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipOut = Join-Path $releases ("SHIELD4_ODESA_release_{0}_{1}.zip" -f $Version, (Get-Date -f yyyyMMdd_HHmmss))
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zipOut)

Write-Host "✅ Release built: $zipOut"


