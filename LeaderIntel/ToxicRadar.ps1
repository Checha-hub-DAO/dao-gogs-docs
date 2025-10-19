param(
    [string]$CleanCsv = "..\data\Leaders.cleaned.csv",
    [string]$ToxicPath = "..\data\ToxicMatrix.csv",
    [string]$OutHtml = "..\reports\ToxicRadar.html",
    [string]$HistoryDir = "..\data\history"   # опційно: для трендів
)

$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Web

function Load-Csv($p) {
    if (Test-Path -LiteralPath $p) { return Import-Csv -LiteralPath $p -Encoding UTF8 }
    else { return @() }
}

$rows = Load-Csv $CleanCsv
$tox = Load-Csv $ToxicPath

if ($rows.Count -eq 0) {
    "# Немає даних для побудови радара (`$CleanCsv` не знайдено або порожній)" |
        Set-Content -LiteralPath $OutHtml -Encoding UTF8
    Write-Host "[WARN] No data. Created placeholder: $OutHtml"
    exit 0
}

# --- Map headers
$h = ($rows | Select-Object -First 1).PSObject.Properties.Name
function F([string[]]$hdr, [string]$p) { $hdr | Where-Object { $_ -match $p } | Select-Object -First 1 }
$cName = F $h 'Ім.?я|Name'
$cVis = F $h '^Visibility$'; if (-not $cVis) { $cVis = 'Visibility' }

# Toxicity lookup (optional)
$toxMap = @{}
if ($tox.Count -gt 0) {
    $th = ($tox | Select-Object -First 1).PSObject.Properties.Name
    $tName = F $th 'Ім.?я|Name'
    $tTox = F $th 'Токсичн|Toxic'
    foreach ($r in $tox) {
        $n = if ($tName -and $r.PSObject.Properties[$tName]) { ($r.PSObject.Properties[$tName]).Value } else { "" }
        $t = if ($tTox -and $r.PSObject.Properties[$tTox]) { ($r.PSObject.Properties[$tTox]).Value } else { "" }
        if ($n) { $toxMap[$n] = $t }
    }
}

# --- Aggregations
$visBuckets = @{ allow = 0; watch = 0; block = 0 }
$toxBuckets = @{ низька = 0; середня = 0; висока = 0; невідомо = 0 }

foreach ($r in $rows) {
    $name = if ($cName -and $r.PSObject.Properties[$cName]) { ($r.PSObject.Properties[$cName]).Value } else { "" }
    $vis = if ($cVis -and $r.PSObject.Properties[$cVis]) { ($r.PSObject.Properties[$cVis]).Value }  else { "allow" }
    if ($visBuckets.ContainsKey($vis)) { $visBuckets[$vis]++ } else { $visBuckets[$vis] = 1 }

    $tlvl = "невідомо"
    if ($name -and $toxMap.ContainsKey($name)) {
        $t = ($toxMap[$name] ?? "").ToString().ToLower()
        if ($t -match 'низ') { $tlvl = 'низька' }
        elseif ($t -match 'сер') { $tlvl = 'середня' }
        elseif ($t -match 'вис') { $tlvl = 'висока' }
    }
    $toxBuckets[$tlvl]++
}

# --- Trend (optional): read last 7 days metrics.json if exist
$trend = @()
if (Test-Path $HistoryDir) {
    $files = Get-ChildItem -LiteralPath $HistoryDir -Filter "metrics_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
    foreach ($f in $files | Select-Object -Last 7) {
        try {
            $m = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $trend += [pscustomobject]@{
                date   = $m.date
                allow  = [int]$m.allow
                watch  = [int]$m.watch
                block  = [int]$m.block
                alerts = [int]$m.alerts
            }
        }
        catch {}
    }
}

# --- HTML render
function Bar($label, $value, $max, $color) {
    if ($max -le 0) { $max = 1 }
    $w = [math]::Round(($value / $max) * 100)
    return "<div style='margin:6px 0'><div style='font-weight:600'>$label: $value</div><div style='height:10px;background:#eee;border-radius:6px'><div style='width:${w}%;height:10px;background:$color;border-radius:6px'></div></div></div>"
}

$maxVis = [math]::Max([int]$visBuckets.allow, [int]$visBuckets.watch, [int]$visBuckets.block)
$visHtml = @()
$visHtml += (Bar "allow" $visBuckets.allow $maxVis "#5cb85c")
$visHtml += (Bar "watch" $visBuckets.watch $maxVis "#f0ad4e")
$visHtml += (Bar "block" $visBuckets.block $maxVis "#d9534f")

$toxHtml = @()
$maxTox = ($toxBuckets.Values | Measure-Object -Maximum).Maximum
$toxHtml += (Bar "низька"  $toxBuckets.'низька'  $maxTox "#5bc0de")
$toxHtml += (Bar "середня" $toxBuckets.'середня' $maxTox "#428bca")
$toxHtml += (Bar "висока"  $toxBuckets.'висока'  $maxTox "#d9534f")
$toxHtml += (Bar "невідомо" $toxBuckets.'невідомо' $maxTox "#999999")

# Trend table (if any)
$trendTable = ""
if ($trend.Count -gt 0) {
    $rowsHtml = foreach ($t in $trend) {
        "<tr><td>$($t.date)</td><td>$($t.allow)</td><td>$($t.watch)</td><td>$($t.block)</td><td>$($t.alerts)</td></tr>"
    }
    $trendTable = @"
  <h2>Тренд (останні 7 днів)</h2>
  <table>
    <thead><tr><th>Дата</th><th>allow</th><th>watch</th><th>block</th><th>alerts</th></tr></thead>
    <tbody>
      $(($rowsHtml -join "`n"))
    </tbody>
  </table>
"@
}

$html = @"
<!doctype html>
<html lang="uk">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>ToxicRadar</title>
<style>
  body{font:16px/1.6 system-ui,-apple-system,Segoe UI,Roboto,Arial;padding:24px;color:#111;background:#fff}
  h1,h2{margin:0.6em 0}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}
  table{border-collapse:collapse}
  th,td{border:1px solid #e0e0e0;padding:6px 10px}
  th{background:#fafafa}
  .meta{color:#666;font-size:12px;margin-bottom:12px}
  .nav a{margin-right:12px;text-decoration:none;color:#0a58ca}
</style>
</head>
<body>
<div class="meta">Згенеровано: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>
<div class="nav">
  <a href="Digest_$(Get-Date -Format 'yyyyMMdd').html">Дайджест</a>
  <a href="Flags.md">Прапорці</a>
  <a href="Alerts.md">Алерти</a>
  <a href="LeaderIntel_Log.md">Журнал</a>
</div>

<h1>Інтелектуальний радар — зведення</h1>
<div class="grid">
  <div>
    <h2>Visibility</h2>
    $(($visHtml -join "`n"))
  </div>
  <div>
    <h2>Токсичність</h2>
    $(($toxHtml -join "`n"))
  </div>
</div>

$trendTable
</body>
</html>
"@

$html | Set-Content -LiteralPath $OutHtml -Encoding UTF8
Write-Host "[OK] ToxicRadar → $OutHtml"


