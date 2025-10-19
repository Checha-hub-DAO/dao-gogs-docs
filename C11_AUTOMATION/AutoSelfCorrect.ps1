[CmdletBinding()]
param(
    [string]$Root = "D:\CHECHA_CORE",
    [switch]$DryRun,

    # Пороги
    [int]$WarnFailTasksThreshold = 1,   # >=1 задачі з Result≠0 → WARN
    [int]$ErrorFailTasksThreshold = 2    # >=2 задач → ERROR
)

function Log([string]$m) { $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Write-Host "[$ts] $m" }

$ReflexDir = Join-Path $Root "C07_ANALYTICS\Reflex"
$FocusDir = Join-Path $Root "C06_FOCUS"
$IncDir = Join-Path $FocusDir "Incidents"
$restoreMd = Join-Path $FocusDir "FOCUS_RestoreLog.md"

$jr = Get-ChildItem -LiteralPath $ReflexDir -Filter "ReflexReport_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $jr) { Log "Reflex JSON не знайдено"; exit 0 }

$d = Get-Content -LiteralPath $jr.FullName -Raw | ConvertFrom-Json

# --- Обчислюємо фактичну Severity, навіть якщо її нема в JSON ---
$ok = !!$d.Status.Ok
$severity = $d.Status.Severity
$warns = @($d.Status.Warns | Where-Object { $_ -ne $null })

$tasks = @($d.TaskHealth)
$bad = @($tasks | Where-Object { -not $_.Ok })
$badCnt = $bad.Count

# Матриці/логи як тригери
$restoreRows = [int]($d.Matrices.RestoreCount   | ForEach-Object { $_ }) 
$balanceRows = [int]($d.Matrices.BalanceCount   | ForEach-Object { $_ })
$restoreFound = [bool]$d.Restore.Found

# ERROR-умови:
#  - немає RestoreLog АБО обидві матриці порожні
#  - провалено >= ErrorFailTasksThreshold задач
$computedSeverity = "OK"
if (-not $restoreFound -or (($restoreRows -eq 0) -and ($balanceRows -eq 0))) { $computedSeverity = "ERROR" }
elseif ($badCnt -ge $ErrorFailTasksThreshold) { $computedSeverity = "ERROR" }
elseif (-not $ok -or $warns.Count -gt 0 -or $badCnt -ge $WarnFailTasksThreshold) { $computedSeverity = "WARN" }

# Якщо в JSON вже ERROR — залишаємо ERROR як вищий рівень
if ($severity -eq "ERROR") { $computedSeverity = "ERROR" }
elseif ($severity -eq "WARN" -and $computedSeverity -eq "OK") { $computedSeverity = "WARN" }

Log ("Стан (computed): {0}; Fails={1}; RestoreRows={2}; BalanceRows={3}; RestoreFound={4}" -f $computedSeverity, $badCnt, $restoreRows, $balanceRows, $restoreFound)

# ---- ДІЇ ЗАЛЕЖНО ВІД РІВНЯ ----
$didActions = @()

function Run-Task([string]$name) {
    try {
        if ($DryRun) { Log "[DRY] schtasks /Run /TN `"$name`"" }
        else { schtasks /Run /TN "$name" | Out-Null; Log "Перезапущено: $name"; $script:didActions += "Restart:$name" }
    }
    catch { Log "Помилка запуску $name: $($_.Exception.Message)" }
}

function Append-RestoreNote([string]$text) {
    if ($DryRun) { Log "[DRY] Append → $restoreMd :: $text" }
    else {
        Add-Content -LiteralPath $restoreMd -Value $text -Encoding UTF8
        Log "Додано нотатку у FOCUS_RestoreLog.md"
    }
}

function Ensure-Incident([string]$title, [string[]]$details) {
    $null = New-Item -ItemType Directory -Force -Path $IncDir -ErrorAction SilentlyContinue
    $id = (Get-Date -Format 'yyyyMMdd_HHmm')
    $path = Join-Path $IncDir ("INC_{0}.md" -f $id)
    $md = @()
    $md += "# ⚠️ $title"
    $md += "**Дата:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $md += "**Reflex JSON:** $($jr.Name)"
    $md += ""
    if ($details) { $md += "## Деталі"; $md += ($details -join "`r`n") }
    $md += ""
    if ($tasks) {
        $md += "## Task Health (провали)"
        $md += "| Task | State | LastRun | Result |"
        $md += "|:-----|:------|:--------|:------:|"
        foreach ($t in $bad) {
            $lr = if ($t.LastRunTime) { (Get-Date $t.LastRunTime).ToString("yyyy-MM-dd HH:mm:ss") } else { "-" }
            $md += "| {0} | {1} | {2} | {3} |" -f $t.TaskName, $t.State, $lr, $t.LastTaskResult
        }
    }
    if (-not $DryRun) { Set-Content -LiteralPath $path -Value ($md -join "`r`n") -Encoding UTF8 }
    Log "Інцидент зафіксовано: $path"
}

# Спільні: підготувати список задач для перезапуску
$restartTasks = @("LeaderIntel-Daily", "Evening-RestoreLog")
if ($computedSeverity -eq "ERROR") {
    # Для ERROR — розширений список
    $restartTasks = @("LeaderIntel-Daily", "Evening-RestoreLog", "MorningPanel-RestoreTop3", "CHECHA_Weekly_Publish")
}

switch ($computedSeverity) {
    "OK" {
        Log "OK — корекція не потрібна."
        break
    }
    "WARN" {
        Log "WARN — виконую м’яку корекцію."
        foreach ($t in $restartTasks) { Run-Task $t }
        Append-RestoreNote "- [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] AutoSelfCorrect: WARN; перезапущено: $($restartTasks -join ', ')"
        # Перегенеруємо HTML-панель
        $upd = Join-Path $Root "C06_FOCUS\Dashboard\Render-FlightDashboardHTML.ps1"
        if (Test-Path $upd -and -not $DryRun) { pwsh -NoProfile -ExecutionPolicy Bypass -File $upd | Out-Null; Log "Панель оновлено" }
        break
    }
    "ERROR" {
        Log "ERROR — виконую посилену корекцію."
        foreach ($t in $restartTasks) { Run-Task $t }

        # Додаткові дії: очистка тимчасових lock-файлів для матриць (якщо використовуються)
        $tmp = Join-Path $Root "C07_ANALYTICS\_tmp"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $tmp | Out-Null
            Get-ChildItem -LiteralPath $tmp -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Log "Очищено тимчасові файли: $tmp"
        }
        else {
            Log "[DRY] Очистка тимчасових файлів: $tmp"
        }

        # Інцидент + нотатка
        Ensure-Incident "CheCha • ERROR-рівень у Reflex" @(
            "- RestoreFound: $restoreFound"
            "- RestoreRows: $restoreRows; BalanceRows: $balanceRows"
            "- FailedTasks: $badCnt → $($bad | ForEach-Object {$_.TaskName} -join ', ')"
            "- Warns: $($warns -join ' | ')"
        )
        Append-RestoreNote "- [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] AutoSelfCorrect: **ERROR**; дії: перезапуски + очистка tmp + інцидент"

        # Рендер панелі
        $upd = Join-Path $Root "C06_FOCUS\Dashboard\Render-FlightDashboardHTML.ps1"
        if (Test-Path $upd -and -not $DryRun) { pwsh -NoProfile -ExecutionPolicy Bypass -File $upd | Out-Null; Log "Панель оновлено" }
        break
    }
}

# Код виходу (для можливого даунстріму)
switch ($computedSeverity) {
    "OK" { exit 0 }
    "WARN" { exit 1 }
    "ERROR" { exit 2 }
}


