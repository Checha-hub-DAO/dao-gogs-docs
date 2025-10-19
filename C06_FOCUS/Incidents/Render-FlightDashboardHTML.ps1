[CmdletBinding()]
param(
    [string]$Root = "D:\CHECHA_CORE",
    [string]$OutHtml = "D:\CHECHA_CORE\C06_FOCUS\Flight_Dashboard_2.0.html"
)

$ReflexDir = Join-Path $Root "C07_ANALYTICS\Reflex"
$IncCsv = Join-Path $Root "C06_FOCUS\Incidents\Incident_Register.csv"

$latestJson = Get-ChildItem -LiteralPath $ReflexDir -Filter "ReflexReport_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latestJson) { Write-Host "[WARN] Не знайдено ReflexReport JSON."; exit 0 }

# Дані Reflex JSON
$reflexData = Get-Content -LiteralPath $latestJson.FullName -Raw

# REG: KPI за останні 7 днів із реєстру інцидентів (ERROR-випадки)
$reg = @()
if (Test-Path -LiteralPath $IncCsv) {
    try {
        $reg = Import-Csv -LiteralPath $IncCsv
    }
    catch { Write-Host "[WARN] Не вдалось прочитати Incident_Register.csv: $($_.Exception.Message)" }
}

$now = Get-Date
$from = $now.AddDays(-7)
$errors7 = 0
if ($reg.Count -gt 0) {
    foreach ($r in $reg) {
        # Очікується формат "YYYY-MM-DD HH:mm" у полі Date (див. генератор)
        $d = $null
        if ([datetime]::TryParse($r.Date, [ref]$d)) {
            if ($d -ge $from -and $d -le $now) { $errors7++ }
        }
    }
}

# Побудова HTML
$html = @"
<!doctype html>
<html lang="uk">
<head>
<meta charset="utf-8">
<title>Flight Dashboard 2.0 — CheCha CORE</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  :root { --bg:#0b1020; --card:#0f162e; --muted:#7f8faa; --ok:#23c55e; --warn:#eab308; --err:#ef4444; --txt:#eef3ff; --grid:#2a3557;}
  html,body{margin:0;padding:0;background:var(--bg);color:var(--txt);font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"DejaVu Sans",Arial,sans-serif;}
  .wrap{max-width:1100px;margin:40px auto;padding:0 24px;}
  h1{font-size:28px;margin:0 0 8px}
  .muted{color:var(--muted)}
  .row{display:flex;gap:16px;flex-wrap:wrap;margin-top:16px}
  .card{background:var(--card);border-radius:16px;padding:16px;box-shadow:0 8px 30px rgba(0,0,0,.25);flex:1 1 320px}
  .kpi{display:flex;align-items:center;gap:12px}
  .badge{display:inline-flex;align-items:center;gap:8px;border-radius:999px;padding:6px 12px;font-weight:600}
  .ok{background:color-mix(in srgb, var(--ok) 20%, transparent);border:1px solid var(--ok)}
  .warn{background:color-mix(in srgb, var(--warn) 20%, transparent);border:1px solid var(--warn)}
  .err{background:color-mix(in srgb, var(--err) 20%, transparent);border:1px solid var(--err)}
  table{width:100%;border-collapse:collapse;margin-top:8px}
  th,td{padding:10px 12px;border-bottom:1px solid var(--grid);font-size:14px}
  th{text-align:left;color:var(--muted);font-weight:600}
  .pill{padding:4px 8px;border-radius:8px;background:#182244;display:inline-block}
  .footer{margin:32px 0 16px;color:var(--muted);font-size:13px}
  .head{display:flex;align-items:center;justify-content:space-between;gap:12px}
  .brand{font-weight:700;letter-spacing:.02em}
  .kpi-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:8px}
  .kpi-box{background:#101a38;border:1px solid #1e2a4d;border-radius:12px;padding:12px}
  .kpi-label{font-size:12px;color:var(--muted)}
  .kpi-value{font-size:22px;font-weight:800;margin-top:4px}
</style>
</head>
<body>
  <div class="wrap">
    <div class="head">
      <div>
        <div class="brand">CHECHA CORE — FLIGHT CONTROL 2025</div>
        <h1>Flight Dashboard 2.0</h1>
        <div class="muted">Жива панель стану системи</div>
      </div>
      <div id="badge" class="badge">Loading…</div>
    </div>

    <div class="row">
      <div class="card">
        <div class="kpi">
          <div>
            <div class="muted">Останній звіт</div>
            <div id="last-date" style="font-size:20px;font-weight:700">—</div>
          </div>
        </div>
        <div class="muted" id="warns-label" style="margin-top:10px">Попередження: —</div>
        <div class="kpi-grid">
          <div class="kpi-box">
            <div class="kpi-label">FailTasks (сьогодні)</div>
            <div class="kpi-value" id="kpi-fails">0</div>
          </div>
          <div class="kpi-box">
            <div class="kpi-label">FailRate %</div>
            <div class="kpi-value" id="kpi-failrate">0</div>
          </div>
          <div class="kpi-box">
            <div class="kpi-label">Макс. затримка задач (хв)</div>
            <div class="kpi-value" id="kpi-latency">0</div>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="muted">Matrices</div>
        <div style="margin-top:6px">
          <span class="pill">Restore: <b id="restore-count">0</b></span>
          &nbsp; <span class="pill">Balance: <b id="balance-count">0</b></span>
        </div>
        <div class="kpi-box" style="margin-top:10px">
          <div class="kpi-label">ERROR за 7 днів</div>
          <div class="kpi-value">$errors7</div>
        </div>
      </div>
    </div>

    <div class="card" style="margin-top:16px">
      <div class="muted" style="margin-bottom:6px">Task Health Map</div>
      <table id="tasks">
        <thead>
          <tr><th>Task</th><th>State</th><th>LastRun</th><th>NextRun</th><th>Result</th><th>OK</th></tr>
        </thead>
        <tbody></tbody>
      </table>
    </div>

    <div class="footer">DAO-GOGS • CheCha Flight — Корекція курсу 4.11 • © С.Ч.</div>
  </div>

  <script id="reflex-data" type="application/json">$reflex$</script>
  <script>
    (function(){
      const raw = document.getElementById('reflex-data').textContent.trim();
      const d = JSON.parse(raw);

      const ok = !!d.Status?.Ok;
      const sev = (d.Status?.Severity || (ok ? 'OK' : 'WARN')).toUpperCase();

      const badge = document.getElementById('badge');
      badge.classList.add('badge',
        sev === 'OK' ? 'ok' : (sev === 'ERROR' ? 'err' : 'warn'));
      badge.textContent = (sev === 'OK' ? '✅' : (sev === 'ERROR' ? '⛔' : '⚠️')) + ' REFLEX: ' + sev;

      document.getElementById('last-date').textContent = d.Date || '—';
      const warns = (d.Status?.Warns || []);
      document.getElementById('warns-label').textContent = 'Попередження: ' + (warns.length ? warns.join(' | ') : '—');

      // KPI з JSON
      const kpi = d.KPI || {};
      document.getElementById('kpi-fails').textContent    = kpi.FailTasks ?? 0;
      document.getElementById('kpi-failrate').textContent = (kpi.FailRate ?? 0);
      document.getElementById('kpi-latency').textContent  = (kpi.MaxTaskLatencyMinutes ?? 0);

      // Matrices
      document.getElementById('restore-count').textContent = d.Matrices?.RestoreCount ?? 0;
      document.getElementById('balance-count').textContent = d.Matrices?.BalanceCount ?? 0;

      // Tasks
      const tbody = document.querySelector('#tasks tbody');
      (d.TaskHealth || []).forEach(t => {
        const tr = document.createElement('tr');
        const td = v => { const x = document.createElement('td'); x.textContent = (v ?? '-'); return x; }
        tr.appendChild(td(t.TaskName));
        tr.appendChild(td(t.State));
        tr.appendChild(td(t.LastRunTime ? new Date(t.LastRunTime).toLocaleString() : '-'));
        tr.appendChild(td(t.NextRunTime ? new Date(t.NextRunTime).toLocaleString() : '-'));
        tr.appendChild(td(t.LastTaskResult));
        tr.appendChild(td(t.Ok ? '✅' : '❗'));
        tbody.appendChild(tr);
      });
    })();
  </script>
</body>
</html>
"@

# Вставляємо дані
$html = $html -replace '\$reflex\$', [Regex]::Escape($reflexData) -replace '\\/', '/'
Set-Content -LiteralPath $OutHtml -Value $html -Encoding UTF8

Write-Host "[OK] Згенеровано: $OutHtml (дані: $($latestJson.Name))"


