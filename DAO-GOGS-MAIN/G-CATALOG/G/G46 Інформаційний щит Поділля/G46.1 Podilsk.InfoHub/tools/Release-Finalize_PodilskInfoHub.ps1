<# 
.SYNOPSIS
  Готує реліз Podilsk.InfoHub: валідація структури, упаковка в ZIP, SHA256, оновлення CHANGELOG, git-тег.

.EXAMPLE
  .\Release-Finalize_PodilskInfoHub.ps1 -Root "D:\CHECHA_CORE\G46-Podilsk.InfoHub" -Version "v1.0"

.PARAMETER Root
  Корінь модуля (де лежать README.md, /media-kit, /content, /contacts, /archive).

.PARAMETER Version
  Семвер/тег релізу (напр. v1.0, v1.1).

.PARAMETER OutDir
  Куди покласти ZIP та SHA256. За замовчуванням: "<Root>\Release".

.PARAMETER NoGitTag
  Не створювати git-тег (за замовчуванням створює, якщо git доступний і в repo).

.PARAMETER Force
  Продовжити при non-blocking warning'ах (менше 5 контентів тощо).
#>
param(
  [Parameter(Mandatory)][string]$Root,
  [Parameter(Mandatory)][string]$Version,
  [string]$OutDir,
  [switch]$NoGitTag,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Info($m){ Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host "✅ $m" -ForegroundColor Green }
function Write-Warn($m){ Write-Host "⚠️  $m" -ForegroundColor Yellow }
function Write-Err($m){ Write-Host "❌ $m" -ForegroundColor Red }

# --- Normalize paths
$Root    = (Resolve-Path $Root).Path
$OutDir  = if ($OutDir) { $OutDir } else { Join-Path $Root 'Release' }
$stamp   = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')

# --- Pre-flight checks
$mustFiles = @("README.md","CHANGELOG.md")
$mustDirs  = @("media-kit","content","contacts","archive")

foreach($f in $mustFiles){
  if(-not (Test-Path (Join-Path $Root $f))){ Write-Err "Відсутній файл: $f"; throw "Missing $f" }
}
foreach($d in $mustDirs){
  if(-not (Test-Path (Join-Path $Root $d))){ Write-Err "Відсутня текa: $d"; throw "Missing dir $d" }
}

$mediaReq = @("logo.svg","banner-1200x400.png")
foreach($m in $mediaReq){
  $p = Join-Path $Root "media-kit\$m"
  if(-not (Test-Path $p)){ Write-Warn "У MediaKit немає $m" }
}

$contentDir = Join-Path $Root "content"
$contentCount = (Get-ChildItem $contentDir -File -Include *.md | Measure-Object).Count
if($contentCount -lt 5){
  $msg = "У content < 5 матеріалів ($contentCount). Рекомендовано ≥5."
  if($Force){ Write-Warn $msg } else { Write-Err $msg; throw "Not enough content" }
}

# --- Prepare Release dir
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stage = Join-Path $OutDir "stage_$stamp"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Info "Копіюю структуру в stage…"
$include = @("README.md","CHANGELOG.md","media-kit","content","contacts","archive")
foreach($i in $include){
  $src = Join-Path $Root $i
  if(Test-Path $src){
    Copy-Item $src -Destination $stage -Recurse -Force
  }
}

# --- Generate CHECKSUMS.txt
Write-Info "Формую CHECKSUMS.txt (SHA256)…"
$checksums = Join-Path $stage "CHECKSUMS.txt"
Remove-Item $checksums -ErrorAction SilentlyContinue
Get-ChildItem $stage -Recurse -File | ForEach-Object {
  $h = Get-FileHash $_.FullName -Algorithm SHA256
  '{0} *{1}' -f $h.Hash, ($_.FullName.Substring($stage.Length+1)) | Out-File -FilePath $checksums -Append -Encoding UTF8
}

# --- Create ZIP
$zipName = "G46_Podilsk.InfoHub_${Version}_$stamp.zip"
$zipPath = Join-Path $OutDir $zipName
Write-Info "Створюю ZIP: $zipPath"
if(Test-Path $zipPath){ Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force

# --- Write .sha256
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
$shaPath = "$zipPath.sha256"
$zipHash | Out-File -FilePath $shaPath -Encoding ASCII
Write-Ok "ZIP готово. SHA256: $zipHash"

# --- Update CHANGELOG.md
$changelog = Join-Path $Root "CHANGELOG.md"
$dateStr = (Get-Date).ToString('yyyy-MM-dd')
$entry = "`n$dateStr — $Version — release package ($zipName)`n"
Add-Content -Path $changelog -Value $entry
Write-Ok "CHANGELOG оновлено: +$Version"

# --- Optional git tag
function Test-IsGitRepo([string]$path){
  try{
    $old = Get-Location
    Set-Location $path
    git rev-parse --is-inside-work-tree *>$null 2>&1
    $rc = $LASTEXITCODE
    Set-Location $old
    return ($rc -eq 0)
  } catch { return $false }
}

if(-not $NoGitTag){
  if(Test-IsGitRepo $Root){
    Write-Info "Git: додаю файли, комічу CHANGELOG, створюю тег $Version…"
    Push-Location $Root
    git add -A
    git commit -m "chore(release): $Version (build $stamp)" *>$null 2>&1
    git tag -a $Version -m "Podilsk.InfoHub $Version ($dateStr)" *>$null 2>&1
    Write-Ok "Git-тег створено: $Version"
    Pop-Location
  } else {
    Write-Warn "Не git-репозиторій. Пропускаю тегування."
  }
}

# --- Cleanup stage
Remove-Item $stage -Recurse -Force

Write-Ok "Реліз завершено:
 ZIP:    $zipPath
 SHA256: $shaPath
 CHANGELOG: $changelog
"
