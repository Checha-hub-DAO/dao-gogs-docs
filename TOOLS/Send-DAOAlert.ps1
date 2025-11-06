#requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Message,
  [string]$Tag = "SYSTEM",
  [string]$Attach,                 # шлях до файлу-вкладення (опційно)
  [switch]$Silent,
  [switch]$DisableNotification      # тихе доставлення в Telegram
)

$ErrorActionPreference = "Stop"
$Root      = "D:\CHECHA_CORE"
$TokenDir  = Join-Path $Root "C11_AUTOMATION\tokens"
$TokenFile = Join-Path $TokenDir "DAO_G13.token"
$ChatFile  = Join-Path $TokenDir "DAO_G13.chatid"

# --- Ініціалізація директорії й шаблонів ---
if (-not (Test-Path $TokenDir)) {
  New-Item -ItemType Directory -Force -Path $TokenDir | Out-Null
}

$needInit = $false
if (-not (Test-Path $TokenFile)) {
@"
# === DAO-G13 TOKEN ===
# Встав сюди токен Telegram-бота від @BotFather
# Формат: 1234567890:AAH3dYjexample_token_here
"@ | Set-Content -LiteralPath $TokenFile -Encoding UTF8
  Write-Warning "⚠️ Створено шаблон DAO_G13.token — заповни токен."
  $needInit = $true
}
if (-not (Test-Path $ChatFile)) {
@"
# === DAO-G13 CHAT ID ===
# Встав сюди ID чату/каналу/групи
# Формат: -1009876543210
"@ | Set-Content -LiteralPath $ChatFile -Encoding UTF8
  Write-Warning "⚠️ Створено шаблон DAO_G13.chatid — заповни chat_id."
  $needInit = $true
}
if ($needInit) {
  Write-Host "`nЗаповни файли та повтори запуск:`n  $TokenFile`n  $ChatFile"
  exit 1
}

# --- Безпечне читання ---
function Read-FirstValue([string]$Path) {
  if (-not (Test-Path $Path)) { return "" }
  $content = Get-Content -LiteralPath $Path -Raw
  $line = ($content -split "`r?`n" | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Select-Object -First 1)
  if ($null -eq $line) { return "" }
  return $line.Trim()
}

$Token = Read-FirstValue $TokenFile
$Chat  = Read-FirstValue $ChatFile

# --- Валідація ---
$TokenOk = ($Token -match '^\d{6,}:[A-Za-z0-9_\-]{20,}$')
$ChatOk  = ($Chat  -match '^-?\d+$')

if (-not $TokenOk -or -not $ChatOk) {
  Write-Host "`nНекоректний токен або chat_id."
  if (-not $TokenOk) { Write-Host "Очікуваний формат токена: 1234567890:AA..." }
  if (-not $ChatOk)  { Write-Host "Очікуваний формат chat_id: -100XXXXXXXXXX" }
  throw "DAO-G13 validation failed"   # <— тепер кидаємо помилку, щоб викликальник міг зловити
}

# --- Повідомлення ---
$HostName  = $env:COMPUTERNAME
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Header = @"
📡 *DAO-G13 System Alert*
🧩 *Tag:* $Tag
💬 *Message:* $Message
🕓 *Time:* $Timestamp
💻 *Host:* $HostName
"@

# --- Відправлення: або sendDocument (з вкладенням), або sendMessage ---
try {
  if ($Attach) {
    if (-not (Test-Path -LiteralPath $Attach)) {
      throw "Файл-вкладення не знайдено: $Attach"
    }

    $uri = "https://api.telegram.org/bot$Token/sendDocument"
    # caption у Telegram має обмеження довжини; беремо перші ~950 символів
    $caption = if ($Header.Length -gt 950) { $Header.Substring(0,950) } else { $Header }

    $form = @{
      chat_id = $Chat
      caption = $caption
      parse_mode = 'Markdown'
      disable_notification = [bool]$DisableNotification
      document = Get-Item -LiteralPath $Attach
    }
    Invoke-RestMethod -Uri $uri -Method Post -Form $form -ErrorAction Stop | Out-Null
    if (-not $Silent) { Write-Host "📎 Надіслано документ: $Attach" -ForegroundColor Green }
  }
  else {
    $uri = "https://api.telegram.org/bot$Token/sendMessage"
    $body = @{
      chat_id = $Chat
      text    = $Header
      parse_mode = 'Markdown'
      disable_notification = [bool]$DisableNotification
    }
    Invoke-RestMethod -Uri $uri -Method Post -Body $body -ErrorAction Stop | Out-Null
    if (-not $Silent) { Write-Host "✅ Повідомлення надіслано ($Tag)" -ForegroundColor Green }
  }
}
catch {
  Write-Warning "❌ Не вдалося надіслати: $($_.Exception.Message)"
  exit 1
}
