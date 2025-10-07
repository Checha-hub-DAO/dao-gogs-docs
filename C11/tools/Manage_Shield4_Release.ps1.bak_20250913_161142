<# 
.SYNOPSIS
  Керує складанням релізу SHIELD4 (структура релізу, копіювання пакетів, контроль хешів, нотатки, опційне розпакування ZIP).

.DESCRIPTION
  Створює каталог релізу в межах -BaseDir, копіює основний пакет (-NewReleasePath)
  і додаткові модулі (-ModulesToAdd), формує VERSION.txt, CHECKSUMS.txt (SHA256),
  веде лог у C03\LOG\shield4_release.log. Підтримує -WhatIf/-Confirm, -SelfTest,
  -AutoPickPrintBook (автопошук PrintBook PDF), -SkipMissing (мʼяка валідація модулів),
  -ReleaseNotes (включення нотаток) та -ExtractZip (розпакування ZIP).

.PARAMETER BaseDir
  Базовий робочий каталог модуля (напр. D:\CHECHA_CORE\C11\SHIELD4_ODESA).

.PARAMETER NewReleasePath
  Шлях до основного пакета релізу (рекомендовано ZIP).

.PARAMETER Version
  Версія релізу (напр. v2.6, v0.1.0, 2025.09.11).

.PARAMETER ModulesToAdd
  Додаткові файли (ZIP/PDF/MD/…): масив шляхів.

.PARAMETER AllowExtensions
  Дозволені розширення (без крапки). За замовчуванням: zip,pdf,md,txt,png,jpg,svg.

.PARAMETER ReleaseFolderName
  Назва підкаталогу для релізів (за замовчуванням: RELEASES).

.PARAMETER SelfTest
  Самотест перевірок шляхів.

.PARAMETER AutoPickPrintBook
  Автопошук останнього 'SHIELD4_ODESA*PrintBook*.pdf' у %USERPROFILE%\Downloads.

.PARAMETER SkipMissing
  Пропуск відсутніх/заборонених модулів з WARN у лог.

.PARAMETER ReleaseNotes
  Шлях до файлу нотаток; буде скопійовано до релізу як RELEASE_NOTES.md (або оригінальну назву).

.PARAMETER ExtractZip
  Якщо задано — розпаковує всі ZIP-и (головний та модулі) у підтеки.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
Param(
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$BaseDir,

  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$NewReleasePath,

  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Version,

  [Parameter()]
  [string[]]$ModulesToAdd = @(),

  [Parameter()]
  [string[]]$AllowExtensions = @('zip','pdf','md','txt','png','jpg','svg'),

  [Parameter()]
  [ValidatePattern('^[^\\/:*?"<>|]+$')]
  [string]$ReleaseFolderName = 'RELEASES',

  [switch]$SelfTest,
  [switch]$AutoPickPrintBook,
  [switch]$SkipMissing,

  [string]$ReleaseNotes,
  [switch]$ExtractZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------- УТИЛІТИ ----------
function New-Dir([string]$Path){
  $Path = $Path.TrimEnd('\',' ')
  if ([System.IO.Path]::HasExtension($Path)) { throw "New-Dir: got a FILE path (not a directory): $Path" }
  $driveMatches = [regex]::Matches($Path, '[A-Za-z]:\\')
  if ($driveMatches.Count -ge 2) {
    $drives  = ($driveMatches | ForEach-Object { $_.Value }) -join ', '
    throw "New-Dir: mixed/concatenated absolute path detected ($drives): $Path"
  }
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Write-RelLog {
  param([string]$LogFile,[ValidateSet('INFO','WARN','ERROR')] [string]$Level,[string]$Message)
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "{0} [{1}] {2}" -f $ts,$Level,$Message
  Add-Content -LiteralPath $LogFile -Value $line
  switch ($Level) {
    'ERROR' { Write-Error $Message }
    'WARN'  { Write-Warning $Message }
    default { Write-Verbose $Message }
  }
}

function Get-SHA256([string]$Path){ (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }
function Test-Allowed([string]$Path,[string[]]$AllowedExt){ [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLower() -in $AllowedExt }

function Copy-IntoRelease([string]$Path,[string]$TargetDir){
  if ([System.IO.Path]::HasExtension($TargetDir)) { throw "Copy-IntoRelease: TargetDir looks like a FILE path: $TargetDir" }
  New-Dir $TargetDir
  $name = [System.IO.Path]::GetFileName($Path)
  $dest = Join-Path $TargetDir $name
  if ($PSCmdlet.ShouldProcess($dest, "Copy from $Path")) { Copy-Item -LiteralPath $Path -Destination $dest -Force }
  return $dest
}

function Expand-ZipSafe {
  param([string]$ZipPath,[string]$TargetDir)
  New-Dir $TargetDir
  if ($PSCmdlet.ShouldProcess($TargetDir, "Expand-Archive from $ZipPath")) {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $TargetDir -Force
  }
}

# ---------- SELFTEST ----------
if ($SelfTest) {
  Write-Host ">> SELFTEST: start"
  try {
    $bd = ($BaseDir.TrimEnd('\',' '))
    New-Dir (Join-Path $bd 'C03\LOG')
    New-Dir (Join-Path $bd $ReleaseFolderName)
    try { New-Dir "$bd\C:\Windows\Temp\Bad" } catch { Write-Host "OK: caught mixed path: $($_.Exception.Message)" }
    try { New-Dir 'C:\Users\Public\file.pdf' } catch { Write-Host "OK: caught file path: $($_.Exception.Message)" }
    Write-Host ">> SELFTEST: done"
  } catch { Write-Error "SELFTEST FAILED: $($_.Exception.Message)" }
  return
}

# ---------- ВАЛІДАЦІЇ ВХОДУ ----------
$BaseDir = ($BaseDir.TrimEnd('\',' '))
if ($ReleaseFolderName -match '^[A-Za-z]:\\' -or $ReleaseFolderName -like '\\*') { throw "ReleaseFolderName must be a folder name (segment), not a full path: $ReleaseFolderName" }
if (-not (Test-Path -LiteralPath $BaseDir)) { throw "BaseDir not found: $BaseDir" }

# Лог раніше — щоб WARN/INFO зберігалися до помилок модулів
$LogDir  = Join-Path $BaseDir 'C03\LOG'; New-Dir $LogDir
$LogFile = Join-Path $LogDir 'shield4_release.log'

# Основний пакет
if (-not (Test-Path -LiteralPath $NewReleasePath)) { throw "NewReleasePath not found: $NewReleasePath" }
if (-not (Test-Allowed $NewReleasePath $AllowExtensions)) {
  $ext = [System.IO.Path]::GetExtension($NewReleasePath)
  throw "Extension not allowed ($ext): $NewReleasePath. Allowed: $($AllowExtensions -join ', ')"
}

# Автопідбір PDF (PrintBook)
$AutoPickedPrintBookPath = $null
if ($AutoPickPrintBook) {
  $dl = Join-Path $env:USERPROFILE 'Downloads'
  if (Test-Path $dl) {
    $pdf = Get-ChildItem $dl -File -Filter '*.pdf' -Recurse |
           Where-Object { $_.Name -like 'SHIELD4_ODESA*PrintBook*' } |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($pdf) { Write-Verbose "AutoPickPrintBook: found $($pdf.FullName)"; $ModulesToAdd += $pdf.FullName; $AutoPickedPrintBookPath = $pdf.FullName }
    else { Write-Warning "AutoPickPrintBook: no matching PDF found in $dl" }
  } else { Write-Warning "AutoPickPrintBook: Downloads folder not found: $dl" }
}

# ReleaseNotes (перевіримо наявність, але не обов'язковий)
$ReleaseNotesPath = $null
if ($ReleaseNotes) {
  if (Test-Path -LiteralPath $ReleaseNotes) {
    $ReleaseNotesPath = (Resolve-Path -LiteralPath $ReleaseNotes).Path
  } else {
    if ($SkipMissing) { Write-RelLog -LogFile $LogFile -Level 'WARN' -Message "ReleaseNotes missing, skipped: $ReleaseNotes" }
    else { throw "ReleaseNotes not found: $ReleaseNotes" }
  }
}

# Модулі: м'яка валідація
$validModules = New-Object System.Collections.Generic.List[string]
foreach($m in $ModulesToAdd){
  if (-not (Test-Path -LiteralPath $m)) {
    if ($SkipMissing) { Write-RelLog -LogFile $LogFile -Level 'WARN' -Message "Module missing, skipped: $m"; continue }
    else { throw "File not found: $m" }
  }
  if (-not (Test-Allowed $m $AllowExtensions)) {
    $ext = [System.IO.Path]::GetExtension($m)
    if ($SkipMissing) { Write-RelLog -LogFile $LogFile -Level 'WARN' -Message "Extension not allowed ($ext), skipped: $m"; continue }
    else { throw "Extension not allowed ($ext): $m. Allowed: $($AllowExtensions -join ', ')" }
  }
  $validModules.Add($m) | Out-Null
}

# ---------- ПІДГОТОВКА ШЛЯХІВ ----------
$ReleasesRoot = Join-Path $BaseDir $ReleaseFolderName; New-Dir $ReleasesRoot
$versionNorm  = ($Version -replace '[^\w\.\-]+','_')
$ReleaseDir   = Join-Path $ReleasesRoot $versionNorm
$AssetsDir    = Join-Path $ReleaseDir 'assets'
$MainExtract  = Join-Path $ReleaseDir 'main'
$AssetsExtract= Join-Path $ReleaseDir 'assets_extracted'
New-Dir $ReleaseDir; New-Dir $AssetsDir

Write-RelLog -LogFile $LogFile -Level 'INFO' -Message "Start Manage_Shield4_Release: Version=$Version BaseDir=$BaseDir"
if ($AutoPickedPrintBookPath) { Write-RelLog -LogFile $LogFile -Level 'INFO' -Message "AutoPickPrintBook: $AutoPickedPrintBookPath" }

# ---------- КОПІЮВАННЯ ----------
$copied = @()
$copied += Copy-IntoRelease -Path $NewReleasePath -TargetDir $ReleaseDir
foreach($m in $validModules){ $copied += Copy-IntoRelease -Path $m -TargetDir $AssetsDir }
Write-RelLog -LogFile $LogFile -Level 'INFO' -Message "Copied files: $($copied.Count)."

# ---------- RELEASE_NOTES ----------
$ReleaseNotesCopiedAs = $null
if ($ReleaseNotesPath) {
  $destName = if ([System.IO.Path]::GetExtension($ReleaseNotesPath).ToLower() -eq '.md') { 'RELEASE_NOTES.md' } else { [System.IO.Path]::GetFileName($ReleaseNotesPath) }
  $rnDest = Join-Path $ReleaseDir $destName
  if ($PSCmdlet.ShouldProcess($rnDest, "Copy ReleaseNotes from $ReleaseNotesPath")) {
    Copy-Item -LiteralPath $ReleaseNotesPath -Destination $rnDest -Force
  }
  $ReleaseNotesCopiedAs = (Split-Path -Leaf $rnDest)
  Write-RelLog -LogFile $LogFile -Level 'INFO' -Message "ReleaseNotes included: $ReleaseNotesCopiedAs"
}

# ---------- EXTRACT ZIP ----------
$extracted = @()
if ($ExtractZip) {
  # головний ZIP
  if ([System.IO.Path]::GetExtension($NewReleasePath).ToLower() -eq '.zip') {
    New-Dir $MainExtract
    Expand-ZipSafe -ZipPath (Join-Path $ReleaseDir (Split-Path -Leaf $NewReleasePath)) -TargetDir $MainExtract
    $extracted += @{ Type='main'; Target=$MainExtract }
  }
  # модулі ZIP
  $zipModules = Get-ChildItem -LiteralPath $AssetsDir -File -Filter *.zip -ErrorAction SilentlyContinue
  if ($zipModules) { New-Dir $AssetsExtract }
  foreach($z in $zipModules){
    $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($z.Name)
    $dest = Join-Path $AssetsExtract $nameNoExt
    Expand-ZipSafe -ZipPath $z.FullName -TargetDir $dest
    $extracted += @{ Type='asset'; Target=$dest; Name=$z.Name }
  }
  Write-RelLog -LogFile $LogFile -Level 'INFO' -Message "Extracted ZIP folders: $($extracted.Count)"
}

# ---------- VERSION.txt ----------
$versionFile = Join-Path $ReleaseDir 'VERSION.txt'
$verBody = @(
  "Module      : SHIELD4_ODESA"
  "Version     : $Version"
  "BuildTime   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
  "BaseDir     : $BaseDir"
  "ReleaseDir  : $ReleaseDir"
  "MainPackage : $(Split-Path -Leaf $NewReleasePath)"
  "AssetsCount : $($validModules.Count)"
  "AutoPick    : $($AutoPickPrintBook.IsPresent)"
  "AutoPicked  : $([string]::IsNullOrEmpty($AutoPickedPrintBookPath) ? '-' : (Split-Path -Leaf $AutoPickedPrintBookPath))"
  "ReleaseNotes: $([string]::IsNullOrEmpty($ReleaseNotesCopiedAs) ? '-' : $ReleaseNotesCopiedAs)"
  "ExtractZip  : $($ExtractZip.IsPresent)"
) -join [Environment]::NewLine
if ($PSCmdlet.ShouldProcess($versionFile, "Write VERSION.txt")) { Set-Content -LiteralPath $versionFile -Value $verBody -Encoding UTF8 }

# ---------- CHECKSUMS.txt ----------
$checksums = New-Object System.Collections.Generic.List[string]
foreach($p in $copied){ $checksums.Add( ("{0}  {1}" -f (Get-SHA256 $p), (Split-Path -Leaf $p)) ) }
$checksumFile = Join-Path $ReleaseDir 'CHECKSUMS.txt'
if ($PSCmdlet.ShouldProcess($checksumFile, "Write CHECKSUMS.txt")) { Set-Content -LiteralPath $checksumFile -Value ($checksums -join [Environment]::NewLine) -Encoding UTF8 }

# ---------- RELEASES\INDEX.md ----------
$indexFile = Join-Path $ReleasesRoot 'INDEX.md'
$lines = @()
$lines += "# SHIELD4 Releases Index"
$lines += ""
$lines += "Last update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$dirs = Get-ChildItem -LiteralPath $ReleasesRoot -Directory | Sort-Object Name -Descending
foreach($d in $dirs){
  $vf = Join-Path $d.FullName 'VERSION.txt'
  $cf = Join-Path $d.FullName 'CHECKSUMS.txt'
  $rn = Join-Path $d.FullName 'RELEASE_NOTES.md'
  $lines += "## $(Split-Path -Leaf $d.FullName)"
  if (Test-Path $vf) {
    $v = Get-Content -LiteralPath $vf -Raw
    $lines += ""
    $lines += "````"
    $lines += $v.TrimEnd()
    $lines += "````"
  }
  if (Test-Path $rn) {
    $lines += ""
    $lines += "<details><summary>RELEASE_NOTES.md</summary>"
    $lines += ""
    $lines += "````"
    $lines += (Get-Content -LiteralPath $rn -Raw).TrimEnd()
    $lines += "````"
    $lines += "</details>"
  }
  if (Test-Path $cf) {
    $c = Get-Content -LiteralPath $cf -Raw
    $lines += ""
    $lines += "<details><summary>CHECKSUMS</summary>"
    $lines += ""
    $lines += "````"
    $lines += $c.TrimEnd()
    $lines += "````"
    $lines += "</details>"
  }
  $lines += ""
}
if ($PSCmdlet.ShouldProcess($indexFile, "Write INDEX.md")) { Set-Content -LiteralPath $indexFile -Value ($lines -join [Environment]::NewLine) -Encoding UTF8 }

# ---------- ПІДСУМОК ----------
Write-RelLog -LogFile $LogFile -Level 'INFO' -Message "Release completed: $ReleaseDir"

[pscustomobject]@{
  Status        = 'OK'
  Version       = $Version
  ReleaseDir    = $ReleaseDir
  MainPackage   = (Split-Path -Leaf $NewReleasePath)
  AssetsCopied  = $validModules.Count
  Notes         = $ReleaseNotesCopiedAs
  Extracted     = $extracted.Count
  IndexFile     = $indexFile
  LogFile       = $LogFile
}
