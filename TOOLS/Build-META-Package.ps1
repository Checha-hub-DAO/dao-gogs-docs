<# 
.SYNOPSIS
  Пакування META-Revival пакета (md + csv + png) у ZIP з MANIFEST.{txt,yaml,json}, SHA256 і опційним GPG-підписом.

.VERSION
  1.1.0

.CHANGELOG
  - Додано MANIFEST.json
  - Прапорець -Sign для GPG detached-sign (.asc) ZIP-файла
  - Опції -GpgPath, -KeyId, -SignTag
#>

[CmdletBinding()]
param(
  [string]$Root = 'D:\CHECHA_CORE',
  [string]$Name = 'META_Revival',
  [string]$Version = '1.1',
  [string]$Stamp,
  [switch]$SkipPng,
  [switch]$Open,
  [switch]$Quiet,

  # Нове у v1.1.0
  [switch]$Sign,                    # підписати ZIP (detached .asc) через gpg
  [string]$GpgPath = 'gpg',         # шлях/назва виконуваного gpg
  [string]$KeyId,                   # ідентифікатор ключа (опціонально)
  [switch]$SignTag                  # якщо тег створюється/оновлюється тут — підписати його
)

# ---------- Helpers ----------
function Write-Info([string]$msg){ if(-not $Quiet){ Write-Host "[INFO] $msg" } }
function Write-Ok([string]$msg){ if(-not $Quiet){ Write-Host "[OK]  $msg" -ForegroundColor Green } }
function Write-Warn([string]$msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg){ Write-Host "[ERR] $msg" -ForegroundColor Red }

function Ensure-Dir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path)){ New-Item -Path $Path -ItemType Directory -Force | Out-Null }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Get-Sha256([string]$FilePath){
  if(-not (Test-Path -LiteralPath $FilePath)){ throw "File not found: $FilePath" }
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $FilePath
  return $h.Hash.ToUpperInvariant()
}

function New-Json([hashtable]$obj, [string]$path){
  $json = $obj | ConvertTo-Json -Depth 6
  $json | Set-Content -LiteralPath $path -Encoding UTF8
}

# ---------- Init ----------
try {
  $ErrorActionPreference = 'Stop'
  $nowLocal = Get-Date
  if([string]::IsNullOrWhiteSpace($Stamp)){ $Stamp = $nowLocal.ToString('yyyy-MM-dd') }

  $c06 = Ensure-Dir (Join-Path $Root 'C06_FOCUS')
  $c03 = Ensure-Dir (Join-Path $Root 'C03_LOG\reports\META')
  $stagingRoot = Ensure-Dir (Join-Path $Root "_staging\META_$($Stamp)")
  $staging = Ensure-Dir (Join-Path $stagingRoot "$($Name)_$($Version)")
  $symbolsDir = Join-Path $c06 'META_SYMBOLS'
  $mdName = "{0}_{1}.md" -f $Name, $Version
  $mdPath = Join-Path $c06 $mdName
  if(-not (Test-Path -LiteralPath $mdPath)){
    $legacy = Join-Path $c06 'META_Revival_1.1.md'
    if(Test-Path -LiteralPath $legacy){ $mdPath = $legacy }
  }
  $csvPath = Join-Path $c06 'META_SYMBOLS.csv'

  if(-not (Test-Path -LiteralPath $mdPath)){ throw "Не знайдено Markdown документ META: $mdPath" }
  if(-not (Test-Path -LiteralPath $csvPath)){ throw "Не знайдено CSV символів: $csvPath" }

  Write-Info "Root: $Root"
  Write-Info "MD:   $mdPath"
  Write-Info "CSV:  $csvPath"

  # ---------- Копіювання артефактів у staging ----------
  Copy-Item -LiteralPath $mdPath -Destination (Join-Path $staging 'META.md') -Force
  Copy-Item -LiteralPath $csvPath -Destination (Join-Path $staging 'META_SYMBOLS.csv') -Force

  $pngAdded = 0
  if(-not $SkipPng){
    if(Test-Path -LiteralPath $symbolsDir){
      $pngs = Get-ChildItem -LiteralPath $symbolsDir -Filter *.png -File -ErrorAction SilentlyContinue
      if($pngs){
        $dst = Ensure-Dir (Join-Path $staging 'META_SYMBOLS')
        foreach($p in $pngs){ Copy-Item -LiteralPath $p.FullName -Destination $dst -Force; $pngAdded++ }
        Write-Info "Додано PNG: $pngAdded"
      } else { Write-Warn "У каталозі $symbolsDir немає *.png — пропущено" }
    } else { Write-Warn "Каталог PNG не знайдено: $symbolsDir — пропущено" }
  } else {
    Write-Info "SkipPng: ввімкнено — PNG-іконки пропущено"
  }

  # ---------- MANIFEST.{txt,yaml} ----------
  $manifestTxt  = Join-Path $staging 'MANIFEST.txt'
  $manifestYaml = Join-Path $staging 'MANIFEST.yaml'
  $filesRel = Get-ChildItem -Path $staging -Recurse -File | ForEach-Object {
    $_.FullName.Replace($staging + [IO.Path]::DirectorySeparatorChar, '')
  }

  $lines = @()
  $lines += "DigitalSignature: (pending SHA256)"
  $lines += "# ================================================================"
  $lines += "# META PACKAGE MANIFEST"
  $lines += "# System: CHECHA CORE / DAO-GOGS"
  $lines += "# Author: С.Ч."
  $lines += ("# Date: {0}" -f $nowLocal.ToString('yyyy-MM-dd HH:mm:ss'))
  $lines += ("# Name: {0}  Version: {1}  Stamp: {2}" -f $Name, $Version, $Stamp)
  $lines += "# ================================================================"
  $lines += ""
  $lines += "[FILES]"
  foreach($f in $filesRel){ $lines += $f }
  $lines += ""
  $lines += "[NOTES]"
  $lines += "Package of META-Revival artifacts (md + csv + png) with MANIFEST and SHA256."
  $lines += "Signature will be filled after ZIP build."
  $lines | Set-Content -LiteralPath $manifestTxt -Encoding UTF8

  $yaml = @()
  $yaml += "name: $Name"
  $yaml += "version: '$Version'"
  $yaml += "date: '$($nowLocal.ToString('yyyy-MM-ddTHH:mm:ss'))'"
  $yaml += "stamp: '$Stamp'"
  $yaml += "system: 'CHECHA CORE / DAO-GOGS'"
  $yaml += "author: 'С.Ч.'"
  $yaml += "files:"
  foreach($f in $filesRel){ $yaml += "  - '$f'" }
  $yaml += "notes: 'META package (md, csv, png) + manifest + sha256'"
  $yaml | Set-Content -LiteralPath $manifestYaml -Encoding UTF8

  # ---------- ZIP ----------
  $zipName = "{0}_{1}_{2}.zip" -f $Name, $Version, $Stamp
  $zipPath = Join-Path $c06 $zipName
  if(Test-Path -LiteralPath $zipPath){
    Write-Warn "ZIP уже існує — перезапис: $zipPath"
    Remove-Item -LiteralPath $zipPath -Force
  }
  Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -Force
  Write-Ok "ZIP створено → $zipPath"

  # ---------- SHA256 ----------
  $sha = Get-Sha256 -FilePath $zipPath
  $shaSidecar = "$zipPath.sha256"
  "$sha  $(Split-Path -Leaf $zipPath)" | Set-Content -LiteralPath $shaSidecar -Encoding ASCII
  Write-Ok "SHA256: $sha"

  # Оновимо MANIFEST.txt підписом (не в ZIP), а також збережемо копії в C06_FOCUS
  (Get-Content -LiteralPath $manifestTxt -Encoding UTF8) `
    -replace 'DigitalSignature: \(pending SHA256\)', "DigitalSignature: $sha" `
    | Set-Content -LiteralPath $manifestTxt -Encoding UTF8
  Copy-Item -LiteralPath $manifestTxt  -Destination (Join-Path $c06 ($zipName -replace '\.zip$','_MANIFEST.txt'))  -Force
  Copy-Item -LiteralPath $manifestYaml -Destination (Join-Path $c06 ($zipName -replace '\.zip$','_MANIFEST.yaml')) -Force

  # ---------- MANIFEST.json (нове) ----------
  $manifestJsonPath = Join-Path $c06 ($zipName -replace '\.zip$','_MANIFEST.json')
  $json = @{
    name    = $Name
    version = $Version
    date    = $nowLocal.ToString('yyyy-MM-ddTHH:mm:ss')
    stamp   = $Stamp
    system  = 'CHECHA CORE / DAO-GOGS'
    author  = 'С.Ч.'
    sha256  = $sha
    zip     = (Split-Path -Leaf $zipPath)
    files   = $filesRel
    notes   = 'META package (md, csv, png) + manifest + sha256 + optional gpg asc'
  }
  New-Json -obj $json -path $manifestJsonPath
  Write-Ok "MANIFEST.json створено → $manifestJsonPath"

  # ---------- Підпис ZIP (опційно) ----------
if($Sign){
  $ascPath = "$zipPath.asc"
  # Авто-видалення старого .asc, щоб не питав підтвердження
  if (Test-Path -LiteralPath $ascPath) {
    Remove-Item -LiteralPath $ascPath -Force
  }

  # Додано --yes і --batch, щоб GPG ніколи не питав
  $args = @('--yes','--batch','--armor','--detach-sign','--output',"$ascPath")
  if($KeyId){ $args += @('--local-user', $KeyId) }
  $args += @("$zipPath")

  try {
    Write-Info "Підпис ZIP через GPG…"
    $p = Start-Process -FilePath $GpgPath -ArgumentList $args -NoNewWindow -PassThru -Wait -ErrorAction Stop
    if($p.ExitCode -ne 0){ throw "GPG повернув код $($p.ExitCode)" }
    Write-Ok "Підпис створено → $ascPath"
  } catch {
    Write-Warn "Не вдалося підписати ZIP через GPG: $($_.Exception.Message)"
  }
}

  # ---------- LOG ----------
  $logCsv = Join-Path $c03 'META_Packages.csv'
  if(-not (Test-Path -LiteralPath $logCsv)){
    "Timestamp,Name,Version,Stamp,ZipPath,SizeBytes,SHA256,PNG_Count,Notes" | Set-Content -LiteralPath $logCsv -Encoding UTF8
  }
  $size = (Get-Item -LiteralPath $zipPath).Length
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $note = "Packed OK" + ($(if($Sign){"; GPG attempted"}else{""}))
  $line = ('"{0}","{1}","{2}","{3}","{4}",{5},"{6}",{7},"{8}"' -f `
    $ts, $Name, $Version, $Stamp, $zipPath, $size, $sha, $pngAdded, $note)
  Add-Content -LiteralPath $logCsv -Value $line -Encoding UTF8
  Write-Ok "Лог оновлено → $logCsv"

  # ---------- FIN ----------
  if($Open){ Invoke-Item -LiteralPath $zipPath }
  Write-Host ""
  Write-Host "Digest:" -ForegroundColor Cyan
  Write-Host "  ZIP:   $zipPath"
  Write-Host "  SHA:   $sha"
  Write-Host "  LOG:   $logCsv"
  Write-Host "  STAGE: $staging"
  Write-Host "  JSON:  $manifestJsonPath"
  exit 0

} catch {
  Write-Err $_.Exception.Message
  if($_.ScriptStackTrace){ Write-Err $_.ScriptStackTrace }
  exit 1
} finally {
  # За бажанням: прибрати staging після успіху
  # try { if(Test-Path -LiteralPath $stagingRoot){ Remove-Item -LiteralPath $stagingRoot -Recurse -Force } } catch {}
}
