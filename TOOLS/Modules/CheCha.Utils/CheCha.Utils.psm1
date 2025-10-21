function Send-Telegram {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Text,
        [ValidateSet('Markdown','MarkdownV2','HTML')][string]$Mode = 'HTML')
  $token = $env:TG_BOT_TOKEN; $chat = $env:TG_CHAT_ID
  if(!$token -or !$chat){ Log -Message "TG env vars missing; skip notify" -Level 'WARN'; return }
  try {
    $uri  = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{ chat_id = $chat; text = $Text; parse_mode = $Mode }
    Invoke-RestMethod -Method Post -Uri $uri -Body $body -ErrorAction Stop | Out-Null
    Log -Message "Telegram sent" -Level 'INFO'
  } catch {
    Log -Message ("Telegram failed: {0}" -f $_.Exception.Message) -Level 'ERR'
  }
}
