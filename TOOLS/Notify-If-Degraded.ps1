param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
trap {
    # мінімізує “тихі” фейли
    $_ | Out-String | ForEach-Object { Add-Content -Path "D:\CHECHA_CORE\C07_ANALYTICS\ALERTS.log" -Value ("[{0}] ERROR: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_) }
    exit 1
}

$lockFile = Join-Path $Analytics ".alert.lock"
if (Test-Path $lockFile -and ((Get-Date) - (Get-Item $lockFile).LastWriteTime).TotalMinutes -lt 5) {
    Log "SKIP: already running"; exit 0
}
New-Item -ItemType File -Path $lockFile -Force | Out-Null
try {
    # ...вся логіка...
}
finally { Remove-Item $lockFile -ErrorAction SilentlyContinue }

param(
    [string]$RepoRoot = "D:\CHECHA_CORE",
    [string]$BotToken,
    [string]$ChatId,
    [switch]$Force
)

# --- Paths/Repo root ---
if (-not $RepoRoot) { $RepoRoot = "D:\CHECHA_CORE" }  # дефолт, якщо не передано
$Analytics = Join-Path $RepoRoot "C07_ANALYTICS"

# переконаємось, що каталог існує
New-Item -ItemType Directory -Path $Analytics -Force | Out-Null

# --- Simple logger (якщо ще немає) ---
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    $script:AlertLog = Join-Path $Analytics "ALERTS.log"
    function Log([string]$m) {
        "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m |
            Out-File -Append -Encoding utf8 $script:AlertLog
    }
}

# --- LOCK ---
$lockFile = Join-Path $Analytics ".alert.lock"
if (Test-Path -LiteralPath $lockFile -and ((Get-Date) - (Get-Item $lockFile).LastWriteTime).TotalMinutes -lt 5) {
    Log "SKIP: already running"
    return
}
New-Item -ItemType File -Path $lockFile -Force | Out-Null

# далі у файлі має йти ВЕСЬ твій основний код у блоці try/finally,
# щоб ми гарантовано прибрали lock
try {
    # ... ВЕСЬ ІСНУЮЧИЙ КОД СПОВІЩЕННЯ ...
    # (гілка OVERALL=OK із оновленням .alert_state.json ПЕРЕД exit/return)
}
finally {
    Remove-Item $lockFile -ErrorAction SilentlyContinue
}

$Analytics = Join-Path $RepoRoot "C07_ANALYTICS"
$healthTxt = Join-Path $Analytics "HEALTH.txt"
$statusJson = Join-Path $Analytics "Status.json"
$stateFile = Join-Path $Analytics ".alert_state.json"
$logFile = Join-Path $Analytics "ALERTS.log"
$tsNow = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

# ensure dir
New-Item -ItemType Directory -Path $Analytics -Force | Out-Null

function Log([string]$m) { "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m | Out-File -Append -Encoding utf8 $logFile }

# 1) OVERALL
$overall = $null
if (Test-Path -LiteralPath $healthTxt) {
    $line = (Get-Content -LiteralPath $healthTxt | Where-Object { $_ -match '^OVERALL=' } | Select-Object -Last 1)
    if ($line) { $overall = ($line -replace '^OVERALL=', '').Trim() }
}
if (-not $overall -and (Test-Path -LiteralPath $statusJson)) {
    try { $st = Get-Content -LiteralPath $statusJson -Raw | ConvertFrom-Json; if ($st.Overall) { $overall = [string]$st.Overall } }catch {}
}
if (-not $overall) { $overall = "WARN" } # перестраховка

# 2) антиспам
$state = @{ lastOverall = ""; lastTs = "" }
if (Test-Path -LiteralPath $stateFile) {
    try { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json }catch {}
}

# --- антиспам однакового статусу (лише коли треба слати) ---
if ($shouldNotify -and $state.lastOverall -eq $overall) {
    $dtPrev = $null
    if ($state.lastTs) { [void][DateTime]::TryParse($state.lastTs, [ref]$dtPrev) }
    if ($dtPrev -and ((Get-Date) - $dtPrev).TotalMinutes -lt 10) {
        Log "SKIP same OVERALL=$overall (<10m)"
        exit 0
    }
}

# --- ГОЛОВНЕ: якщо все ОК і не примусово — не шлемо ---
if (-not $Force.IsPresent -and $overall -eq "OK") {
    Log "OK/no alert (OVERALL=OK)"
    exit 0
}

# 3) сформувати повідомлення
$msg = "[CHECHA] OVERALL=$overall at $tsNow"
try {
    if (Test-Path -LiteralPath $statusJson) {
        $st = Get-Content -LiteralPath $statusJson -Raw | ConvertFrom-Json
        if ($st -and $st.LastMetrics) {
            $m = $st.LastMetrics
            $msg += "`nAvg=" + [math]::Round([double]$m.Avg, 3) + "  {St:" + [math]::Round([double]$m.Stability, 2) + ", Cl:" + [math]::Round([double]$m.Clean, 2) + ", Sy:" + [math]::Round([double]$m.Sync, 2) + ", Ed:" + [math]::Round([double]$m.Edu, 2) + ", An:" + [math]::Round([double]$m.Anal, 2) + "}"
        }
    }
}
catch {}

# 4) секрети
$Token = if ($BotToken) { $BotToken }else { $env:TELEGRAM_BOT_TOKEN }
$Chat = if ($ChatId) { $ChatId }else { $env:TELEGRAM_CHAT_ID }
if (-not $Token -or -not $Chat) {
    Log "SKIP no secrets (Token/Chat empty)"
    exit 2
}

# 5) надсилання
Log ("TRY: " + $msg.Replace("`n", " | "))
$ok = $false
try {
    $uri = "https://api.telegram.org/bot$Token/sendMessage"
    Invoke-RestMethod -Method Post -Uri $uri -Body @{ chat_id = $Chat; text = $msg; parse_mode = 'Markdown'; disable_web_page_preview = $true } -ErrorAction Stop | Out-Null
    $ok = $true
}
catch {
    Log ("ERR: " + $_.Exception.Message)
    $ok = $false
}

# 6) state + exitcode
if ($ok) {
    [pscustomobject]@{ lastOverall = $overall; lastTs = $tsNow } | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 -FilePath $stateFile
    Log "OK: sent"
    exit 0
}
else {
    exit 1
}


