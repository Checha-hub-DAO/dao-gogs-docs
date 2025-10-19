<#
.SYNOPSIS
  Формує щотижневий Markdown-дайджест за логом post-commit:
  D:\CHECHA_CORE\C03_LOG\BTD-Manifest-Commits.log

.DESCRIPTION
  - Парсить записи комітів (SHA, дата, повідомлення, MANIFEST_SHA256).
  - Діапазон: [WeekStart, WeekEnd], за замовчуванням — останній календарний тиждень
    (понеділок 00:00 → неділя 23:59:59 у твоєму локальному часовому поясі).
  - Генерує: REPORTS\BTD_Manifest_Digest_YYYY-MM-DD_to_YYYY-MM-DD.md
  - Додає/оновлює REPORTS\CHECKSUMS.txt

.PARAMETER WeekStart
  Початок тижня (DateTime). Необов'язковий.

.PARAMETER WeekEnd
  Кінець тижня (DateTime). Необов'язковий.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\TOOLS\Build-WeeklyBTD-Digest.ps1"

.EXAMPLE
  pwsh -NoProfile -File "D:\CHECHA_CORE\TOOLS\Build-WeeklyBTD-Digest.ps1" -WeekStart '2025-10-01' -WeekEnd '2025-10-07'
#>

[CmdletBinding()]
param(
    [datetime]$WeekStart,
    [datetime]$WeekEnd
)

# --- Шляхи ---
$RepoRoot = 'D:\CHECHA_CORE'
$LogPath = Join-Path $RepoRoot 'C03_LOG\BTD-Manifest-Commits.log'
$ReportsDir = Join-Path $RepoRoot 'REPORTS'

# --- Обчислення діапазону за замовчуванням (останній календарний тиждень: Пн–Нд) ---
# Приймаємо локальний час (Europe/Kyiv у твоєму середовищі)
if (-not $WeekStart -or -not $WeekEnd) {
    $now = Get-Date
    # зсув до понеділка цього тижня
    $dow = ([int]$now.DayOfWeek) # 0=Sunday … 6=Saturday
    $offsetToMonday = switch ($dow) { 0 { -6 } 1 { 0 } default { 1 - $dow } }
    $mondayThisWeek = (Get-Date ($now.Date)).AddDays($offsetToMonday)

    # попередній тиждень (останній завершений)
    $WeekStart = $mondayThisWeek.AddDays(-7)
    $WeekEnd = $WeekStart.AddDays(7).AddSeconds(-1)
}

# --- Перевірка середовища ---
$null = New-Item -ItemType Directory -Force -Path $ReportsDir
if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "Лог не знайдено: $LogPath"
}

# --- Парсер логу ---
# Формат очікується як у post-commit hook:
# ------------------------------------------------------------
# Commit: <hash>
# Date  : 2025-10-07 15:45:12 +0300
# Msg   : ...
# MANIFEST_SHA256: <hash or (missing)>

$raw = Get-Content -LiteralPath $LogPath -Raw
$blocks = ($raw -split '[-]{60,}').Where({ $_.Trim() })

$items = foreach ($b in $blocks) {
    $lines = ($b -split "`r?`n").Where({ $_.Trim() })
    $commit = ($lines | Where-Object { $_ -like 'Commit:*' }) -replace '^Commit:\s*', ''
    $dtStr = ($lines | Where-Object { $_ -like 'Date  :*' }) -replace '^Date\s*:', ''
    $msg = ($lines | Where-Object { $_ -like 'Msg   :*' }) -replace '^Msg\s*:', ''
    $msha = ($lines | Where-Object { $_ -like 'MANIFEST_SHA256:*' }) -replace '^MANIFEST_SHA256:\s*', ''

    # Парсимо дату; якщо не вдалось — пропускаємо
    $dt = $null
    [void][datetime]::TryParse($dtStr.Trim(), [ref]$dt)

    if ($dt) {
        [pscustomobject]@{
            CommitHash  = $commit.Trim()
            CommitDate  = $dt
            Message     = $msg.Trim()
            ManifestSHA = $msha.Trim()
        }
    }
}

# --- Фільтр за діапазоном ---
$itemsInRange = $items | Where-Object { $_.CommitDate -ge $WeekStart -and $_.CommitDate -le $WeekEnd } |
    Sort-Object CommitDate

# --- Агрегація ---
$total = $itemsInRange.Count
$missing = ($itemsInRange | Where-Object { $_.ManifestSHA -eq '(missing)' -or [string]::IsNullOrWhiteSpace($_.ManifestSHA) }).Count
$uniqueCommits = ($itemsInRange.CommitHash | Where-Object { $_ } | Select-Object -Unique).Count
$uniqueMsgs = ($itemsInRange.Message    | Where-Object { $_ } | Select-Object -Unique).Count

# --- Побудова Markdown ---
$wStartStr = $WeekStart.ToString('yyyy-MM-dd')
$wEndStr = $WeekEnd.ToString('yyyy-MM-dd')
$outName = "BTD_Manifest_Digest_${wStartStr}_to_${wEndStr}.md"
$outPath = Join-Path $ReportsDir $outName

$md = @()
$md += "# 🧾 BTD Manifest — Щотижневий дайджест"
$md += ""
$md += "**Період:** ${wStartStr} → ${wEndStr}"
$md += ""
$md += "– Загалом записів: **$total**"
$md += "– Унікальних комітів: **$uniqueCommits**"
$md += "– Унікальних повідомлень: **$uniqueMsgs**"
$md += "– MANIFEST_SHA256 missing: **$missing**"
$md += ""
$md += "## Події"
$md += ""
if ($total -eq 0) {
    $md += "_За період подій не зафіксовано._"
}
else {
    $md += "| Дата/час | Commit | Msg | MANIFEST_SHA256 |"
    $md += "|---|---|---|---|"
    foreach ($it in $itemsInRange) {
        $dtCell = $it.CommitDate.ToString('yyyy-MM-dd HH:mm:ss')
        $hash = if ($it.CommitHash) { $it.CommitHash.Substring(0, [Math]::Min(12, $it.CommitHash.Length)) } else { "(n/a)" }
        $msg = if ($it.Message) { $it.Message.Replace('|', '\|') } else { "(n/a)" }
        $sha = if ($it.ManifestSHA) { $it.ManifestSHA } else { "(missing)" }
        $md += "| $dtCell | `$hash | $msg | `$sha |"
    }
}
$md += ""
$md += "## Підсумок"
$md += "- **Охоплення**: $wStartStr → $wEndStr"
$md += "- **Локальний TZ**: $(Get-TimeZone).Id"
$md += "- **Звіт згенеровано**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
$md += ""
$md += "— _С.Ч._"

$md -join "`r`n" | Set-Content -LiteralPath $outPath -Encoding UTF8

# --- Оновити REPORTS\CHECKSUMS.txt ---
$checksPath = Join-Path $ReportsDir 'CHECKSUMS.txt'
$line = "{0}  {1}" -f ((Get-FileHash -Algorithm SHA256 -LiteralPath $outPath).Hash), ("REPORTS\" + $outName)
if (Test-Path -LiteralPath $checksPath) {
    # прибираємо старий рядок для цього файлу (якщо є)
    $all = Get-Content -LiteralPath $checksPath
    $filtered = $all | Where-Object { $_ -notmatch [regex]::Escape($outName) }
    $filtered + $line | Set-Content -LiteralPath $checksPath -Encoding UTF8
}
else {
    $line | Set-Content -LiteralPath $checksPath -Encoding UTF8
}

Write-Host "[OK] Report: $outPath"
Write-Host "[OK] CHECKSUMS updated: $checksPath"

