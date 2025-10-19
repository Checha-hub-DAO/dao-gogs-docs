# D:\CHECHA_CORE\TOOLS\Uninstall-CheChaProfile.ps1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CoreRoot = "D:\CHECHA_CORE",
    [string]$ToolsDir = "D:\CHECHA_CORE\TOOLS",
    [switch]$RemoveToolsFiles,
    [switch]$RemoveScheduledTasks
)

function Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err($m) { Write-Host "[ERR] $m" -ForegroundColor Red }

$profilePath = $PROFILE
if (-not (Test-Path -LiteralPath $profilePath)) {
    Warn "Profile file not found: $profilePath (nothing to remove in profile)"
}
else {
    # 1) Бекап профілю
    $backup = "$profilePath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if ($PSCmdlet.ShouldProcess($profilePath, "Backup -> $backup")) {
        Copy-Item -LiteralPath $profilePath -Destination $backup -Force
        Info "Profile backup: $backup"
    }

    # 2) Видалення CheCha-блоків із профілю
    $raw = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8

    $markers = @(
        'CheCha: auto-open dashboard',
        'CheCha: aliases & helpers',
        'CheCha: PSModulePath \(TOOLS\)'
    )

    $updated = $raw
    foreach ($m in $markers) {
        # Вирізаємо від рядка з маркером до першого пустого рядка після блоку (поблажливо)
        $rx = "(?ms)^\s*#\s*$m\s*\r?\n.*?(?=^\s*#\s*CheCha:|^\s*$|`Z)"
        if ($updated -match $rx) {
            if ($PSCmdlet.ShouldProcess($profilePath, "Remove block: $m")) {
                $updated = [regex]::Replace($updated, $rx, "", 1)
                Ok "Removed profile block: $m"
            }
        }
        else {
            Info "Profile block not found: $m"
        }
    }

    if ($PSCmdlet.ShouldProcess($profilePath, "Write updated profile")) {
        $updated.TrimEnd() + "`r`n" | Set-Content -LiteralPath $profilePath -Encoding UTF8
        Ok "Profile updated: $profilePath"
    }

    # 3) Перезавантажити профіль (не фатально)
    try { . $profilePath; Info "Profile reloaded." } catch { Warn "Reload profile: $($_.Exception.Message)" }
}

# 4) (опц.) Видалення скриптів інфраструктури з TOOLS
if ($RemoveToolsFiles) {
    if (-not (Test-Path -LiteralPath $ToolsDir)) {
        Warn "TOOLS dir not found: $ToolsDir"
    }
    else {
        $files = @(
            "Update-MANIFEST-Metrics.ps1",
            "Update-MANIFEST-SystemPaths.ps1",
            "Update-MANIFEST-Scheduler.ps1",
            "Build-MANIFEST.ps1",
            "Build-Dashboard.ps1",
            "Install-CheChaProfile.ps1",
            "Uninstall-CheChaProfile.ps1" # сам себе — видалимо останнім
        )
        foreach ($f in $files) {
            $p = Join-Path $ToolsDir $f
            if (Test-Path -LiteralPath $p) {
                if ($PSCmdlet.ShouldProcess($p, "Remove file")) {
                    # не видаляємо Uninstall поки не завершимо — відкладемо
                    if ($f -ne "Uninstall-CheChaProfile.ps1") {
                        Remove-Item -LiteralPath $p -Force
                        Ok "Removed: $p"
                    }
                    else {
                        $self = $p
                    }
                }
            }
            else {
                Info "Skip (not found): $p"
            }
        }
    }
}

# 5) (опц.) Видалити задачі планувальника \CHECHA\
if ($RemoveScheduledTasks) {
    try {
        $tasks = Get-ScheduledTask -TaskPath "\CHECHA\" -ErrorAction Stop
        foreach ($t in $tasks) {
            if ($PSCmdlet.ShouldProcess("\CHECHA\$($t.TaskName)", "Unregister-ScheduledTask")) {
                Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath "\CHECHA\" -Confirm:$false
                Ok "Unregistered task: \CHECHA\$($t.TaskName)"
            }
        }
    }
    catch {
        Warn "Scheduler cleanup: $($_.Exception.Message)"
    }
}

# 6) Якщо потрібно — самовидалення деінсталятора
if ($RemoveToolsFiles -and $self -and (Test-Path -LiteralPath $self)) {
    Info "Self-removal staged: $self"
    try {
        # Запускаємо окремий процес, який трохи зачекає й прибере скрипт
        $cmd = "Start-Sleep -Seconds 1; Remove-Item -LiteralPath '$self' -Force"
        Start-Process pwsh -ArgumentList "-NoProfile", "-Command", $cmd -WindowStyle Hidden
        Ok "Uninstaller self-remove scheduled."
    }
    catch {
        Warn "Self-remove failed: $($_.Exception.Message)"
    }
}

Ok "Uninstall routine finished."

