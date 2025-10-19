<#
.SYNOPSIS
  Інтегрує або верифікує пакет DAO-G35_v1.0.zip у CHECHA_CORE.
.DESCRIPTION
  Виконує:
    - Перевірку шляхів
    - (Опційно) Розпаковку у C12\Vault\DAO\G35
    - Додавання посилання до C12\INDEX.md (idempotent)
    - Лог у C03\LOG\LOG.md (із таймштампом)
    - SHA256 → C05\ARCHIVE\CHECKSUMS.txt (без дублів)
  Режим -VerifyOnly робить лише перевірки й підсумок без змін.
.PARAMETER Root
  Корінь CHECHA_CORE (за замовчуванням: D:\CHECHA_CORE).
.PARAMETER ZipPath
  Повний шлях до ZIP (за замовчуванням: <Root>\C12\Vault\DAO\DAO-G35_v1.0.zip).
.PARAMETER VerifyOnly
  Лише перевірка існування ZIP, обчислення SHA256 і наявності в CHECKSUMS, без змін.
.EXAMPLE
  pwsh -NoProfile -File .\Integrate-DAO-G35_v2.ps1
.EXAMPLE
  pwsh -NoProfile -File .\Integrate-DAO-G35_v2.ps1 -VerifyOnly
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$Root = "D:\CHECHA_CORE",
    [Parameter()][string]$ZipPath,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DirIfMissing([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Add-LineOnce {
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Line
    )
    if (-not (Test-Path -LiteralPath $File)) {
        New-Item -ItemType File -Path $File -Force | Out-Null
        Set-Content -LiteralPath $File -Value "" -Encoding UTF8
    }
    $content = Get-Content -LiteralPath $File -ErrorAction Stop
    if ($content -notcontains $Line) {
        Add-Content -LiteralPath $File -Value $Line
    }
}

function Write-CoreLog {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Message
    )
    $logDir = Join-Path $Root "C03\LOG"
    $log = Join-Path $logDir "LOG.md"
    New-DirIfMissing $logDir
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    if (-not (Test-Path -LiteralPath $log)) {
        Set-Content -LiteralPath $log -Value "# CORE LOG`r`n" -Encoding UTF8
    }
    Add-Content -LiteralPath $log -Value "$stamp [INFO] $Message"
}

# --- Paths
if (-not $ZipPath) {
    $ZipPath = Join-Path $Root "C12\Vault\DAO\DAO-G35_v1.0.zip"
}
$destDir = Join-Path $Root "C12\Vault\DAO\G35"
$indexFile = Join-Path $Root "C12\INDEX.md"
$archDir = Join-Path $Root "C05\ARCHIVE"
$checks = Join-Path $archDir "CHECKSUMS.txt"

Write-Host "🔧 Integrate-DAO-G35_v2 | Root = $Root"
Write-Host "📦 ZIP                 | $ZipPath"
Write-Host "📁 Dest                | $destDir"

# --- Basic checks
if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "ZIP не знайдено: $ZipPath"
}
New-DirIfMissing $archDir

# --- Compute hash
$hash = Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256
$hashLine = ("{0}  {1}" -f $hash.Hash, (Split-Path -Leaf $ZipPath))

if ($VerifyOnly) {
    $existsChecks = (Test-Path -LiteralPath $checks) -and (Select-String -LiteralPath $checks -Pattern [Regex]::Escape($hashLine) -Quiet)
    Write-Host "ℹ️  VERIFY: SHA256 = $($hash.Hash)"
    Write-Host ("ℹ️  VERIFY: У CHECKSUMS.txt {0}" -f ($(if ($existsChecks) { "ЗНАЙДЕНО" } else { "НЕ ЗНАЙДЕНО" })))
    Write-Host "✅ Перевірка завершена (без змін)."
    return
}

# --- Expand
if ($PSCmdlet.ShouldProcess($destDir, "Expand-Archive (force overwrite)")) {
    if (Test-Path -LiteralPath $destDir) {
        Remove-Item -LiteralPath $destDir -Recurse -Force
    }
    Expand-Archive -Path $ZipPath -DestinationPath $destDir -Force
    Write-Host "✅ Розпаковано до: $destDir"
}

# --- INDEX
$indexLine = "- [G35 — DAO-Медіа](./DAO/G35/README.md) — інформаційне серце системи: кампанії, дайджести, медіа-фідбек."
Add-LineOnce -File $indexFile -Line $indexLine
Write-Host "🧭 INDEX оновлено: $indexFile"

# --- LOG
Write-CoreLog -Root $Root -Message "Інтегровано DAO-G35 Package v1.0 → C12\Vault\DAO\G35"
Write-Host "📝 Запис у лог додано: C03\LOG\LOG.md"

# --- CHECKSUMS
if (-not (Test-Path -LiteralPath $checks)) {
    New-Item -ItemType File -Path $checks -Force | Out-Null
    Set-Content -LiteralPath $checks -Value "" -Encoding UTF8
}
$exists = Select-String -LiteralPath $checks -Pattern [Regex]::Escape($hashLine) -Quiet
if (-not $exists) {
    Add-Content -LiteralPath $checks -Value $hashLine
}
Write-Host "🔐 CHECKSUMS оновлено: $checks"
Write-Host "🎉 Готово."


