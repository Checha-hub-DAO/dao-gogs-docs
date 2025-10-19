param([Parameter(Mandatory = $true)] [string]$Token, [string]$SecretsDir = "D:\CHECHA_CORE\SECRETS")
$ErrorActionPreference = 'Stop'
$null = New-Item -ItemType Directory -Path $SecretsDir -Force
$me = Invoke-RestMethod -Uri ("https://api.telegram.org/bot{0}/getMe" -f $Token)
if (-not $me.ok) { throw "Bad token" }
Write-Host "[OK] Token valid. Bot=@$($me.result.username)" -Foreground Green
Write-Host "1) ДОДАЙ бота в чат або напиши боту в приваті /start."
Write-Host "2) Напиши будь-яке повідомлення в цей чат."
Write-Host "Потім натисни Enter, щоб продовжити..."
Read-Host | Out-Null
$upd = Invoke-RestMethod -Uri ("https://api.telegram.org/bot{0}/getUpdates" -f $Token)
if (-not $upd.ok -or -not $upd.result) { throw "Немає оновлень. Перевір, що бот у чаті і є нове повідомлення." }
$last = $upd.result | Sort-Object update_id | Select-Object -Last 1
$chat = $last.message.chat.id
if (-not $chat) { throw "Не знайшов chat.id" }
$secretsPath = Join-Path $SecretsDir "telegram.json"
@{ token = $Token; chat = "$chat"; saved = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } |
    ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 -FilePath $secretsPath
Write-Host "[OK] Saved to $secretsPath" -Foreground Green
$resp = Invoke-RestMethod -Method Post -Uri ("https://api.telegram.org/bot{0}/sendMessage" -f $Token) -Body @{
    chat_id=$chat; text="[CHECHA] secrets saved ✅"; parse_mode='Markdown'; disable_web_page_preview=$true 
}
if ($resp.ok) { Write-Host "[OK] Test message sent (id=$($resp.result.message_id))" -Foreground Green }

