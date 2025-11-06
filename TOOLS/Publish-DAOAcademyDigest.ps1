#requires -Version 5.1
<#
.SYNOPSIS
  Публікація DAO-Academy Digest (G29) у GitBook-структуру + Telegram-чернетка.
  v1.3.1 — коректний статус DAO-G13 alert (OK лише при успіху), стабільні Git/NoGit.

.PARAMETER Root
  Корінь CheCha Core. За замовчуванням: D:\CHECHA_CORE

.PARAMETER RepoPath
  Шлях до локальної копії репозиторію dao-g (для GitBook-структури).
  За замовчуванням: $Root\dao-g

.PARAMETER GitbookDir
  Відносний шлях у repo для розділу дайджесту.
  За замовчуванням: "dao-gid\g29-dao-academy\digest"

.PARAMETER DigestPath
  Необов'язково: шлях до вже згенерованого дайджесту (.md).
  Якщо не задано — береться останній "DAO_Academy_Digest_*.md" із $Root\C03_LOG\reports\DAO_Academy

.PARAMETER NoGit
  Якщо вказано — не торкаємось Git; копіюємо у LOCAL_PUBLISH\<GitbookDir>.

.PARAMETER Push
  Якщо вказано — git add/commit/push (ігнорується при -NoGit).

.PARAMETER SendAlert
  Якщо вказано — виклик Send-DAOAlert.ps1 (шле повідомлення у DAO-канал із вкладенням дайджесту).

.EXAMPLE
  pwsh -NoProfile -File "D:\CHECHA_CORE\TOOLS\Publish-DAOAcademyDigest.ps1" -Root D:\CHECHA_CORE -NoGit -SendAlert
#>

[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string]$RepoPath = $(Join-Path $Root "dao-g"),
  [string]$GitbookDir = "dao-gid\g29-dao-academy\digest",
  [string]$DigestPath,
  [switch]$NoGit,
  [switch]$Push,
  [switch]$SendAlert
)

$ErrorActionPreference = "Stop"

# --- Paths
$ReportsDir   = Join-Path $Root "C03_LOG\reports\DAO_Academy"
$LocalPublish = Join-Path $RepoPath "LOCAL_PUBLISH"
$GitbookAbs   = if ($NoGit) { Join-Path $LocalPublish $GitbookDir } else { Join-Path $RepoPath $GitbookDir }
$AlertTool    = Join-Path $Root "TOOLS\Send-DAOAlert.ps1"

# --- Ensure dirs
foreach($p in @($ReportsDir,$GitbookAbs)) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# --- Resolve digest file
if (-not $DigestPath) {
  $latest = Get-ChildItem -Path $ReportsDir -Filter "DAO_Academy_Digest_*.md" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { throw "❌ Не знайдено DAO_Academy_Digest_*.md у $ReportsDir. Спочатку запусти Build-DAOAcademyDigest.ps1." }
  $DigestPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $DigestPath)) { throw "❌ Не знайдено файл дайджесту: $DigestPath" }

# --- Names
$monthTag    = [System.IO.Path]::GetFileNameWithoutExtension($DigestPath) -replace '^DAO_Academy_Digest_',''
$gitbookFile = Join-Path $GitbookAbs ("G29_Digest_{0}.md" -f $monthTag)

# --- Copy to GitBook structure
Copy-Item -LiteralPath $DigestPath -Destination $gitbookFile -Force
Write-Host "[OK] Скопійовано Digest -> $gitbookFile"

# --- Telegram draft
$TgDir = Join-Path $ReportsDir "_tg"
if (-not (Test-Path $TgDir)) { New-Item -ItemType Directory -Path $TgDir -Force | Out-Null }
$tgFile    = Join-Path $TgDir ("DAO_Academy_Telegram_{0}.md" -f $monthTag)
$monthName = (Get-Culture).DateTimeFormat.GetMonthName(([datetime]::ParseExact("$monthTag-01","yyyy-MM-dd",$null)).Month)

$tgText = @"
📘 *DAO-Academy Digest — $monthName*  
Файл: `$([System.IO.Path]::GetFileName($gitbookFile))

Ключові підсумки:
— Курси / наставництво / сертифікація (деталі в дайджесті)
— KPI/індекси — див. таблицю в документі

#G29 #DAOAcademy
"@
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tgFile, $tgText, $utf8)
Write-Host "[OK] Чернетка Telegram -> $tgFile"

# --- Git flow (if not NoGit)
if (-not $NoGit) {
  if (-not (Test-Path $RepoPath)) { throw "❌ Не знайдено Git-репозиторій: $RepoPath" }
  Push-Location $RepoPath
  try {
    git add --all | Out-Null
    $msg = "G29: Digest $monthTag"
    git commit -m $msg | Out-Null
    if ($Push) {
      git push | Out-Null
      Write-Host "[OK] Git push виконано."
    } else {
      Write-Host "[OK] Git commit виконано (без push)."
    }
  } catch {
    Write-Warning "⚠️ Git-операції не вдалися: $($_.Exception.Message)"
  } finally {
    Pop-Location
  }
} else {
  Write-Host "[OK] Локальна публікація (NoGit): $gitbookFile"
}

# --- Optional: DAO-G13 alert with attachment
if ($SendAlert) {
  if (-not (Test-Path $AlertTool)) {
    Write-Warning "⚠️ Не знайдено $AlertTool — пропускаю Send-DAOAlert."
  } else {
    $msg = "📘 DAO-Academy Digest опубліковано ($monthTag)"
    try {
      & $AlertTool -Message $msg -Tag "G29" -Attach $DigestPath
      if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Warning "⚠️ DAO-G13 alert завершився з кодом $LASTEXITCODE."
      } else {
        Write-Host "[OK] Надіслано DAO-G13 alert із вкладенням."
      }
    } catch {
      Write-Warning "❌ Не вдалося надіслати DAO-G13 alert: $($_.Exception.Message)"
    }
  }
}

# --- Summary
Write-Host "`n=== Publish Summary ==="
Write-Host "Digest:   $DigestPath"
Write-Host "GitBook:  $gitbookFile"
Write-Host "Telegram: $tgFile"
Write-Host ("Git push: {0}" -f ($(if ($NoGit) {'(off)'} elseif ($Push) {'on'} else {'(off)'})))
