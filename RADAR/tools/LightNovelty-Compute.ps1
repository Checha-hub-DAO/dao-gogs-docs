<#
  LightNovelty-Compute.ps1
  Обчислює метрику "Light-Novelty" для артефактів на основі тегів.
  - Zero7d: частка тегів, які не з'являлись у попередні W днів
  - Rarity30d: рідкість тегів у журналі за H днів (відн. до P95 розподілу)
  - Novelty = wZ*Zero7d + wR*Rarity30d

  Вихід: додає/оновлює колонки LightNovelty, Novelty_ZeroShare_7d, Novelty_Rarity_30d, Novelty_WDays, Novelty_HDays
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = "D:\CHECHA_CORE",
    [string]$CsvPath,
    [int]$ZeroWindowDays = 7,     # W
    [int]$HistoryDays = 30,    # H
    [double]$WZero = 0.6,         # wZ
    [double]$WRarity = 0.4,       # wR
    [switch]$DryRun
)

function W([string]$m, [string]$lvl = "INFO") { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$lvl] $ts $m" }
function SplitTags([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { @() }
    else { ($s -split '[,;|]+' | ForEach-Object { ($_ -as [string]).Trim().ToLower() } | Where-Object { $_ -ne '' }) }
}
function P95($arr) {
    if (-not $arr -or $arr.Count -eq 0) { return 1 }
    $s = $arr | Sort-Object
    $idx = [int][Math]::Floor(0.95 * ([Math]::Max(1, $s.Count) - 1))
    return [double]$s[$idx]
}
function Clamp01([double]$x) { if ($x -lt 0) { 0 } elseif ($x -gt 1) { 1 } else { $x } }

try {
    if ([string]::IsNullOrWhiteSpace($CsvPath)) { $CsvPath = Join-Path $RepoRoot 'RADAR\INDEX\artifacts.csv' }
    if (!(Test-Path -LiteralPath $CsvPath)) { throw "Не знайдено індекс: $CsvPath" }

    $rows = Import-Csv -LiteralPath $CsvPath
    if (-not $rows -or $rows.Count -eq 0) { throw "Порожній CSV" }

    $now = Get-Date
    $histFrom = $now.AddDays( - [Math]::Abs($HistoryDays))
    $zeroFrom = $now.AddDays( - [Math]::Abs($ZeroWindowDays))

    # Підготовка: нормалізовані записи за H днів
    $A = foreach ($r in $rows) {
        $ts = $null; [datetime]::TryParse($r.timestamp, [ref]$ts) | Out-Null
        if ($null -eq $ts) { continue }
        [pscustomobject]@{ ts = $ts; day = $ts.Date; tags = (SplitTags $r.tags) }
    } | Where-Object { $_.ts -ge $histFrom }

    if (-not $A) { W "У вікні H=$HistoryDays днів не знайдено записів." "WARN" }

    # Лічильники по тегах в історичному вікні та у Zero-вікні
    $tagCntHist = @{}
    $tagCntZero = @{}
    foreach ($x in $A) {
        foreach ($t in $x.tags) {
            if (!$t) { continue }
            $tagCntHist[$t] = 1 + ($tagCntHist[$t] | ForEach-Object { $_ })
            if ($x.ts -ge $zeroFrom) { $tagCntZero[$t] = 1 + ($tagCntZero[$t] | ForEach-Object { $_ }) }
        }
    }

    # Розподіл частот для P95 (щоб оцінювати рідкість відносно загального поля)
    $histCounts = @($tagCntHist.Values)
    $p95 = [double](P95 $histCounts); if ($p95 -lt 1) { $p95 = 1 }  # захист від 0

    W ("HistoryDays={0}, ZeroWindowDays={1}, P95(hist tag counts)={2}" -f $HistoryDays, $ZeroWindowDays, [Math]::Round($p95, 2))

    # Розрахунок по кожному рядку
    $updated = 0
    $out = foreach ($r in $rows) {
        $ts = $null; [datetime]::TryParse($r.timestamp, [ref]$ts) | Out-Null
        if ($null -eq $ts) { 
            # все одно додамо колонки порожніми, щоб структура була стабільна
            $r | Add-Member -NotePropertyName LightNovelty -NotePropertyValue $null -Force
            $r | Add-Member -NotePropertyName Novelty_ZeroShare_7d -NotePropertyValue $null -Force
            $r | Add-Member -NotePropertyName Novelty_Rarity_30d -NotePropertyValue $null -Force
            $r | Add-Member -NotePropertyName Novelty_WDays -NotePropertyValue $ZeroWindowDays -Force
            $r | Add-Member -NotePropertyName Novelty_HDays -NotePropertyValue $HistoryDays -Force
            $out += $r; continue
        }

        $tags = SplitTags $r.tags
        if ($tags.Count -eq 0) {
            $r | Add-Member -NotePropertyName LightNovelty -NotePropertyValue 0 -Force
            $r | Add-Member -NotePropertyName Novelty_ZeroShare_7d -NotePropertyValue 0 -Force
            $r | Add-Member -NotePropertyName Novelty_Rarity_30d -NotePropertyValue 0 -Force
            $r | Add-Member -NotePropertyName Novelty_WDays -NotePropertyValue $ZeroWindowDays -Force
            $r | Add-Member -NotePropertyName Novelty_HDays -NotePropertyValue $HistoryDays -Force
            $updated++; $out += $r; continue
        }

        # Zero-7d: частка тегів, яких НЕ було у Zero-вікні
        $zeroFlags = foreach ($t in $tags) {
            $cz = ($tagCntZero.ContainsKey($t) ? $tagCntZero[$t] : 0)
            if ($cz -eq 0) { 1.0 } else { 0.0 }
        }
        $zeroShare = [double]((($zeroFlags | Measure-Object -Average).Average) ?? 0)

        # Rarity-30d: середнє по тегах 1 - (count_H / P95)
        $rars = foreach ($t in $tags) {
            $ch = ($tagCntHist.ContainsKey($t) ? [double]$tagCntHist[$t] : 0.0)
            Clamp01(1.0 - ($ch / $p95))
        }
        $rarity = [double]((($rars | Measure-Object -Average).Average) ?? 0)

        $nov = Clamp01($WZero * $zeroShare + $WRarity * $rarity)

        $r | Add-Member -NotePropertyName LightNovelty -NotePropertyValue ([Math]::Round($nov, 4)) -Force
        $r | Add-Member -NotePropertyName Novelty_ZeroShare_7d -NotePropertyValue ([Math]::Round($zeroShare, 4)) -Force
        $r | Add-Member -NotePropertyName Novelty_Rarity_30d -NotePropertyValue ([Math]::Round($rarity, 4)) -Force
        $r | Add-Member -NotePropertyName Novelty_WDays -NotePropertyValue $ZeroWindowDays -Force
        $r | Add-Member -NotePropertyName Novelty_HDays -NotePropertyValue $HistoryDays -Force

        $updated++; $out += $r
    }

    W "Оновлено рядків: $updated"

    if ($DryRun) { W "DryRun: зміни не записані"; exit 0 }

    $bak = "$CsvPath.bak"; Copy-Item -LiteralPath $CsvPath -Destination $bak -Force
    $tmp = [System.IO.Path]::GetTempFileName()
    $out | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $tmp
    Move-Item -LiteralPath $tmp -Destination $CsvPath -Force
    W "CSV оновлено: $CsvPath"

    $logDir = Join-Path $RepoRoot 'C03_LOG'; if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    Add-Content -Path (Join-Path $logDir 'RADAR_LIGHTNOVELTY_LOG.md') -Encoding UTF8 `
    ("- [{0}] File='{1}' | ZeroWindow={2}d | History={3}d | Updated={4} | Weights(Z={5},R={6})" -f `
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CsvPath, $ZeroWindowDays, $HistoryDays, $updated, $WZero, $WRarity)

    exit 0
}
catch {
    W $_.Exception.Message "ERR"; exit 2
}


