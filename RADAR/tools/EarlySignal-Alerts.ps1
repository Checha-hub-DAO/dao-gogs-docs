[CmdletBinding()]
param(
    [string]$RepoRoot = "D:\CHECHA_CORE",
    [string]$CsvPath,
    [int]$DaysBack = 30,
    [int]$LookbackForStats = 30,   # для μ/σ/P95
    [double]$ToxHigh = 0.6,
    [double]$HQScore = 0.7,
    [double]$HQTrust = 0.7,
    [int]$MinCountForToxic = 5
)

function W([string]$m, [string]$lvl = "INFO") { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m" }
function SplitTags([string]$s) { if ([string]::IsNullOrWhiteSpace($s)) { @() } else { ($s -split '[,;|]+' | % { $_.Trim().ToLower() } | ? { $_ }) } }
function TryNum([string]$s) { if ([string]::IsNullOrWhiteSpace($s)) { return $null } $s2 = $s -replace ',', '.'; $n = 0.0; if ([double]::TryParse($s2, [ref]$n)) { $n } else { $null } }
function Pct($arr, [double]$p) { if (-not $arr -or $arr.Count -eq 0) { return 0 } $s = $arr | Sort-Object; $idx = [int][Math]::Floor(($p / 100.0) * ($s.Count - 1)); return $s[$idx] }

try {
    if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
    if (!(Test-Path -LiteralPath $CsvPath)) { throw "Немає індексу: $CsvPath" }

    $rows = Import-Csv -LiteralPath $CsvPath
    if (-not $rows -or $rows.Count -eq 0) { throw "Порожній CSV" }

    $now = Get-Date
    $from = $now.AddDays( - [Math]::Abs($DaysBack))
    $statsFrom = $now.AddDays( - [Math]::Abs($LookbackForStats))

    # Нормалізований набір
    $A = foreach ($r in $rows) {
        $ts = $null; [datetime]::TryParse($r.timestamp, [ref]$ts) | Out-Null
        if ($null -eq $ts) { continue }
        $score = TryNum $r.RadarScore
        $trust = TryNum ($r.SourceTrust ?? $r.Trust)
        $tox = TryNum $r.toxicity_score
        [pscustomobject]@{
            day = $ts.Date; timestamp=$ts
            module = $r.GModule
            tags = SplitTags $r.tags
            score=$score; trust=$trust; tox=$tox
            id=$r.id; title=$r.title; source=$r.source; author=$r.author
        }
    }

    # 1) Базова статистика по модулях за lookback
    $hist = $A | Where-Object { $_.day -ge $statsFrom.Date -and $_.day -lt $now.Date }
    $modDaily = $hist | Group-Object module, day | ForEach-Object {
        [pscustomobject]@{ module = $_.Group[0].module; day = $_.Group[0].day; count = $_.Count }
    }

    $modStats = $modDaily | Group-Object module | ForEach-Object {
        $cnts = ($_.Group | Select-Object -ExpandProperty count)
        [pscustomobject]@{
            module =$_.Name
            mean   = [double]($cnts | Measure-Object -Average).Average
            std    = [double][Math]::Sqrt((($cnts | ForEach-Object { ($_ - ($_ | Measure-Object -Average).Average) * * 2 }) | Measure-Object -Sum).Sum / [Math]::Max(1, ($cnts.Count)))
            p95    = [double](Pct $cnts 95)
        }
    }

    # 2) Поточне вікно (24h) — підрахунки
    $todayFrom = $now.AddDays(-1)
    $cur = $A | Where-Object { $_.timestamp -ge $todayFrom }

    $curByMod = $cur | Group-Object module | ForEach-Object {
        [pscustomobject]@{ module = $_.Name; count = $_.Count; avgTox = [double](($_.Group | ? { $_.tox -ne $null } | Measure-Object tox -Average).Average) }
    }

    # Піки по модулях
    $alerts = New-Object System.Collections.Generic.List[object]
    foreach ($m in $curByMod) {
        if ([string]::IsNullOrWhiteSpace($m.module)) { continue }
        $st = $modStats | Where-Object { $_.module -eq $m.module }
        $mean = ($st ? $st.mean : 0); $std = ($st ? $st.std : 0); $p95 = ($st ? $st.p95 : 0)
        if ($m.count -gt ($mean + 2 * $std)) { $alerts.Add([pscustomobject]@{type = 'M-PEAK'; module = $m.module; value = $m.count; ref = ("{0}+2σ" -f [Math]::Round($mean, 2)); note = 'module spike (24h)' } ) }
        if ($m.avgTox -ge $ToxHigh -and $m.count -ge $MinCountForToxic) { $alerts.Add([pscustomobject]@{type = 'TOX-HIGH'; module = $m.module; value = [Math]::Round($m.avgTox, 2); ref = ("count≥{0}" -f $MinCountForToxic); note = 'high toxicity (24h)' } ) }
    }

    # HQ-сигнали (артефакти з високим скором і довірою)
    $hq = $cur | Where-Object { ($_.score -ne $null -and $_.score -ge $HQScore) -and ($_.trust -ne $null -and $_.trust -ge $HQTrust) }
    foreach ($x in $hq) {
        $alerts.Add([pscustomobject]@{ type = 'HQ-SIGNAL'; module = $x.module; value = $x.score; ref = ("trust {0}" -f [Math]::Round($x.trust, 2)); id = $x.id; title = $x.title; source = $x.source })
    }

    # Теги: пік проти P95 історії
    # Рахуємо історичний щоденний розподіл по тегах
    $tagDaily = foreach ($r in $hist) {
        foreach ($t in $r.tags) { [pscustomobject]@{ tag = $t; day = $r.day } }
    } | Group-Object tag, day | ForEach-Object { [pscustomobject]@{ tag = $_.Group[0].tag; day = $_.Group[0].day; count = $_.Count } }

    $tagP95 = $tagDaily | Group-Object tag | ForEach-Object {
        $cnts = $_.Group | Select-Object -ExpandProperty count
        [pscustomobject]@{ tag = $_.Name; p95 = [double](Pct $cnts 95) }
    }

    $curTags = foreach ($r in $cur) { foreach ($t in $r.tags) { $t } } | Group-Object | ForEach-Object { [pscustomobject]@{ tag = $_.Name; count = $_.Count } }
    foreach ($t in $curTags) {
        $ref = ($tagP95 | Where-Object { $_.tag -eq $t.tag }).p95
        if ($null -eq $ref) { $ref = 0 }
        if ($t.count -gt $ref) { $alerts.Add([pscustomobject]@{ type = 'T-PEAK'; tag = $t.tag; value = $t.count; ref = ("P95={0}" -f $ref); note = 'tag spike (24h)' }) }
    }

    # Вивід CSV
    $outDir = Join-Path $RepoRoot 'RADAR\REPORTS'; if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $range = ("{0}_to_{1}" -f $from.ToString('yyyy-MM-dd'), $now.ToString('yyyy-MM-dd'))
    $csvPath = Join-Path $outDir ("EarlySignals_{0}.csv" -f $range)
    $alerts | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath
    W "CSV: $csvPath"

    # Markdown для C06_FOCUS
    $focusDir = Join-Path $RepoRoot 'C06_FOCUS\ALERTS'; if (!(Test-Path $focusDir)) { New-Item -ItemType Directory -Force -Path $focusDir | Out-Null }
    $md = Join-Path $focusDir ("EarlySignals_{0}.md" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    $lines = @("# Early Signals (24h)", "", "*Згенеровано:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "")
    if ($alerts.Count -eq 0) { $lines += "_Подій не виявлено._" }
    else {
        foreach ($a in $alerts) {
            $desc = switch ($a.type) {
                'M-PEAK' { "**M-PEAK** · модуль: `$( $a.module )` · count: $( $a.value ) · ref: $( $a.ref )" }
                'TOX-HIGH' { "**TOX-HIGH** · модуль: `$( $a.module )` · avgTox: $( $a.value ) · $( $a.ref )" }
                'HQ-SIGNAL' { "**HQ-SIGNAL** · модуль: `$( $a.module )` · score: $( [Math]::Round($a.value,2) ) · $( $a.ref )" + ($(if ($a.title) { " · **" + $a.title + "**" } else { "" })) }
                'T-PEAK' { "**T-PEAK** · тег: `$( $a.tag )` · count: $( $a.value ) · ref: $( $a.ref )" }
                default { "**$($a.type)**" }
            }
            $lines += "- $desc"
        }
    }
    [IO.File]::WriteAllLines($md, $lines, (New-Object System.Text.UTF8Encoding($true)))
    W "FOCUS MD: $md"

    # Лог
    $logDir = Join-Path $RepoRoot 'C03_LOG'; if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    Add-Content -Path (Join-Path $logDir 'RADAR_EARLYSIGNAL_LOG.md') -Encoding UTF8 ("- [{0}] Alerts={1} | CSV='{2}' | MD='{3}'" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $alerts.Count, $csvPath, $md)

    exit 0
}
catch {
    W $_.Exception.Message "ERR"; exit 2
}


