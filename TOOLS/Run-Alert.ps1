# === Run-Alert.ps1 (повна стабільна структура) ===
param(
    [string]$ReportsRoot = 'D:\LeaderIntel\pkg\LeaderIntel\reports',
    [string]$LogsRoot = 'D:\CHECHA_CORE\C07_ANALYTICS'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- 1. Функція логування має бути перед усіма try/catch ---
if (!(Test-Path $LogsRoot)) { New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null }
$log = Join-Path $LogsRoot 'Run-Alert.log'
function W($m) {
    $l = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $l | Add-Content -LiteralPath $log
    Write-Host $l
}

function Ensure-Dir([Parameter(Mandatory)][string]$Path, [string]$name) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$name is null/empty" }
    $rp = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $rp -PathType Container)) { throw "$name is not a directory: $rp" }
    return $rp.Path
}

# --- 2. Головна логіка ---
try {
    $ReportsRoot = Ensure-Dir $ReportsRoot 'ReportsRoot'
    $LogsRoot = Ensure-Dir $LogsRoot    'LogsRoot'
    W "START Run-Alert (ReportsRoot=$ReportsRoot)"
}
catch {
    # Тепер функція W існує, тому catch спрацює коректно
    $msg = $_.Exception.Message
    Add-Content -LiteralPath $log -Value "[{0}] ERROR: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host "ERROR: $msg"
    exit 1
}

$rc = 0

# --- 3. Крок 1: перевірка деградації ---
try {
    W "STEP Notify-If-Degraded.ps1"
    $script = 'D:\LeaderIntel\pkg\LeaderIntel\scripts\Notify-If-Degraded.ps1'
    if (Test-Path $script) {
        & $script -ReportsRoot $ReportsRoot -Verbose
        if ($LASTEXITCODE -ne 0) { throw "Notify-If-Degraded returned $LASTEXITCODE" }
    }
    else {
        W "WARN: script not found: $script — skipped"
    }
}
catch {
    W "FAIL Notify-If-Degraded: $($_.Exception.Message)"
    $rc = 1
}

# --- 4. Крок 2: перевірка свіжості артефактів ---
try {
    W "STEP Reports freshness/size"
    $need = @('ToxicRadar.html', 'MetricsTrend.svg', 'Dashboard.html')
    $now = Get-Date
    $maxAge = New-TimeSpan -Minutes 90
    foreach ($n in $need) {
        $f = Join-Path $ReportsRoot $n
        if (!(Test-Path $f)) { throw "$n missing" }
        $fi = Get-Item $f
        if ($now - $fi.LastWriteTime -gt $maxAge) { throw "$n stale: $($fi.LastWriteTime)" }
        if ($fi.Length -le 0) { throw "$n size=0" }
    }
    W "OK freshness/size"
}
catch {
    W "FAIL freshness/size: $($_.Exception.Message)"
    $rc = 1
}

W ("END Run-Alert (rc={0})" -f $rc)
exit $rc
# === /Run-Alert.ps1 ===

