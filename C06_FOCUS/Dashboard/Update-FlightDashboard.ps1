[CmdletBinding()]
param(
    [string]$Root = "D:\CHECHA_CORE",
    [string]$DashboardMd = "D:\CHECHA_CORE\C06_FOCUS\Flight_Dashboard_2.0.md",
    [string]$BadgeTpl = "D:\CHECHA_CORE\C06_FOCUS\assets\ReflexBadge_Template.svg",
    [string]$BadgeOut = "D:\CHECHA_CORE\C06_FOCUS\assets\reflex_badge.svg"
)

$ReflexDir = Join-Path $Root "C07_ANALYTICS\Reflex"
$latestJson = Get-ChildItem -LiteralPath $ReflexDir -Filter "ReflexReport_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $latestJson) {
    Write-Host "[WARN] Не знайдено ReflexReport JSON."
    exit 0
}

$data = Get-Content -LiteralPath $latestJson.FullName -Raw | ConvertFrom-Json
$statusOk = $data.Status.Ok
$warns = $data.Status.Warns
$dateIso = $data.Date
$taskTbl = $data.TaskHealth

# 1) Бейдж
$tpl = Get-Content -LiteralPath $BadgeTpl -Raw
if ($statusOk) {
    $tpl = $tpl -replace '#4c1', '#4c1' -replace '>OK<', '>OK<'
}
else {
    # WARN → жовтий; якщо хочеш, розділи ERROR окремо
    $tpl = $tpl -replace '#4c1', '#dfb317' -replace '>OK<', '>WARN<'
}
Set-Content -LiteralPath $BadgeOut -Value $tpl -Encoding UTF8

# 2) Хедер-плашка
$warnText = if ($warns.Count -gt 0) { ($warns -join '; ') } else { '—' }
$stateStr = if ($statusOk) { "✅ OK" } else { "⚠️ WARN" }
$headerBlock = @()
$headerBlock += "<!-- FLIGHT_DASHBOARD_HEADER -->"
$headerBlock += "# 🛰️ Flight Dashboard 2.0"
$headerBlock += ""
$headerBlock += "**Стан Reflex:** $stateStr  "
$headerBlock += "**Останній звіт:** $dateIso  "
$headerBlock += "**Попередження:** $warnText  "
$headerBlock += ""
$headerBlock += "![Reflex Badge](assets/reflex_badge.svg)"
$headerBlock += "<!-- /FLIGHT_DASHBOARD_HEADER -->"
$header = ($headerBlock -join "`r`n")

# 3) Таблиця задач
$rows = foreach ($t in $taskTbl) {
    $lr = if ($t.LastRunTime) { (Get-Date $t.LastRunTime).ToString("yyyy-MM-dd HH:mm:ss") } else { "-" }
    $nr = if ($t.NextRunTime) { (Get-Date $t.NextRunTime).ToString("yyyy-MM-dd HH:mm:ss") } else { "-" }
    $ok = if ($t.Ok) { "✅" } else { "❗" }
    "| $($t.TaskName) | $($t.State) | $lr | $nr | $($t.LastTaskResult) | $ok |"
}

$table = @()
$table += "<!-- FLIGHT_DASHBOARD_TABLE -->"
$table += "| Task | State | LastRun | NextRun | Result | OK |"
$table += "|:-----|:------|:--------|:--------|:------:|:--:|"
$table += ($rows -join "`r`n")
$table += "<!-- /FLIGHT_DASHBOARD_TABLE -->"
$tableMd = ($table -join "`r`n")

# 4) Підміна в Dashboard
$md = Get-Content -LiteralPath $DashboardMd -Raw
$md = [regex]::Replace($md, '(?s)\<\!\-\- FLIGHT_DASHBOARD_HEADER \-\-\>.*?\<\!\-\- \/FLIGHT_DASHBOARD_HEADER \-\-\>', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $header })
$md = [regex]::Replace($md, '(?s)\<\!\-\- FLIGHT_DASHBOARD_TABLE \-\-\>.*?\<\!\-\- \/FLIGHT_DASHBOARD_TABLE \-\-\>', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $tableMd })
Set-Content -LiteralPath $DashboardMd -Value $md -Encoding UTF8

Write-Host "[OK] Dashboard оновлено: $DashboardMd"


