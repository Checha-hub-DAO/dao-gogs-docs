param(
  [string]$Root = "D:\LeaderIntel",
  [string]$Name = "LeaderIntel"
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src   = Join-Path $Root "pkg\$Name"
$dist  = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$zip   = Join-Path $dist ("{0}_{1}.zip" -f $Name,$stamp)
if (Test-Path $zip) { Remove-Item $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($src,$zip)

$sha   = "$zip.sha256"
$hash  = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
("$hash  " + [IO.Path]::GetFileName($zip)) | Set-Content -LiteralPath $sha -Encoding ascii

Write-Host "ZIP : $zip"
Write-Host "SHA : $sha"
Write-Host "DONE ✅"
