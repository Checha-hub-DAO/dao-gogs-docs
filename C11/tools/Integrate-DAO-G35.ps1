<#
.SYNOPSIS
  Інтегрує пакет DAO-G35_v1.0.zip у CHECHA_CORE: розпаковує, оновлює INDEX, лог та CHECKSUM.

.DESCRIPTION
  Скрипт виконує послідовно:
    1) Перевірка шляхів та підготовка директорій.
    2) Розпаковка G35 у C12\Vault\DAO\G35 (з перезаписом).
    3) Додавання посилання в C12\INDEX.md (якщо відсутнє).
    4) Логування події до C03\LOG\LOG.md (із міткою часу).
    5) Обчислення SHA256 zip-файла та допис у C05\ARCHIVE\CHECKSUMS.txt.

.PARAMETER Root
  Корінь CHECHA_CORE (за замовчуванням: D:\CHECHA_CORE).

.PARAMETER ZipPath
  Повний шлях до ZIP (за замовчуванням: <Root>\C12\Vault\DAO\DAO-G35_v1.0.zip).

.EXAMPLE
  PS> .\Integrate-DAO-G35.ps1
  # Інтегрує за стандартними шляхами (D:\CHECHA_CORE\...)

.EXAMPLE
  PS> .\Integrate-DAO-G35.ps1 -Root "C:\CHECHA_CORE"
  # Інтеграція для альтернативного кореня

.NOTES
  Потребує PowerShell 7+ (pwsh), права на запис у каталоги CHECHA_CORE.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$Root = "D:\CHECHA_CORE",
    [Parameter()][string]$ZipPath
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
        # UTF-8 BOM для GitBook/Markdown сумісності
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
    Add-LineOnce -File $log -Line "# CORE LOG"  # заголовок лише якщо файл порожній
    Add-Content -LiteralPath $log -Value "$stamp [INFO] $Message"
}

# --- Шляхи за замовчуванням
if (-not $ZipPath) {
    $ZipPath = Join-Path $Root "C12\Vault\DAO\DAO-G35_v1.0.zip"
}
$destDir = Join-Path $Root "C12\Vault\DAO\G35"
$indexFile = Join-Path $Root "C12\INDEX.md"
$archDir = Join-Path $Root "C05\ARCHIVE"
$checks = Join-Path $archDir "CHECKSUMS.txt"

Write-Host "🔧 Integrate-DAO-G35 | Root = $Root"
Write-Host "📦 ZIP            | $ZipPath"
Write-Host "📁 Dest           | $destDir"

# 1) Перевірки
if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "ZIP не знайдено: $ZipPath"
}
New-DirIfMissing (Split-Path -Parent $destDir)
New-DirIfMissing $archDir

# 2) Розпаковка
if ($PSCmdlet.ShouldProcess($destDir, "Expand-Archive (force overwrite)")) {
    if (Test-Path -LiteralPath $destDir) {
        Remove-Item -LiteralPath $destDir -Recurse -Force
    }
    Expand-Archive -Path $ZipPath -DestinationPath $destDir -Force
    Write-Host "✅ Розпаковано до: $destDir"
}

# 3) Оновлення INDEX (посилання на README G35)
$indexLine = "- [G35 — DAO-Медіа](./DAO/G35/README.md) — інформаційне серце системи: кампанії, дайджести, медіа-фідбек."
Add-LineOnce -File $indexFile -Line $indexLine
Write-Host "🧭 INDEX оновлено: $indexFile"

# 4) Логування
Write-CoreLog -Root $Root -Message "Інтегровано DAO-G35 Package v1.0 → C12\Vault\DAO\G35"
Write-Host "📝 Запис у лог додано: C03\LOG\LOG.md"

# 5) SHA256 → CHECKSUMS.txt
$hash = Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256
$line = ("{0}  {1}" -f $hash.Hash, (Split-Path -Leaf $ZipPath))

if (-not (Test-Path -LiteralPath $checks)) {
    New-Item -ItemType File -Path $checks -Force | Out-Null
    Set-Content -LiteralPath $checks -Value "" -Encoding UTF8
}

# Додати лише якщо ще немає
$exists = Select-String -LiteralPath $checks -Pattern [Regex]::Escape($line) -Quiet
if (-not $exists) {
    Add-Content -LiteralPath $checks -Value $line
}

Write-Host "🔐 CHECKSUMS оновлено: $checks"
Write-Host "🎉 Готово."

