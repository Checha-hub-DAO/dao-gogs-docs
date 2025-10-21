Set-StrictMode -Version Latest

function Log {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('INFO','WARN','ERR','DBG')][string]$Level = 'INFO'
  )
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$Level] $ts $Message"
}

function Fail {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Message,
    [int]$Code = 1
  )
  Log -Message $Message -Level 'ERR'
  exit $Code
}

function Ensure-Dir {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { Fail "Ensure-Dir: empty path" }
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Log -Message "Created directory: $Path" -Level 'DBG'
  }
  return $true
}

function Get-IsoWeekStartEnd {
  [CmdletBinding()]
  param(
    [int]$Year  = (Get-Date).Year,
    [int]$Week
  )
  if (-not $PSBoundParameters.ContainsKey('Week')) {
    $now = Get-Date
    $cul = [System.Globalization.CultureInfo]::GetCultureInfo("uk-UA")
    $cal = $cul.DateTimeFormat.Calendar
    $rule= [System.Globalization.CalendarWeekRule]::FirstFourDayWeek
    $dow = [System.DayOfWeek]::Monday
    $Week = $cal.GetWeekOfYear($now,$rule,$dow)
    if($Week -ge 52 -and $now.Month -eq 1){ $Year-- }
  }
  $tz  = [System.TimeZoneInfo]::FindSystemTimeZoneById("FLE Standard Time") # Europe/Kyiv
  $jan4Utc  = [datetime]::SpecifyKind([datetime]"$Year-01-04", 'Utc')
  $jan4Kyiv = [System.TimeZoneInfo]::ConvertTimeFromUtc($jan4Utc,$tz)
  $dow = [int]$jan4Kyiv.DayOfWeek; if($dow -eq 0){ $dow = 7 }
  $monWeek1 = $jan4Kyiv.AddDays(1 - $dow)
  $start = (Get-Date $monWeek1.AddDays(7 * ($Week - 1)).Date)
  $end   = (Get-Date $start.AddDays(6).Date)
  [pscustomobject]@{ Start = $start; End = $end; ISOWeek = $Week; Year = $Year }
}

function Read-FrontMatterVersion {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$MarkdownPath)
  if (-not (Test-Path -LiteralPath $MarkdownPath)) { return $null }
  $raw = Get-Content -LiteralPath $MarkdownPath -Raw
  $m = [regex]::Match($raw, '(?is)^---\s*(.*?)\s*---')
  if ($m.Success) {
    $yaml = $m.Groups[1].Value
    $mv = [regex]::Match($yaml, '(?im)^\s*version\s*:\s*([^\r\n]+)')
    if ($mv.Success) { return $mv.Groups[1].Value.Trim() }
  }
  return $null
}

function Get-LastArtifacts {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$OutDir)
  if (-not (Test-Path -LiteralPath $OutDir)) { Fail "OutDir not found: $OutDir" }
  $zip = Get-ChildItem -LiteralPath $OutDir -Filter "DAO-ARCHITECTURE_*.zip" |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $sha = Get-ChildItem -LiteralPath $OutDir -Filter "*.zip.sha256.txt" |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $log = Get-ChildItem -LiteralPath $OutDir -Filter "*.log" |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  [pscustomobject]@{ Zip=$zip; Sha=$sha; Log=$log }
}

function Send-Telegram {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Text,
    [ValidateSet('Markdown','MarkdownV2','HTML')][string]$Mode = 'HTML'
  )
  $token = $env:TG_BOT_TOKEN
  $chat  = $env:TG_CHAT_ID
  if(!$token -or !$chat){
    Log -Message "TG env vars missing; skip notify" -Level 'WARN'
    return
  }
  try {
    $uri  = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{ chat_id = $chat; text = $Text; parse_mode = $Mode }
    Invoke-RestMethod -Method Post -Uri $uri -Body $body -ErrorAction Stop | Out-Null
    Log -Message "Telegram sent" -Level 'INFO'
  } catch {
    Log -Message ("Telegram failed: {0}" -f $_.Exception.Message) -Level 'ERR'
  }
}

Export-ModuleMember -Function `
  Log, Fail, Ensure-Dir, Get-IsoWeekStartEnd, Read-FrontMatterVersion, `
  Get-LastArtifacts, Send-Telegram
