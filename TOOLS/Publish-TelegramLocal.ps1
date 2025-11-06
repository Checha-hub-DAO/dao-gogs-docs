<#
.SYNOPSIS
  Локальна публікація Telegram-чернетки DAO-Academy Digest
  v1.6 — авто-пошук Telegram Desktop + копіювання в буфер + toast + DAO-G13 alert
#>

[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [switch]$OpenTelegram,
  [switch]$SendAlert
)

$ErrorActionPreference = "Stop"
$tgDir = Join-Path $Root "C03_LOG\reports\DAO_Academy\_tg"

if (-not (Test-Path $tgDir)) {
  throw "❌ Папка з Telegram-чернетками не знайдена: $tgDir"
}

# Знайти останній _tg-файл
$tgFile = Get-ChildItem -Path $tgDir -Filter 'DAO_Academy_Telegram_*.md' |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

if (-not $tgFile) {
  throw "Чернеток ще нема. Спершу запусти Publish-DAOAcademyDigest.ps1 (він створить _tg-файл)."
}

# Копіюємо у буфер
$text = Get-Content -LiteralPath $tgFile.FullName -Raw
Set-Clipboard -Value $text
Write-Host "✅ Скопійовано у буфер:" $tgFile.FullName -ForegroundColor Green

# --- [Пошук Telegram Desktop] ---
function Find-Telegram {
  $paths = @()
  if ($env:TELEGRAM_PATH) { $paths += $env:TELEGRAM_PATH }
  $paths += @(
    "$env:LOCALAPPDATA\Telegram Desktop\Telegram.exe",
    "$env:APPDATA\Telegram Desktop\Telegram.exe",
    "C:\Program Files\Telegram Desktop\Telegram.exe",
    "C:\Program Files (x86)\Telegram Desktop\Telegram.exe"
  )
  foreach ($p in $paths) { if (Test-Path $p) { return $p } }
  try {
    $cmd = (Get-Command telegram.exe -ErrorAction SilentlyContinue)
    if ($cmd) { return $cmd.Source }
  } catch {}
  return $null
}

# --- [Toast-сповіщення] ---
function Show-Toast($Title, $Message) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.BalloonTipTitle = $Title
    $notify.BalloonTipText  = $Message
    $notify.Visible = $true
    $notify.ShowBalloonTip(4000)
    Start-Sleep -Seconds 5
    $notify.Dispose()
  } catch {
    Write-Warning "Toast не вдалося показати: $($_.Exception.Message)"
  }
}

# --- [DAO-G13 alert] ---
function Send-DAOAlert($Message) {
  try {
    $tokenFile = "D:\CHECHA_CORE\C11_AUTOMATION\tokens\DAO_G13.token"
    $chatFile  = "D:\CHECHA_CORE\C11_AUTOMATION\tokens\DAO_G13.chatid"
    if (-not (Test-Path $tokenFile) -or -not (Test-Path $chatFile)) {
      Write-Warning "⚠️ Немає токена або chatid для DAO-G13. Створи файли DAO_G13.token / DAO_G13.chatid."
      return
    }
    $token = Get-Content -LiteralPath $tokenFile -Raw
    $chat  = Get-Content -LiteralPath $chatFile  -Raw
    $uri   = "https://api.telegram.org/bot$token/sendMessage"
    $body  = @{
      chat_id = $chat
      text    = $Message
      parse_mode = 'Markdown'
    }
    Invoke-RestMethod -Uri $uri -Method Post -Body $body -ErrorAction Stop | Out-Null
    Write-Host "📡 DAO-G13 alert надіслано." -ForegroundColor Green
  } catch {
    Write-Warning "❌ Не вдалося надіслати DAO-G13 alert: $($_.Exception.Message)"
  }
}

# --- [Основна логіка запуску Telegram] ---
$telegramPath = $null
if ($OpenTelegram) {
  $telegramPath = Find-Telegram
  if ($telegramPath) {
    Start-Process -FilePath $telegramPath
    Write-Host "🚀 Відкрито Telegram Desktop → встав (Ctrl+V)" -ForegroundColor Cyan
    Show-Toast "DAO-Academy Digest" "✅ Чернетка скопійована у буфер. Telegram відкрито."
  }
  else {
    Write-Warning "Не знайдено Telegram Desktop. Встав у веб/десктоп Telegram вручну (Ctrl+V)."
    Show-Toast "DAO-Academy Digest" "⚠️ Telegram не знайдено. Встав текст вручну (Ctrl+V)."
  }
}
else {
  Show-Toast "DAO-Academy Digest" "✅ Чернетка скопійована у буфер. Telegram не відкривався."
}

if ($SendAlert) {
  $msg = "📘 *DAO-Academy Digest* опубліковано.`nФайл: `$($tgFile.Name)`nСтатус: ✅ Успішно."
  Send-DAOAlert $msg
}

Write-Host "`n=== Telegram Publish Summary ==="
Write-Host "File: $($tgFile.FullName)"
Write-Host "OpenTelegram: $OpenTelegram"
Write-Host "SendAlert: $SendAlert"
Write-Host "Status: OK"
