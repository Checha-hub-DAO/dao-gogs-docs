<#
.SYNOPSIS
  Показ системного toast-повідомлення у Windows 10/11 без зовнішніх залежностей.
  Якщо модуль BurntToast доступний — буде використаний автоматично.

.PARAMETER Title
  Заголовок тосту

.PARAMETER Message
  Основний текст

.PARAMETER AppId
  Ім’я для групування повідомлень у Центрі сповіщень (за замовч: 'CheCha')

.PARAMETER Severity
  info|warning|error — впливає на іконку/звук (за замовч: info)

.PARAMETER Duration
  short|long (за замовч: short)

.PARAMETER Silent
  Без звуку (за замовч: $false)

.PARAMETER IconPath
  Шлях до PNG/ICO (необов’язковий)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Message,
    [string]$AppId = 'CheCha',
    [ValidateSet('info', 'warning', 'error')][string]$Severity = 'info',
    [ValidateSet('short', 'long')][string]$Duration = 'short',
    [switch]$Silent,
    [string]$IconPath
)

function Use-BurntToast {
    try {
        if (Get-Module -ListAvailable -Name BurntToast) {
            Import-Module BurntToast -ErrorAction Stop
            return $true
        }
    }
    catch { }
    return $false
}

if (Use-BurntToast) {
    # Мапа звуків/іконок для BurntToast
    $sound = switch ($Severity) {
        'error' { 'Default' }     # BurntToast має окремі пресети, але Default достатньо
        'warning' { 'Default' }
        default { 'Default' }
    }
    $splat = @{
        Text   = @($Title, $Message)
        AppId  = $AppId
        Silent = [bool]$Silent
    }
    if ($IconPath -and (Test-Path -LiteralPath $IconPath)) { $splat['AppLogo'] = $IconPath }
    New-BurntToastNotification @splat | Out-Null
    return
}

# ---- Без BurntToast: нативний шлях через WinRT API ----
Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue | Out-Null

# Підключаємо WinRT типи
$null = [Windows.UI.Notifications.ToastNotification]
$null = [Windows.Data.Xml.Dom.XmlDocument]

# Базовий XML (Text02 шаблон: Title + Message)
$xml = @"
<toast duration="$Duration">
  <visual>
    <binding template="ToastGeneric">
      <text>$([System.Security.SecurityElement]::Escape($Title))</text>
      <text>$([System.Security.SecurityElement]::Escape($Message))</text>
    </binding>
  </visual>
</toast>
"@

# Додаємо звук/тишу
if (-not $Silent) {
    $soundSrc = switch ($Severity) {
        'error' { 'ms-winsoundevent:Notification.Looping.Alarm2' }
        'warning' { 'ms-winsoundevent:Notification.Reminder' }
        default { 'ms-winsoundevent:Notification.Default' }
    }
    $xml = $xml -replace '</toast>', "<audio src=""$soundSrc""/><\/toast>"
}
else {
    $xml = $xml -replace '</toast>', '<audio silent="true"/></toast>'
}

# Іконка (AppLogoOverride)
if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
    $iconEsc = $IconPath -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
    $xml = $xml -replace '<binding template="ToastGeneric">', "<binding template=""ToastGeneric""><image placement=""appLogoOverride"" src=""$iconEsc""/>"
}

# Завантаження XML
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml($xml)

# Ініціалізація нотифікації
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)

# Реєструємо AppId у менеджері
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)

# Відправляємо тост
$notifier.Show($toast)

