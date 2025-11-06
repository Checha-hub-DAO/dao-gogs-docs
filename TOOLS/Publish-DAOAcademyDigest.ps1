#requires -Version 5.1
<#
.SYNOPSIS
  Публікація DAO-Academy Digest (G29) у локальну GitBook-структуру + підготовка Telegram-чернетки.
  v1.3 — інтеграція з Send-DAOAlert.ps1 (опційне надсилання повідомлення/вкладення у DAO-чат).

.PARAMETER Root
  Корінь CheCha Core. За замовчуванням: D:\CHECHA_CORE

.PARAMETER RepoPath
  Шлях до локальної копії репозиторію dao-g (для GitBook-структури). За замовчуванням: $Root\dao-g

.PARAMETER GitbookDir
  Відносний шлях усередині repo для GitBook розділу дайджесту.
  За замовчуванням: "dao-gid\g29-dao-academy\digest"

.PARAMETER DigestPath
  Необов'язково: шлях до вже згенерованого дайджесту (.md).
  Якщо не задано — візьме останній "DAO_Academy_Digest_*.md" із $Root\C03_LOG\reports\DAO_Academy

.PARAMETER NoGit
  Якщо вказано — не перевіряє repo і просто копіює у LOCAL_PUBLISH\<GitbookDir>.

.PARAMETER Push
  Якщо вказано — виконує git add/commit/push (за умови, що RepoPath валідний). Ігнорується при -NoGit.

.PARAMETER SendAlert
  Якщо вказано — викликає Send-DAOAlert.ps1 для надсилання повідомлення в DAO-канал (із вкладенням дайджесту).

.EXAMPLE
  pwsh -NoProfile -File "$env:CHECHA_ROOT\TOOLS\Publish-DAOAcademyDigest.ps1" -Root D:\CHECHA_CORE -NoGit -SendAlert

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

# --- Шляхи
$ReportsDir = Join-Path $Root "C03_LOG\reports\DAO_Academy"
$LocalPublish = Join-Path $RepoPath "LOCAL_PUBLISH"
$GitbookAbs = if ($NoGit) {
  Join-Path $LocalPublish $GitbookDir
} else {
  Join-Path $RepoPath $GitbookDir
}
$AlertTool = Join-Path $Root "TOOLS\Send-DAOAlert.ps1"

# --- Переконаймося, що є директрії призначення
foreach($p in @($ReportsDir,$GitbookAbs)) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# --- Визначити файл дайджесту
if (-not $DigestPath) {
  $latest = Get-ChildItem -Path $ReportsDir -Filter "DAO_Academy_Digest_*.md" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) {
    throw "❌ Не знайдено DAO_Academy_Digest_*.md у $ReportsDir. Спочатку запусти Build-DAOAcademyDigest.ps1."
  }
  $DigestPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $DigestPath)) {
  throw "❌ Не знайдено файл дайджесту: $DigestPath"
}

# --- Ім'я для GitBook-копії
$monthTag = [System.IO.Path]::GetFileNameWithoutExtension($DigestPath) -replace '^DAO_Academy_Digest_',''
$gitbookFile = Join-Path $GitbookAbs ("G29_Digest_{0}.md" -f $monthTag)

# --- Копіювання у GitBook-структуру
Copy-Item -LiteralPath $DigestPath -Destination $gitbookFile -Force
Write-Host "[OK] Скопійовано Digest -> $gitbookFile"

# --- Telegram-чернетка
$TgDir = Join-Path $ReportsDir "_tg"
if (-not (Test-Path $TgDir)) { New-Item -ItemType Directory -Path $TgDir -Force | Out-Null }

$tgFile = Join-Path $TgDir ("DAO_Academy_Telegram_{0}.md" -f $monthTag)
$monthName = (Get-Culture).DateTimeFormat.GetMonthName(([datetime]::ParseExact("$monthTag-01","yyyy-MM-dd",$null)).Month)

$tgText = @"
📘 *DAO-Academy Digest — $monthName*  
Файл: `$([System.IO.Path]::GetFileName($gitbookFile))

Ключові підсумки:
— Курси / наставництво / сертифікація (деталі в дайджесті)
— Показники та індекси — у розділі KPI

#G29 #DAOAcademy
"@
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tgFile, $tgText, $utf8)
Write-Host "[OK] Чернетка Telegram -> $tgFile"

# --- Git-операції (якщо не NoGit)
if (-not $NoGit) {
  if (-not (Test-Path $RepoPath)) {
    throw "❌ Не знайдено Git-репозиторій: $RepoPath"
  }
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
    Write-Warning "⚠️ Git-дії не вдалися: $($_.Exception.Message)"
  } finally {
    Pop-Location
  }
} else {
  Write-Host "[OK] Локальна публікація (NoGit): $gitbookFile"
}

# --- Опційне повідомлення в DAO-канал (із вкладенням)
if ($SendAlert) {
  if (-not (Test-Path $AlertTool)) {
    Write-Warning "⚠️ Не знайдено $AlertTool — пропускаю Send-DAOAlert."
  } else {
    $msg = "📘 DAO-Academy Digest опубліковано ($monthTag)"
    try {
      # Перевага: надсилаємо саме дайджест як документ (читабельно в TG)
      & $AlertTool -Message $msg -Tag "G29" -Attach $DigestPath | Out-Null
      Write-Host "[OK] Надіслано DAO-G13 alert із вкладенням."
    } catch {
      Write-Warning "❌ Не вдалося надіслати DAO-G13 alert: $($_.Exception.Message)"
    }
  }
}

# --- Звіт
Write-Host "`n=== Publish Summary ==="
Write-Host "Digest:   $DigestPath"
Write-Host "GitBook:  $gitbookFile"
Write-Host "Telegram: $tgFile"
Write-Host ("Git push: {0}" -f ($(if ($NoGit) {'(off)'} elseif ($Push) {'on'} else {'(off)'})))
