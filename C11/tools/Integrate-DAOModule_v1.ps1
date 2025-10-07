[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('G43')][string]$Module,
  [string]$Root = 'D:\CHECHA_CORE',
  [string]$ZipPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$daoDir  = Join-Path $Root 'C12\Vault\DAO'
$destDir = Join-Path $daoDir $Module
if (-not (Test-Path $daoDir)) { New-Item -ItemType Directory -Force -Path $daoDir | Out-Null }

# ---- Resolve ZIP
if (-not $ZipPath -or -not (Test-Path $ZipPath)) {
  $ZipPath = Get-ChildItem $daoDir -Filter ($Module + '*.zip') -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Desc | Select-Object -First 1 -Expand FullName
  if (-not $ZipPath) { throw "ZIP для модуля $Module не знайдено у $daoDir. Вкажи -ZipPath." }
}

Write-Host "🔧 Integrate-DAOModule | Module = $Module"
Write-Host "📁 Root               | $Root"
Write-Host "📦 ZIP                | $ZipPath"
Write-Host "📍 Dest               | $destDir"

# ---- Hash
$hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
Write-Host "🔑 SHA256             | $hash"

# ---- Prepare destination (safe replace)
if (Test-Path $destDir) {
  $bak = "$destDir.bak_$(Get-Date -f yyyyMMdd_HHmmss)"
  Rename-Item $destDir $bak -Force
}
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# ---- Extract
Expand-Archive -LiteralPath $ZipPath -DestinationPath $destDir -Force
Write-Host "✅ Розпаковано до: $destDir"

# ---- Update INDEX.md
$index = Join-Path $Root 'C12\INDEX.md'
if (-not (Test-Path $index)) { New-Item -ItemType File -Path $index | Out-Null }
$idx = Get-Content $index -Raw -ErrorAction SilentlyContinue
if ($idx -notmatch [regex]::Escape($Module)) {
  Add-Content -LiteralPath $index -Value ("* {0} → {1}" -f $Module,$destDir)
  Write-Host "🧭 INDEX оновлено: $index"
} else {
  Write-Host "🧭 INDEX вже містить $Module"
}

# ---- Global log
$glog = Join-Path $Root 'C03\LOG\LOG.md'
New-Item -ItemType Directory -Force -Path (Split-Path $glog) | Out-Null
Add-Content -LiteralPath $glog -Value ("{0} [DAO] {1} integrated | ZIP={2} SHA256={3}" -f (Get-Date -f 'yyyy-MM-dd HH:mm:ss'), $Module, (Split-Path $ZipPath -Leaf), $hash)
Write-Host "📝 Запис у лог додано: C03\LOG\LOG.md"

exit 0
