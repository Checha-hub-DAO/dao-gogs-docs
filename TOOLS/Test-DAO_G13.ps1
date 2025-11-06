#requires -Version 5.1
<#
.SYNOPSIS
  Повна перевірка Telegram-бота DAO-G13: getMe -> getChat -> sendMessage (з інтерактивним режимом).
.DESCRIPTION
  - Читає токен/chat_id із CheCha Core (tokens) або приймає через параметри.
  - Режим -Interactive: запитує токен і канал (@name), сам зберігає у tokens.
  - Перевіряє токен (getMe), дістає chat_id через getChat (за -Channel або введеним @name),
    надсилає тест (sendMessage), все логуючи у C03_LOG\reports\DAO_G13\Test_<timestamp>.log.
.PARAMETER Token
  Токен Telegram-бота (альтернатива файлу tokens\DAO_G13.token).
.PARAMETER ChatId
  Цільовий chat_id (наприклад, -1001234567890). Альтернатива -Channel.
.PARAMETER Channel
  Публічний @username каналу/групи для отримання numeric chat_id через getChat.
.PARAMETER Message
  Текст тестового повідомлення (HTML).
.PARAMETER Root
  Корінь CheCha Core. За замовчуванням: D:\CHECHA_CORE
.PARAMETER SaveChatId
  Зберегти отриманий chat_id у tokens\DAO_G13.chatid.
.PARAMETER NoSend
  Не надсилати тестове повідомлення (лише getMe/getChat).
.PARAMETER Interactive
  Інтерактивно запитати відсутні Token/Channel, зберегти у tokens та виконати повний тест.
.EXAMPLE
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Test-DAO_G13.ps1 -Interactive
.EXAMPLE
  pwsh -NoProfile -File D:\CHECHA_CORE\TOOLS\Test-DAO_G13.ps1 -Channel "@gogsdao" -SaveChatId
.EXAMPLE
  .\Test-DAO_G13.ps1 -ChatId -1002123456789 -Message "<b>DAO-G13</b> тест ✅"
#>

[CmdletBinding()]
param(
  [string]$Token,
  [string]$ChatId,
  [string]$Channel,
  [string]$Message = "✅ DAO-G13 тестове повідомлення",
  [string]$Root = "D:\CHECHA_CORE",
  [switch]$SaveChatId,
  [switch]$NoSend,
  [switch]$Interactive
)

$ErrorActionPreference = "Stop"

# --- Paths
$tokenDir  = Join-Path $Root "C11_AUTOMATION\tokens"
$tokenFile = Join-Path $tokenDir "DAO_G13.token"
$chatFile  = Join-Path $tokenDir "DAO_G13.chatid"
$logDir    = Join-Path $Root "C03_LOG\reports\DAO_G13"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$ts        = (Get-Date -Format "yyyyMMdd_HHmmss")
$logFile   = Join-Path $logDir "Test_$ts.log"

# --- Logger
function Write-Log { param([string]$Text)
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
  $line | Tee-Object -FilePath $logFile -Append
}

Write-Log "=== Test-DAO_G13 START (v1.2) ==="

# --- Helpers
function Read-FirstValue([string]$Path){
  if (-not (Test-Path $Path)) { return "" }
  $content = Get-Content -LiteralPath $Path -Raw
  $line = $content -split "`r?`n" | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Select-Object -First 1
  if ($null -eq $line) { return "" }
  return $line.Trim()
}

function Mask-Token([string]$t){
  if (-not $t) { return "" }
  if ($t.Length -le 10) { return "****" }
  return ($t.Substring(0,6) + "..." + $t.Substring($t.Length-4,4))
}

# --- Interactive bootstrap
if ($Interactive) {
  if (-not (Test-Path $tokenDir)) { New-Item -ItemType Directory -Path $tokenDir -Force | Out-Null }

  if (-not $Token) {
    $Token = Read-FirstValue $tokenFile
  }
  if (-not $Token) {
    Write-Host "Введи токен бота (формат 1234567890:AA...):" -ForegroundColor Yellow
    $Token = Read-Host "Token"
    if ($Token) {
      Set-Content -LiteralPath $tokenFile -Value $Token -Encoding UTF8
      Write-Log ("💾 Збережено токен у {0} ({1})" -f $tokenFile, (Mask-Token $Token))
    }
  }

  if (-not $ChatId -and -not $Channel) {
    $existingChat = Read-FirstValue $chatFile
    if ($existingChat) {
      $ChatId = $existingChat
      Write-Log "📎 Знайдено chat_id у tokens: $ChatId"
    } else {
      Write-Host "Введи канал (як @username) або натисни Enter, щоб ввести numeric chat_id:" -ForegroundColor Yellow
      $inputChannel = Read-Host "Channel (@name)"
      if ($inputChannel) {
        if ($inputChannel -notmatch '^@') { $inputChannel = '@' + $inputChannel }
        $Channel = $inputChannel
      } else {
        $ChatId = Read-Host "chat_id (наприклад -1002123456789)"
      }
    }
  }

  # за промовчанням — зберігати chat_id, якщо отримаємо
  if (-not $SaveChatId) { $SaveChatId = $true }
}

# --- Token
if (-not $Token) { $Token = Read-FirstValue $tokenFile }
if (-not $Token) {
  Write-Log "❌ Токен не знайдено (ні параметра -Token, ні значення в $tokenFile)."
  throw "Вкажи -Token або заповни $tokenFile"
}
if ($Token -notmatch '^\d{6,}:[A-Za-z0-9_\-]{20,}$') {
  Write-Log "❌ Формат токена некоректний."
  throw "Очікуваний формат: 1234567890:AA..."
}
Write-Log ("🔐 Token: OK ({0})" -f (Mask-Token $Token))

# --- getMe
try {
  $me = Invoke-RestMethod "https://api.telegram.org/bot$Token/getMe"
  if (-not $me.ok) { throw "getMe -> ok:false" }
  Write-Log ("🤖 getMe: OK | {0} (@{1}) id={2}" -f $me.result.first_name, $me.result.username, $me.result.id)
} catch {
  Write-Log "❌ getMe error: $($_.Exception.Message)"
  throw
}

# --- Channel → ChatId
if (-not $ChatId -and $Channel) {
  try {
    $chat = Invoke-RestMethod "https://api.telegram.org/bot$Token/getChat?chat_id=$Channel"
    if (-not $chat.ok) { throw "getChat(@) -> ok:false" }
    $ChatId = $chat.result.id
    Write-Log ("📌 getChat(@): OK | chat_id={0} title='{1}'" -f $ChatId, $chat.result.title)
    if ($SaveChatId) {
      if (-not (Test-Path $tokenDir)) { New-Item -ItemType Directory -Path $tokenDir -Force | Out-Null }
      Set-Content -LiteralPath $chatFile -Value $ChatId -Encoding UTF8
      Write-Log "💾 Збережено chat_id у tokens\DAO_G13.chatid"
    }
  } catch {
    Write-Log "❌ getChat(@$Channel) error: $($_.Exception.Message)"
    Write-Log "ℹ️ Додай бота у канал адміністратором з правом 'Публікувати повідомлення'."
    throw
  }
}

# --- ChatId (файл → параметр)
if (-not $ChatId) {
  $ChatId = Read-FirstValue $chatFile
  if ($ChatId) { Write-Log "📎 ChatId з tokens: $ChatId" }
}

if (-not $ChatId) {
  Write-Log "❌ Немає ChatId. Вкажи -ChatId або -Channel '@username' (і додай бота у канал)."
  throw "Немає chat_id для відправки"
}
if ($ChatId -notmatch '^-?\d+$') {
  Write-Log "❌ ChatId має бути числом (зазвичай -100XXXXXXXXXXXX)."
  throw "Некоректний chat_id"
}

# --- sendMessage
if (-not $NoSend) {
  try {
    $body = @{
      chat_id = $ChatId
      text    = $Message
      parse_mode = "HTML"
      disable_web_page_preview = $true
    }
    $resp = Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$Token/sendMessage" -Body $body
    if (-not $resp.ok) { throw "sendMessage -> ok:false" }
    Write-Log "✉️ sendMessage: OK (message_id=$($resp.result.message_id))"
  } catch {
    Write-Log "❌ sendMessage error: $($_.Exception.Message)"
    Write-Log "ℹ️ Переконайся, що бот доданий у канал/групу і має право публікувати."
    throw
  }
} else {
  Write-Log "⏭ NoSend: пропускаю sendMessage (перевірено лише getMe/getChat)."
}

Write-Log "=== Test-DAO_G13 DONE ==="
Write-Host "`n✅ Перевірку завершено. Лог: $logFile"
exit 0
