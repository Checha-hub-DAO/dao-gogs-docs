param(
    [string]$Root = "D:\CHECHA_CORE",
    [string[]]$Modules,
    [string]$ReportDir = "$Root\C03\LOG\weekly_reports",
    [switch]$Csv,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 0) Модулі
if (-not $Modules -or $Modules.Count -eq 0) { $Modules = @('G35', 'G37', 'G43') }
$Modules = $Modules | ForEach-Object {
    if ($_ -is [string] -and $_ -like '*,*') { $_.Split(',') } else { $_ }
} | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique

# 1) Оркестратор
$orch = Join-Path $Root 'C11\C11_AUTOMATION\tools\Checha-Orchestrator.ps1'
if (-not (Test-Path $orch)) { throw "Не знайдено Orchestrator: $orch" }

# 2) Папка звітів
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$rows = @()

# 3) Чи є параметр для фільтрації модулів?
$maybeParam = $null
try {
    $maybeParam = (Get-Command $orch).Parameters.Keys |
        Where-Object { $_ -match '^(Module|Modules|Target|Targets|Workload|Project|Group|Name|Filter)$' } |
        Select-Object -First 1
}
catch { }

# 4) Якщо фільтра нема — знімемо один "глибокий" лог Weekly і з нього виріжемо G-модулі
$deep = $null
if (-not $maybeParam) {
    $deep = Join-Path $ReportDir ("weekly_all_{0}.deep.log" -f $ts)
    (& $orch -Mode Weekly -Root $Root -Quiet:$Quiet -Verbose *>&1) |
        Tee-Object -FilePath $deep | Out-Null
    if (-not (Test-Path $deep)) { New-Item -ItemType File -Path $deep | Out-Null }
}

# 5) Прогін по модулях
foreach ($m in $Modules) {
    $logPath = Join-Path $ReportDir ("verify_weekly_{0}_{1}.log" -f $m, $ts)
    $code = 0

    if ($maybeParam) {
        # адресний запуск
        $ht = @{ Mode = 'Weekly'; Root = $Root; Quiet = $Quiet }
        $ht[$maybeParam] = $m
        (& $orch @ht *>&1) | Tee-Object -FilePath $logPath | Out-Null
        $code = $LASTEXITCODE
    }
    else {
        # фільтр з deep-логу
        Select-String -Path $deep -AllMatches -CaseSensitive:$false `
            -Pattern ("`b{0}`b" -f [regex]::Escape($m)), 'ERROR', 'Exception', 'failed', 'не знайдено', 'denied' |
            Sort-Object LineNumber | ForEach-Object { $_.Line } |
            Set-Content -Encoding UTF8 -LiteralPath $logPath

        # якщо у deep-лозі є "No steps resolved" — беремо код 64 (SKIP)
        $code = if (Select-String -Path $deep -SimpleMatch -Pattern 'No steps resolved' -Quiet) { 64 } else { 0 }
    }

    $status = if ($code -eq 0) { 'OK' }
    elseif ($code -eq 64) { 'SKIP' }
    else { 'FAIL' }

    $rows += [pscustomobject]@{
        Timestamp = Get-Date
        Module    = $m
        Status    = $status
        Code      = $code
        Log       = $logPath
    }
}

# 6) Підсумок у консоль
$rows | Sort-Object Module | Format-Table -AutoSize | Out-String | Write-Host

# 7) CSV (опційно)
if ($Csv) {
    $csvPath = Join-Path $ReportDir "verify_weekly_$ts.csv"
    $rows | Select-Object Timestamp, Module, Status, Code, Log |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    "Saved: $csvPath" | Write-Host
}

# 8) Exit-код: FAIL → 1, інакше 0 (SKIP не є фейлом)
$failCount = ($rows | Where-Object { $_.Status -eq 'FAIL' } | Measure-Object).Count
if ($failCount -gt 0) { exit 1 } else { exit 0 }


