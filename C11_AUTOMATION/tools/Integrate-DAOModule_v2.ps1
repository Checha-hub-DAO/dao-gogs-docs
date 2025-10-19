<#
.SYNOPSIS
  Універсальний інтегратор DAO‑модулів у CHECHA_CORE (з pre-flight валідацією та ротацією логів).
.DESCRIPTION
  Інтегрує або верифікує пакет DAO‑<Module> у структуру CHECHA_CORE:
    - Pre‑flight перевірка вмісту ZIP (README.md, MANIFEST.yaml, AGENTS/, DOCS/ ...)
    - Пошук ZIP (або використання заданого -ZipPath)
    - Розпаковка до C12\Vault\DAO\<Module> (idempotent)
    - Оновлення C12\INDEX.md (один раз)
    - Лог події у C03\LOG\LOG.md
    - SHA256 у C05\ARCHIVE\CHECKSUMS.txt (без дублів)
    - (опційно) Ротація логів у C03\LOG\ (verify_weekly.log/csv, LOG.md)

.PARAMETER Module
  Код модуля (наприклад: G35, G37, G43). Обов’язковий, формат ^G\d{2}$.

.PARAMETER Root
  Корінь CHECHA_CORE. За замовчуванням: D:\CHECHA_CORE.

.PARAMETER ZipPath
  Повний шлях до ZIP. Якщо не задано — шукає останній ZIP у <Root>\C12\Vault\DAO, який містить "<Module>" у назві.

.PARAMETER VerifyOnly
  Лише перевірка наявності ZIP, SHA256 і запису в CHECKSUMS, без розпаковки та змін.

.PARAMETER NoIndexUpdate
  Не змінювати C12\INDEX.md.

.PARAMETER NoUnpack
  Пропустити розпаковку (корисно, якщо вже розпаковано).

.PARAMETER Strict
  Якщо pre‑flight виявив відсутні обов’язкові файли/каталоги — кидати помилку (і зупиняти інтеграцію).

.PARAMETER RequiredPaths
  Кастомний список обов’язкових шляхів у ZIP (рядки у стилі "README.md", "AGENTS/", "DOCS/"). Якщо не задано — використовується стандартний набір.

.PARAMETER RotateLogs
  Після інтеграції виконати просту ротацію логів у C03\LOG\ (verify_weekly.log, verify_weekly.csv, LOG.md).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^G\d{2}$')][string]$Module,
    [Parameter()][string]$Root = "D:\CHECHA_CORE",
    [Parameter()][string]$ZipPath,
    [switch]$VerifyOnly,
    [switch]$NoIndexUpdate,
    [switch]$NoUnpack,
    [switch]$Strict,
    [string[]]$RequiredPaths,
    [switch]$RotateLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

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
    if (-not (Test-Path -LiteralPath $log)) {
        Set-Content -LiteralPath $log -Value "# CORE LOG`r`n" -Encoding UTF8
    }
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -LiteralPath $log -Value "$stamp [INFO] $Message"
}

function Get-LatestZipForModule {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$Module
    )
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    Get-ChildItem -LiteralPath $Dir -File -Filter *.zip |
        Where-Object { $_.Name -match $Module } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Test-ZipPreflight {
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string[]]$Required
    )
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
    }
    finally {
        $zip.Dispose()
    }
    $missing = @()
    foreach ($req in $Required) {
        if ($req.EndsWith("/")) {
            # директорія: шукаємо будь-який запис, що починається з префікса
            $exists = $names | Where-Object { $_ -like "$req*" } | Select-Object -First 1
            if (-not $exists) { $missing += $req }
        }
        else {
            # файл: точне співпадіння в корені
            $exists = $names -contains $req
            if (-not $exists) { $missing += $req }
        }
    }
    [pscustomobject]@{
        ZipPath  = $ZipPath
        Required = $Required
        Missing  = $missing
        Ok       = ($missing.Count -eq 0)
    }
}

function Rotate-File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$MaxBytes,
        [int]$Keep = 3
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fi) { return $false }
    if ($fi.Length -lt $MaxBytes) { return $false }
    $dir = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $ext = [IO.Path]::GetExtension($name)
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $rot = Join-Path $dir ("{0}.{1}{2}" -f $base, $stamp, $ext)
    Move-Item -LiteralPath $Path -Destination $rot -Force
    # створити порожній новий файл з тим самим ім'ям
    Set-Content -LiteralPath $Path -Value "" -Encoding UTF8

    # чистимо старі
    $pattern = Join-Path $dir ("{0}.*{1}" -f $base, $ext)
    $old = Get-ChildItem -LiteralPath $dir -Filter ("{0}.*{1}" -f $base, $ext) | Sort-Object LastWriteTime -Descending
    $i = 0
    foreach ($f in $old) {
        $i++
        if ($i -le $Keep) { continue }
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# --- Paths
$daoDir = Join-Path $Root "C12\Vault\DAO"
$destDir = Join-Path $daoDir $Module
$indexFile = Join-Path $Root "C12\INDEX.md"
$archDir = Join-Path $Root "C05\ARCHIVE"
$checks = Join-Path $archDir "CHECKSUMS.txt"
$logDir = Join-Path $Root "C03\LOG"

Write-Host "🔧 Integrate-DAOModule v2 | Module = $Module"
Write-Host "📁 Root                  | $Root"

# --- Resolve ZIP
if (-not $ZipPath) {
    $latest = Get-LatestZipForModule -Dir $daoDir -Module $Module
    if (-not $latest) {
        throw "ZIP для модуля $Module не знайдено у $daoDir. Вкажи -ZipPath або поклади файл у цю папку."
    }
    $ZipPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "ZIP не знайдено: $ZipPath"
}
Write-Host "📦 ZIP                   | $ZipPath"
Write-Host "📍 Dest                  | $destDir"

# --- Ensure dirs
New-DirIfMissing $archDir
New-DirIfMissing $logDir

# --- Pre-flight
if (-not $RequiredPaths -or $RequiredPaths.Count -eq 0) {
    $RequiredPaths = @(
        "README.md",
        "MANIFEST.yaml",
        "AGENTS/",
        "DOCS/"
    )
}
$pf = Test-ZipPreflight -ZipPath $ZipPath -Required $RequiredPaths
if ($pf.Ok) {
    Write-Host "✅ Pre‑flight: усі обов’язкові елементи присутні."
}
else {
    Write-Warning ("Pre‑flight: відсутні елементи → {0}" -f ($pf.Missing -join ", "))
    Write-CoreLog -Root $Root -Message ("[WARN] Pre‑flight $Module: відсутні → {0}" -f ($pf.Missing -join ", "))
    if ($Strict) {
        throw ("Pre‑flight (Strict): зупинено інтеграцію через відсутні елементи → {0}" -f ($pf.Missing -join ", "))
    }
}

# --- Compute hash
$hash = Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256
$hashLine = ("{0}  {1}" -f $hash.Hash, (Split-Path -Leaf $ZipPath))
Write-Host "🔑 SHA256                | $($hash.Hash)"

if ($VerifyOnly) {
    $existsChecks = (Test-Path -LiteralPath $checks) -and (Select-String -LiteralPath $checks -Pattern [Regex]::Escape($hashLine) -Quiet)
    Write-Host ("ℹ️  VERIFY: У CHECKSUMS.txt {0}" -f ($(if ($existsChecks) { "ЗНАЙДЕНО" } else { "НЕ ЗНАЙДЕНО" })))
    Write-Host "✅ Перевірка завершена (без змін)."
    return
}

# --- Unpack
if (-not $NoUnpack) {
    if ($PSCmdlet.ShouldProcess($destDir, "Expand-Archive (force overwrite)")) {
        if (Test-Path -LiteralPath $destDir) {
            Remove-Item -LiteralPath $destDir -Recurse -Force
        }
        Expand-Archive -Path $ZipPath -DestinationPath $destDir -Force
        Write-Host "✅ Розпаковано до: $destDir"
    }
}
else {
    Write-Host "⏭️  Пропущено розпаковку (-NoUnpack)."
}

# --- INDEX update (generic line; якщо є README.md — підставляємо заголовок)
if (-not $NoIndexUpdate) {
    $indexLine = "- [$Module](./DAO/$Module/README.md) — DAO‑модуль, інтегрований у CHECHA_CORE."
    $readme = Join-Path $destDir "README.md"
    if (Test-Path -LiteralPath $readme) {
        try {
            $hdr = (Select-String -LiteralPath $readme -Pattern '^\s*#\s+(.+)$' -AllMatches | Select-Object -First 1)
            if ($hdr) {
                $title = ($hdr.Matches[0].Groups[1].Value).Trim()
                $indexLine = "- [$title](./DAO/$Module/README.md) — DAO‑модуль $Module."
            }
        }
        catch { }
    }
    Add-LineOnce -File $indexFile -Line $indexLine
    Write-Host "🧭 INDEX оновлено: $indexFile"
}
else {
    Write-Host "⏭️  Пропущено оновлення INDEX (-NoIndexUpdate)."
}

# --- LOG
Write-CoreLog -Root $Root -Message "Інтегровано DAO‑модуль $Module → C12\Vault\DAO\$Module (ZIP: $(Split-Path -Leaf $ZipPath))"
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

# --- Rotate logs (optional)
if ($RotateLogs) {
    $rot1 = Rotate-File -Path (Join-Path $logDir "verify_weekly.log") -MaxBytes (5MB) -Keep 5
    $rot2 = Rotate-File -Path (Join-Path $logDir "verify_weekly.csv") -MaxBytes (10MB) -Keep 5
    $rot3 = Rotate-File -Path (Join-Path $logDir "LOG.md") -MaxBytes (2MB) -Keep 5
    Write-Host ("♻️  Ротація логів: weekly.log={0}, weekly.csv={1}, LOG.md={2}" -f $rot1, $rot2, $rot3)
}

Write-Host "🎉 Готово."


