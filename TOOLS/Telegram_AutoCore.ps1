<#
.SYNOPSIS
  Єдина точка інтеграції Telegram для CHECHA_CORE/DAO-GOGS.

.PARAMETER Profile
  Профіль бота: radar | public | alerts (default: radar)

.PARAMETER Text
  Текст повідомлення (рядок або файл через -FromFile)

.PARAMETER Mode
  Формат: HTML | Markdown | MarkdownV2 | Text (за замовчуванням HTML)

.PARAMETER FromFile
  Шлях до файлу з текстом (перезаписує -Text)

.PARAMETER Token / ChatId
  Ручний оверрайд токена/чат-айді (override .env та env)

.PARAMETER EnvPath
  Шлях до .env (default: D:\CHECHA_CORE\TOOLS\telegram.env)

.EXAMPLES
  # Просте повідомлення в канал DAO (public):
  .\Telegram_AutoCore.ps1 -Profile public -Text "<b>DAO-GOGS</b> Weekly v2.0 OK"

  # Технічний пінг (radar) з Markdown:
  .\Telegram_AutoCore.ps1 -Profile radar -Text "*Build OK*" -Mode Markdown

  # Надіслати в alerts текст із файлу:
  .\Telegram_AutoCore.ps1 -Profile alerts -FromFile "D:\msg\alert.txt"

  # Пряме перевизначення токена/чату:
  .\Telegram_AutoCore.ps1 -Token "123:ABC..." -ChatId "-100..." -Text "Hi"
#>

[CmdletBinding()]
param(
  [ValidateSet('radar','public','alerts')][string]$Profile = 'radar',
  [string]$Text,
  [ValidateSet('HTML','Markdown','MarkdownV2','Text')][string]$Mode = 'HTML',
  [string]$FromFile,
  [string]$Token,
  [string]$ChatId,
  [string]$EnvPath = "D:\CHECHA_CORE\TOOLS\telegram.env",
  [switch]$TestBot,
  [switch]$TestChat
)

Set-StrictMode -Version Latest

function Log([string]$m,[string]$lvl='INFO'){
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$lvl] $ts $m"
}

function Read-DotEnv([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ return @{} }
  $dict = @{}
  foreach($line in Get-Content -LiteralPath $path){
    if($line -match '^\s*#'){ continue }
    if($line -match '^\s*$'){ continue }
    $idx = $line.IndexOf('=')
    if($idx -lt 1){ continue }
    $k = $line.Substring(0,$idx).Trim()
    $v = $line.Substring($idx+1).Trim()
    $dict[$k] = $v
  }
  return $dict
}

function Resolve-Creds([string]$profile,[string]$envPath,[string]$overrideToken,[string]$overrideChat){
  if($overrideToken -and $overrideChat){
    return [pscustomobject]@{ Token=$overrideToken; ChatId=$overrideChat; Source='override' }
  }
  $env = Read-DotEnv -path $envPath
  switch ($profile) {
    'radar'  { $t = $env.RADAR_TOKEN  ?? $env:RADAR_TOKEN;  $c = $env.RADAR_CHAT  ?? $env:RADAR_CHAT  }
    'public' { $t = $env.PUBLIC_TOKEN ?? $env:PUBLIC_TOKEN; $c = $env.PUBLIC_CHAT ?? $env:PUBLIC_CHAT }
    'alerts' { $t = $env.ALERTS_TOKEN ?? $env:ALERTS_TOKEN; $c = $env.ALERTS_CHAT ?? $env:ALERTS_CHAT }
  }
  if(-not $t -or -not $c){ return $null }
  [pscustomobject]@{ Token=$t; ChatId=$c; Source='env' }
}

function Test-Token([string]$token){
  try {
    $resp = Invoke-RestMethod "https://api.telegram.org/bot$token/getMe" -ErrorAction Stop
    return $resp.ok -eq $true
  } catch { return $false }
}

function Test-ChatAccess([string]$token,[string]$chatId){
  try {
    # safest ping with minimal risk
    $uri = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{ chat_id=$chatId; text="ping"; parse_mode="HTML" }
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ErrorAction Stop
    return $resp.ok -eq $true
  } catch {
    # read error body to help debugging
    $r = $_.Exception.Response
    if($r){
      $sr = New-Object IO.StreamReader($r.GetResponseStream())
      $sr.BaseStream.Position = 0; $sr.DiscardBufferedData()
      $json = $sr.ReadToEnd()
      Log "Chat access error: $json" 'ERR'
    } else {
      Log "Chat access error: $($_.Exception.Message)" 'ERR'
    }
    return $false
  }
}

function Send-CheChaMsg([string]$token,[string]$chatId,[string]$text,[string]$mode){
  if($mode -eq 'Text'){ $mode = $null } # no parse_mode
  $uri = "https://api.telegram.org/bot$token/sendMessage"
  $body = @{ chat_id=$chatId; text=$text }
  if($mode){ $body.parse_mode = $mode }
  try {
    Invoke-RestMethod -Method Post -Uri $uri -Body $body -ErrorAction Stop | Out-Null
    Log "Message sent to chat $chatId" 'INFO'
  } catch {
    $r = $_.Exception.Response
    if($r){
      $sr = New-Object IO.StreamReader($r.GetResponseStream())
      $sr.BaseStream.Position = 0; $sr.DiscardBufferedData()
      $json = $sr.ReadToEnd()
      Log "Send failed: $json" 'ERR'
    } else {
      Log "Send failed: $($_.Exception.Message)" 'ERR'
    }
    exit 2
  }
}

# --- main ---
$creds = Resolve-Creds -profile $Profile -envPath $EnvPath -overrideToken $Token -overrideChat $ChatId
if(-not $creds){ Log "Credentials for profile '$Profile' not found (.env or ENV)" 'ERR'; exit 1 }

if(-not (Test-Token -token $creds.Token)){
  Log "Token invalid for profile '$Profile' (getMe failed)" 'ERR'; exit 1
}

if($FromFile){
  if(-not (Test-Path -LiteralPath $FromFile)){ Log "FromFile not found: $FromFile" 'ERR'; exit 1 }
  $Text = Get-Content -LiteralPath $FromFile -Raw
}

if([string]::IsNullOrWhiteSpace($Text) -and -not $TestBot -and -not $TestChat){
  Log "Empty -Text. Use -Text or -FromFile or -Test* switches." 'ERR'; exit 1
}

if($TestBot){
  Log "Bot OK: $((Invoke-RestMethod "https://api.telegram.org/bot$($creds.Token)/getMe").result.username)" 'INFO'
}

if($TestChat){
  if(Test-ChatAccess -token $creds.Token -chatId $creds.ChatId){
    Log "Chat access OK for $($creds.ChatId)" 'INFO'
  } else {
    exit 2
  }
}

if($Text){
  Send-CheChaMsg -token $creds.Token -chatId $creds.ChatId -text $Text -mode $Mode
}
