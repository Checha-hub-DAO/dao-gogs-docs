<#  Create-DailyFocus.ps1  — v1.2.1
    -UpdateStatus          : оновлення (логування циклу)
    -UpdateChangelog       : простий запис у CHANGELOG
    -NewVersion            : створення нової версії + SHA256 + Composite + CHECKSUMS
    -VerifyChecksums       : перевірка SHA256 (без змін файлів)
    -AutoFix               : (разом з -VerifyChecksums) — лог у RestoreLog, перерахунок і оновлення CHECKSUMS
    -RegisterTasks         : реєстрація ранкової/вечірньої задачі (schtasks)
    -PassThru              : повернути об’єкт з шляхами
#>

param(
    [string]$Root = ".",
    [switch]$UpdateStatus,
    [switch]$UpdateChangelog,
    [switch]$NewVersion,
    [switch]$VerifyChecksums,
    [switch]$AutoFix,
    [switch]$RegisterTasks,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

# --- Helpers ---
function Get-FileHashHex($path) {
    if (!(Test-Path $path)) { return "" }
    return (Get-FileHash -Algorithm SHA256 -Path $path).Hash
}
function Add-Log($file, $msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $file -Value ("- [{0}] {1}" -f $ts, $msg)
}

# --- Paths ---
$dashPath = Join-Path $Root "FOCUS_Dashboard.md"
$restPath = Join-Path $Root "FOCUS_RestoreLog.md"
$timeline = Join-Path $Root "FOCUS_Timeline.md"
$changelog = Join-Path $Root "CHANGELOG.md"
$checksumFile = Join-Path $Root "FOCUS_CHECKSUMS.txt"
$Date = Get-Date -Format "yyyy-MM-dd"

# --- Verify Checksums (read-only unless -AutoFix) ---
if ($VerifyChecksums) {
    if (!(Test-Path $checksumFile)) {
        Write-Warning "Файл $checksumFile не знайдено."
        exit
    }

    # Витягуємо останній блок SHA256 (4 рядки)
    $lines = Get-Content $checksumFile | Where-Object { $_ -match "SHA256" }
    if ($lines.Count -lt 4) {
        Write-Warning "У $checksumFile недостатньо даних для перевірки."
        exit
    }
    $last = $lines[-4..-1]

    $expected = @{
        Dashboard  = ($last[0] -split "=")[-1].Trim()
        Timeline   = ($last[1] -split "=")[-1].Trim()
        RestoreLog = ($last[2] -split "=")[-1].Trim()
        Composite  = ($last[3] -split "=")[-1].Trim()
    }

    # Поточні хеші (без змін файлів)
    $actual = @{
        Dashboard  = Get-FileHashHex $dashPath
        Timeline   = Get-FileHashHex $timeline
        RestoreLog = Get-FileHashHex $restPath
    }
    $compInput = "$($actual.Dashboard)$($actual.Timeline)$($actual.RestoreLog)"
    $compHash = [System.BitConverter]::ToString(
        (New-Object -TypeName System.Security.Cryptography.SHA256Managed).ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($compInput)
        )
    ) -replace "-", ""
    $actual.Composite = $compHash

    Write-Host "`n=== Verify Checksums ==="
    $allOk = $true
    foreach ($k in 'Timeline', 'Dashboard', 'RestoreLog', 'Composite') {
        if ($expected[$k] -eq $actual[$k]) {
            Write-Host ("{0}: OK ✅" -f $k)
        }
        else {
            Write-Host ("{0}: FAIL ❌ (expected {1}, got {2})" -f $k, $expected[$k], $actual[$k])
            $allOk = $false
        }
    }

    if ($allOk) {
        # ВАЖЛИВО: нічого не пишемо у RestoreLog, щоб не змінювати хеші при перевірці
        Write-Host "All checksums OK."
    }
    else {
        Write-Host "Some checksums FAILED."
        if ($AutoFix) {
            # 1) Лог про застосування AutoFix (це змінить RestoreLog)
            Add-Log $restPath "Checksums AutoFix applied (re-syncing checksums)"

            # 2) Перерахунок ХЕШІВ ПІСЛЯ логу в RestoreLog
            $newDash = Get-FileHashHex $dashPath
            $newTime = Get-FileHashHex $timeline
            $newRest = Get-FileHashHex $restPath
            $newCompInput = "$newDash$newTime$newRest"
            $newComp = [System.BitConverter]::ToString(
                (New-Object -TypeName System.Security.Cryptography.SHA256Managed).ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($newCompInput)
                )
            ) -replace "-", ""

            # 3) Додаємо синхронізований блок у CHECKSUMS
            $entry = @"
Date: $Date
Version: AutoFix
Dashboard : SHA256=$newDash
Timeline  : SHA256=$newTime
RestoreLog: SHA256=$newRest
Composite : SHA256=$newComp
---------------------------------
"@
            Add-Content -Path $checksumFile -Value $entry
            Write-Host "AutoFix completed. Checksums re-synced."
        }
    }
    exit
}

# --- Update Status (лог події циклу у RestoreLog) ---
if ($UpdateStatus) {
    Add-Log $restPath "FOCUS cycle updated"
}

# --- Update Changelog (простий запис) ---
if ($UpdateChangelog) {
    Add-Content -Path $changelog -Value @"
## Update — $Date
- Автоматичне оновлення Dashboard/Timeline/RestoreLog
✍️ С.Ч.
"@
    Write-Host "📌 CHANGELOG оновлено (Update)."
}

# --- New Version (детерміноване авто-інкрементування vX.Y) ---
if ($NewVersion) {
    # Індивідуальні SHA
    $hDash = Get-FileHashHex $dashPath
    $hTime = Get-FileHashHex $timeline
    $hRest = Get-FileHashHex $restPath
    # Composite
    $compInputV = "$hDash$hTime$hRest"
    $compHashV = [System.BitConverter]::ToString(
        (New-Object -TypeName System.Security.Cryptography.SHA256Managed).ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($compInputV)
        )
    ) -replace "-", ""

    # Обчислюємо наступний тег версії
    if (!(Test-Path $changelog)) {
        $ver = "v1.0"
    }
    else {
        $content = Get-Content $changelog -Raw
        $matches = [regex]::Matches($content, "v(\d+)\.(\d+)")
        if ($matches.Count -gt 0) {
            $last = $matches[$matches.Count - 1].Groups
            $major = [int]$last[1].Value
            $minor = [int]$last[2].Value + 1
            $ver = "v{0}.{1}" -f $major, $minor
        }
        else {
            $ver = "v1.0"
        }
    }

    # CHANGELOG
    Add-Content -Path $changelog -Value @"
## $ver — $Date
- Нова версія створена автоматично.
- Файли:
  - Dashboard : SHA256=$hDash
  - Timeline  : SHA256=$hTime
  - RestoreLog: SHA256=$hRest
- Composite SHA256: $compHashV
- Статус: active

✍️ С.Ч.
"@

    # CHECKSUMS
    $entryV = @"
Date: $Date
Version: $ver
Dashboard : SHA256=$hDash
Timeline  : SHA256=$hTime
RestoreLog: SHA256=$hRest
Composite : SHA256=$compHashV
---------------------------------
"@
    Add-Content -Path $checksumFile -Value $entryV
    Write-Host "📌 CHANGELOG оновлено (New Version): $ver"
}

# --- Register Tasks (optional) ---
if ($RegisterTasks) {
    $pwsh = (Get-Command pwsh).Source
    schtasks /Create /SC DAILY /TN "CheCha-Focus-Morning" /ST 07:00 /F /TR "`"$pwsh`" -File `"$PSCommandPath`" -Root `"$Root`" -UpdateStatus"
    schtasks /Create /SC DAILY /TN "CheCha-Focus-Evening" /ST 21:00 /F /TR "`"$pwsh`" -File `"$PSCommandPath`" -Root `"$Root`" -UpdateStatus"
    Write-Host "✅ Зареєстровано задачі: CheCha-Focus-Morning, CheCha-Focus-Evening"
}

# --- Output ---
Write-Host ""
Write-Host "Dashboard : $dashPath"
Write-Host "RestoreLog: $restPath"
Write-Host "Timeline  : $timeline"

if ($PassThru) {
    [PSCustomObject]@{
        Dashboard  = $dashPath
        RestoreLog = $restPath
        Timeline   = $timeline
    }
}


