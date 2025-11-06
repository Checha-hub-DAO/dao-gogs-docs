#requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Message,

  [ValidateSet('INFO','SUCCESS','WARN','ERROR')]
  [string]$Level = 'INFO',

  [string]$Tag = 'SYSTEM',

  # Режими відправки
  [string]$File,      # шлях до файлу-вкладення (sendDocument)
  [string]$Photo,     # шлях до зображення (sendPhoto)
  [string]$Chat,      # альтернативно: @username каналу/групи

  # Поведінка
  [ValidateSet('Markdown','HTML')]
  [string]$ParseMode = 'Markdown',
  [switch]$DisableNotification,
  [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$Root      = 'D:\CHECHA_CORE'
$TokenDir  = Join-Path $Root 'C11_AUTOMATION\tokens'
$TokenFile = Join-Path $TokenDir 'DAO_G13.token'
$ChatFile  = Join-Path $TokenDir 'DAO_G13.chatid'

# ─── Utilities ────────────────────────────────────────────────────────────────
function Read-FirstValue([string]$Path){
  if (-not (Test-Path $Path)) { return '' }
  $content = Get-Content -LiteralPath $Path -Raw
  $line = $content -split "`r?`n" | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Select-Object -First 1
  if ($null -eq $line) { return '' }
  return $line.Trim()
}
function Mask-Token([string]$t){
  if (-not $t) { return '' }
  if ($t.Length -le 10) { return '****' }
  return ($t.Substring(0,6) + '...' + $t.Substring($t.Length-4,4))
}
function Get-LevelEmoji([string]$lvl){
  switch ($lvl) {
    'SUCCESS' { '✅' }
    'WARN'    { '⚠️' }
    'ERROR'   { '❌' }
    default   { 'ℹ️' }
  }
}
function Build-Header([string]$lvl,[string]$tag,[string]$msg){
  $HostName = $env:COMPUTERNAME
  $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $e    = Get-LevelEmoji $lvl
  @"
$e *DAO-G13 System Alert*
🔖 *Level:* $lvl
🧩 *Tag:* $tag
💬 *Message:* $msg
🕓 *Time:* $ts
💻 *Host:* $HostName
"@
}
function Ensure-Dirs(){
  if (-not (Test-Path $TokenDir)) { New-Item -ItemType Directory -Force -Path $TokenDir | Out-Null }
}

# ─── Init tokens ─────────────────────────────────────────────────────────────
Ensure-Dirs

$needInit = $false
if (-not (Test-Path $TokenFile)) {
@"
# === DAO-G13 TOKEN ===
# Встав сюди токен Telegram-бота від @BotFather
# Формат: 1234567890:AAH3dYjexample_token_here
"@ | Set-Content -LiteralPath $TokenFile -Encoding UTF8
  Write-Warning "⚠️ Створено шаблон $TokenFile — заповни токен."
  $needInit = $true
}
if (-not (Test-Path $ChatFile)) {
@"
# === DAO-G13 CHAT ID ===
# Встав сюди ID чату/каналу/групи (зазвичай -100XXXXXXXXXXXX)
"@ | Set-Content -LiteralPath $ChatFile -Encoding UTF8
  Write-Warning "⚠️ Створено шаблон $ChatFile — заповни chat_id (або використай -Chat '@name')."
}

if ($needInit) {
  throw "DAO-G13: токен не налаштований. Заповни $TokenFile"
}

# ─── Read & validate credentials ─────────────────────────────────────────────
$Token = Read-FirstValue $TokenFile
if (-not ($Token -match '^\d{6,}:[A-Za-z0-9_\-]{20,}$')) {
  throw "DAO-G13: некоректний токен у $TokenFile (очікувано 1234567890:AA...)."
}

# chat_id з файлу, якщо не передано -Chat
$ChatId = $null
if (-not $Chat) {
  $ChatId = Read-FirstValue $ChatFile
  if (-not $ChatId) {
    Write-Warning "⚠️ ChatId відсутній у $ChatFile. Можеш передати -Chat '@username' або заповнити файл."
  }
}

# ─── Resolve Chat if -Chat provided (@username → numeric) ────────────────────
if ($Chat) {
  if ($Chat -notmatch '^@') { $Chat = '@' + $Chat }
  $uri = "https://api.telegram.org/bot$Token/getChat?chat_id=$Chat"
  try {
    $resp = Invoke-RestMethod $uri -Method Get
    if (-not $resp.ok) { throw "getChat ok:false" }
    $ChatId = $resp.result.id
  } catch {
    throw "DAO-G13: не вдалося отримати chat_id для $Chat → $($_.Exception.Message)"
  }
}

if (-not $ChatId) {
  throw "DAO-G13: не задано chat_id. Додай у $ChatFile або скористайся -Chat '@username'."
}
if ($ChatId -notmatch '^-?\d+$') {
  throw "DAO-G13: некоректний chat_id '$ChatId' (очікується число, зазвичай -100XXXXXXXXXXXX)."
}

# ─── Build message/caption ───────────────────────────────────────────────────
$headerMD = Build-Header -lvl $Level -tag $Tag -msg $Message
$caption  = if ($headerMD.Length -gt 950) { $headerMD.Substring(0,950) } else { $headerMD }

if ($ParseMode -eq 'HTML') {
  $header = $headerMD -replace '\*([^\*]+)\*','<b>$1</b>'
} else {
  $header = $headerMD
}

# ─── Dispatch helper ─────────────────────────────────────────────────────────
function Send-Message([string]$text){
  $uri  = "https://api.telegram.org/bot$Token/sendMessage"
  $body = @{
    chat_id              = $ChatId
    text                 = $text
    parse_mode           = $ParseMode
    disable_notification = [bool]$DisableNotification
  }
  Invoke-RestMethod -Uri $uri -Method Post -Body $body -ErrorAction Stop | Out-Null
}
function Send-Document([string]$path){
  if (-not (Test-Path -LiteralPath $path)) { throw "Файл не знайдено: $path" }
  $uri = "https://api.telegram.org/bot$Token/sendDocument"
  $form = @{
    chat_id              = $ChatId
    caption              = $caption
    parse_mode           = $ParseMode
    disable_notification = [bool]$DisableNotification
    document             = Get-Item -LiteralPath $path
  }
  Invoke-RestMethod -Uri $uri -Method Post -Form $form -ErrorAction Stop | Out-Null
}
function Send-Photo([string]$path){
  if (-not (Test-Path -LiteralPath $path)) { throw "Зображення не знайдено: $path" }
  $uri = "https://api.telegram.org/bot$Token/sendPhoto"
  $form = @{
    chat_id              = $ChatId
    caption              = $caption
    parse_mode           = $ParseMode
    disable_notification = [bool]$DisableNotification
    photo                = Get-Item -LiteralPath $path
  }
  Invoke-RestMethod -Uri $uri -Method Post -Form $form -ErrorAction Stop | Out-Null
}

# ─── Send ────────────────────────────────────────────────────────────────────
try {
  if ($Photo) {
    Send-Photo -path $Photo
    if (-not $Silent) { Write-Host "🖼️ Фото надіслано ($Tag) → $ChatId" -ForegroundColor Green }
  }
  elseif ($File) {
    Send-Document -path $File
    if (-not $Silent) { Write-Host "📎 Документ надіслано ($Tag) → $ChatId" -ForegroundColor Green }
  }
  else {
    Send-Message -text $header
    if (-not $Silent) { Write-Host "✅ Повідомлення надіслано ($Tag) → $ChatId" -ForegroundColor Green }
  }
}
catch {
  Write-Warning ("❌ DAO-G13: помилка відправки — {0}" -f $_.Exception.Message)
  throw
}
