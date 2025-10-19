# === CheCha Smoke Runner ===
# Проганяє Build-WeeklyIndex.ps1 і Generate-WeeklyChecklistReport.ps1,
# пише логи, рахує тривалість, формує SUMMARY і повертає 0 якщо все ок.

$ErrorActionPreference = 'Stop'

$files = @(
    "D:\CHECHA_CORE\TOOLS\Build-WeeklyIndex.ps1",
    "D:\CHECHA_CORE\TOOLS\Generate-WeeklyChecklistReport.ps1"
)

# Аргументи для кожного скрипта
$perScriptArgs = @{
    "D:\CHECHA_CORE\TOOLS\Build-WeeklyIndex.ps1"              = @()
    "D:\CHECHA_CORE\TOOLS\Generate-WeeklyChecklistReport.ps1" = @("-WeekEnd", (Get-Date).Date.AddDays(-1))
}

# Де зберігати логи
$logDir = "D:\CHECHA_CORE\C06_FOCUS\.logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

$results = @()

foreach ($f in $files) {
    $name = Split-Path $f -Leaf
    $args = if ($perScriptArgs.ContainsKey($f)) { $perScriptArgs[$f] } else { @() }
    $log = Join-Path $logDir ("{0}_{1}.log" -f $name, (Get-Date -Format 'yyyyMMdd_HHmmss'))

    Write-Host "▶ Running: $name"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # окремий процес pwsh; збираємо stdout+stderr у лог і в змінну
        $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $f @args 2>&1 | Tee-Object -FilePath $log
        $exit = $LASTEXITCODE
        $sw.Stop()

        $outJoined = ($out | Out-String)

        # Критерій успіху: ExitCode==0 і у виводі немає явних помилок
        $ok = ($exit -eq 0) -and ($outJoined -notmatch 'ParserError|Exception|CategoryInfo')

        $results += [pscustomobject]@{
            Script   = $name
            Status   = if ($ok) { 'Success' } else { 'Failed' }
            Duration = ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
            ExitCode = $exit
            Log      = $log
            Note     = if ($ok) { '' } else { ($out | Select-Object -Last 1) }
        }

        if ($ok) {
            Write-Host ("  ✔ {0}  [{1}]" -f $name, ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)) -ForegroundColor Green
        }
        else {
            Write-Host ("  ✖ {0}  [{1}]" -f $name, ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)) -ForegroundColor Red
            Write-Host ("    See log: {0}" -f $log) -ForegroundColor DarkYellow
        }
    }
    catch {
        $sw.Stop()
        $results += [pscustomobject]@{
            Script   = $name
            Status   = 'Failed'
            Duration = ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
            ExitCode = $LASTEXITCODE
            Log      = $log
            Note     = $_.Exception.Message
        }
        Write-Warning ("Error while running {0}: {1}" -f $name, $_.Exception.Message)
        Write-Host ("    See log: {0}" -f $log) -ForegroundColor DarkYellow
    }
}

# Підсумок
Write-Host ""
Write-Host "===== SUMMARY =====" -ForegroundColor Cyan
$results | Select-Object Script, Status, Duration, ExitCode, Log | Format-Table -AutoSize

# Код повернення: 0 якщо всі Success, інакше 1
$failed = ($results | Where-Object { $_.Status -ne 'Success' })
if ($failed.Count -eq 0) {
    Write-Host "All good ✅"
    exit 0
}
else {
    Write-Host "Some scripts failed ❌ — дивись логи" -ForegroundColor Yellow
    exit 1
}

