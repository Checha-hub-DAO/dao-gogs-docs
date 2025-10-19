# Alerts.ps1 — універсальні нотифікації (Email/Telegram) для CheCha CORE

function Get-AlertsConfig {
    param([string]$Path = "D:\CHECHA_CORE\CONFIG\alerts.json")
    if (!(Test-Path -LiteralPath $Path)) { throw "alerts.json не знайдено: $Path" }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Send-EmailAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [string]$ConfigPath = "D:\CHECHA_CORE\CONFIG\alerts.json"
    )
    $c = Get-AlertsConfig -Path $ConfigPath
    $smtp = New-Object System.Net.Mail.SmtpClient($c.Email.SmtpHost, [int]$c.Email.SmtpPort)
    $smtp.EnableSsl = [bool]$c.Email.EnableSsl
    if ($c.Email.User -and $c.Email.Password) {
        $creds = New-Object System.Net.NetworkCredential($c.Email.User, $c.Email.Password)
        $smtp.Credentials = $creds
    }
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = $c.Email.From
    foreach ($to in $c.Email.To) { $null = $msg.To.Add($to) }
    $msg.Subject = $Subject
    $msg.Body = $Body
    $msg.IsBodyHtml = $false
    try { $smtp.Send($msg) ; return $true }
    catch { Write-Host "[EmailAlert][ERROR] $($_.Exception.Message)"; return $false }
    finally { $msg.Dispose(); $smtp.Dispose() }
}

function Send-TelegramAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$ConfigPath = "D:\CHECHA_CORE\CONFIG\alerts.json"
    )
    $c = Get-AlertsConfig -Path $ConfigPath
    $uri = "https://api.telegram.org/bot$($c.Telegram.BotToken)/sendMessage"
    $payload = @{
        chat_id                  = $c.Telegram.ChatId
        text                     = $Text
        parse_mode               = "Markdown"
        disable_web_page_preview = $true
    }
    try { Invoke-RestMethod -Method Post -Uri $uri -Body $payload ; return $true }
    catch { Write-Host "[TGAlert][ERROR] $($_.Exception.Message)"; return $false }
}


