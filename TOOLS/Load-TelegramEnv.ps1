# D:\CHECHA_CORE\TOOLS\Load-TelegramEnv.ps1
param([string]$SecretsDir = "D:\CHECHA_CORE\SECRETS")
$secretsPath = Join-Path $SecretsDir "telegram.json"
if(!(Test-Path -LiteralPath $secretsPath)){
  Write-Host "[WARN] No telegram.json at $secretsPath" -ForegroundColor Yellow
  exit 0
}
$j = Get-Content -LiteralPath $secretsPath -Raw | ConvertFrom-Json
$env:TELEGRAM_BOT_TOKEN = $j.token
$env:TELEGRAM_CHAT_ID   = $j.chat
Write-Host "[OK] TELEGRAM_* env set" -ForegroundColor Green
