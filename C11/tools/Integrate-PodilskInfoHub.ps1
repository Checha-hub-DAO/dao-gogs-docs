<# 
.SYNOPSIS
  Integrate G46.1 Podilsk.InfoHub package (README.md + CHANGELOG.md) into repo.

.DESCRIPTION
  - Unzips package to target dir (non-ASCII paths supported).
  - Optionally validates SHA-256 of the ZIP.
  - Performs git add/commit/push from RepoRoot.
  - Safe by default: supports -DryRun and -SkipPush.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File `
    .\Integrate-PodilskInfoHub.ps1 `
    -ZipPath 'C:\Users\serge\Downloads\G46.1_Podilsk_InfoHub_Package.zip' `
    -RepoRoot 'D:\DAO_GOGS' `
    -TargetDir 'D:\DAO_GOGS\G-CATALOG\G\G46 Інформаційний щит Поділля\G46.1 Podilsk.InfoHub' `
    -CommitMessage 'G46.1 Podilsk.InfoHub — integrate README + CHANGELOG package' `
    -Verbose
#>

[CmdletBinding()]
param(
  # Шлях до ZIP-пакета з README.md + CHANGELOG.md
  [Parameter(Mandatory=$true)]
  [ValidateScript({ Test-Path $_ -PathType Leaf })]
  [string]$ZipPath,

  # Корінь git-репозиторію
  [Parameter(Mandatory=$true)]
  [ValidateScript({ Test-Path $_ -PathType Container })]
  [string]$RepoRoot,

  # Кінцева папка модуля (куди розпаковувати)
  [Parameter(Mandatory=$true)]
  [string]$TargetDir,

  # (Опціонально) Очікуваний SHA256 ZIP-а
  [Parameter(Mandatory=$false)]
  [string]$ExpectedSha256,

  # Текст коміту
  [Parameter(Mandatory=$false)]
  [string]$CommitMessage = "G46.1 Podilsk.InfoHub — integrate README + CHANGELOG package",

  # Не виконувати push
  [switch]$SkipPush,

  # Сухий прогін (нічого не змінює на диску/в репозиторії)
  [switch]$DryRun
)

function Step($m){ Write-Host "🔧 $m" -ForegroundColor Cyan }
function OK($m){ Write-Host "✅ $m" -ForegroundColor Green }
function Warn($m){ Write-Host "⚠️  $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "❌ $m" -ForegroundColor Red }

$ErrorActionPreference = 'Stop'

# 1) Перевірки довкілля
Step "Перевірка довкілля…"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git не знайдено у PATH" }
$repo = (Resolve-Path $RepoRoot).Path
$zip  = (Resolve-Path $ZipPath).Path

# 2) Перевірка SHA256 (якщо вказано)
if ($ExpectedSha256) {
  Step "Перевірка SHA256 ZIP…"
  $actual = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToUpper()
  if ($actual -ne $ExpectedSha256.ToUpper()) {
    throw "Hash mismatch: expected $ExpectedSha256, got $actual"
  }
  OK "SHA256 валідний."
} else {
  Warn "ExpectedSha256 не задано — перевірку пропущено."
}

# 3) Підготовка цільової папки
Step "Підготовка TargetDir…"
if (-not (Test-Path $TargetDir)) {
  if ($DryRun) { Warn "DryRun: створення каталогу пропущено → $TargetDir" }
  else { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }
}
$target = (Resolve-Path $TargetDir).Path
OK "TargetDir: $target"

# 4) Розпакування ZIP
Step "Розпакування ZIP у TargetDir…"
if (-not $DryRun) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  # Force overwrite = true
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $target, $true)
} else {
  Warn "DryRun: розпакування пропущено."
}
OK "Розпаковано (або DryRun)."

# 5) Перевірка наявності файлів
$readme = Join-Path $target 'README.md'
$chlog  = Join-Path $target 'CHANGELOG.md'
if (-not (Test-Path $readme)) { throw "README.md не знайдено після розпакування!" }
if (-not (Test-Path $chlog))  { throw "CHANGELOG.md не знайдено після розпакування!" }
OK "README.md та CHANGELOG.md — на місці."

# 6) git add/commit/push
Step "git add…"
$relReadme = $readme.Replace($repo, '').TrimStart('\','/')
$relChlog  = $chlog.Replace($repo, '').TrimStart('\','/')

if (-not $DryRun) {
  git -C $repo add -- "$relReadme" "$relChlog"
} else {
  Warn "DryRun: git add пропущено ($relReadme, $relChlog)"
}

Step "git commit…"
if (-not $DryRun) {
  # Якщо немає змін — git поверне ненульовий код. Обробимо м’яко.
  try {
    git -C $repo commit -m $CommitMessage | Out-Null
    OK "Коміт створено."
  } catch {
    Warn "Ймовірно немає змін для коміту. Продовжую."
  }
} else {
  Warn "DryRun: commit пропущено."
}

if (-not $SkipPush) {
  Step "git push…"
  if (-not $DryRun) {
    git -C $repo push | Out-Null
    OK "Push виконано."
  } else {
    Warn "DryRun: push пропущено."
  }
} else {
  Warn "SkipPush: push пропущено."
}

OK "ІНТЕГРАЦІЮ ЗАВЕРШЕНО."
Write-Host "👉 Перевір GitBook синхронізацію сторінки G46.1 після push." -ForegroundColor Magenta
