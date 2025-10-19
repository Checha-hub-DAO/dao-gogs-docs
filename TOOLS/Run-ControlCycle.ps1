<#
.SYNOPSIS
  Контрольний цикл: Verify → Score → Summary → (опц.) Archive.
  Містить:
   - коректне визначення VerifyRoot (поважає, якщо передали ...\WEEKLY)
   - авто-стейджинг з кореня, якщо WEEKLY відсутній
   - гарантію існування ARCHIVE\YYYY під VerifyRoot

.EXIT CODES
  0 — успіх
  1 — попередження/помилки кроку Verify
  2 — попередження/помилки кроку Score
  3 — попередження/помилки Summary/Archive
#>

[CmdletBinding()]
param(
    [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
    [string]$C03 = "D:\CHECHA_CORE\C03_LOG",
    [string]$C07 = "D:\CHECHA_CORE\C07_ANALYTICS",
    [string]$C12ChecksumsGlob = "D:\CHECHA_CORE\C03_LOG\VerifyChecksums_*.csv",
    [switch]$DoArchive,
    [int]$ArchiveSinceHours = 48
)

# ===== helpers =====
function Write-Log([string]$m) {
    $p = Join-Path $C03 "control\Run-ControlCycle.log"
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line; try { $null = $line | Tee-Object -FilePath $p -Append } catch {}
}
function Ensure-Dir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
# ====================

Ensure-Dir (Join-Path $C03 "control")
Write-Log "START Run-ControlCycle"

# ---------- 0) Detect WEEKLY / set VerifyRoot ----------
$VerifyRoot = $ReportsRoot
$weeklyLeaf = (Split-Path -Leaf $ReportsRoot)

if ($weeklyLeaf -ieq 'WEEKLY') {
    # Користувач явно дав ...\WEEKLY → використовуємо як VerifyRoot
    Write-Log "[INFO] WEEKLY root explicitly provided → using as VerifyRoot."
}
else {
    # Шукаємо WEEKLY всередині ReportsRoot
    $weeklyBase = Join-Path $ReportsRoot "WEEKLY"
    $hasWeekly = $false
    if (Test-Path -LiteralPath $weeklyBase) {
        # Випадок A: WEEKLY\<YYYY>\<YYYY-MM-DD_to_YYYY-MM-DD>
        $hasYearRange = Get-ChildItem -LiteralPath $weeklyBase -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\\d{4}\\\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$' } |
            Select-Object -First 1
        # Випадок B: WEEKLY\<YYYY-MM-DD_to_YYYY-MM-DD>
        $hasFlatRange = Get-ChildItem -LiteralPath $weeklyBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$' } |
            Select-Object -First 1
        if ($hasYearRange -or $hasFlatRange) { $hasWeekly = $true }
    }

    if (-not $hasWeekly) {
        # Авто-стейджинг з файлів у корені ReportsRoot
        Write-Log "[INFO] WEEKLY not found → staging from root files…"
        $stage = "D:\CHECHA_CORE\REPORTS_STAGED"
        if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force $stage }
        Ensure-Dir $stage

        $rx = '^WeeklyChecklist_(?<from>\d{4}-\d{2}-\d{2})_to_(?<to>\d{4}-\d{2}-\d{2})\.(?<ext>md|html|csv|xlsx)$'
        $rootFiles = Get-ChildItem -LiteralPath $ReportsRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $rx }

        foreach ($f in $rootFiles) {
            $null = ($f.Name -match $rx)
            $from = $matches['from']; $to = $matches['to']; $year = $from.Substring(0, 4)
            $weekDir = Join-Path $stage ("WEEKLY\{0}\{1}_to_{2}" -f $year, $from, $to)
            Ensure-Dir $weekDir
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $weekDir $f.Name) -Force

            foreach ($ext in @("html", "csv", "xlsx")) {
                $cand = Join-Path $ReportsRoot ("WeeklyChecklist_{0}_to_{1}.{2}" -f $from, $to, $ext)
                if (Test-Path -LiteralPath $cand) {
                    Copy-Item -LiteralPath $cand -Destination (Join-Path $weekDir (Split-Path $cand -Leaf)) -Force
                }
            }
        }

        # Якщо нічого не зібрали — створимо 2 стуби (попер. і поточний тижні)
        if (-not (Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction SilentlyContinue)) {
            function Get-IsoMonday([datetime]$d) {
                $dow = [int]$d.DayOfWeek
                $shift = ($dow - 1); if ($shift -lt 0) { $shift = 6 }
                return (Get-Date $d.Date).AddDays(-$shift)
            }
            foreach ($offset in @(-7, 0)) {
                $s = (Get-IsoMonday (Get-Date).AddDays($offset))
                $e = $s.AddDays(6)
                $year = $s.ToString('yyyy')
                $range = "{0}_to_{1}" -f $s.ToString('yyyy-MM-dd'), $e.ToString('yyyy-MM-dd')
                $weekDir = Join-Path $stage ("WEEKLY\{0}\{1}" -f $year, $range)
                Ensure-Dir $weekDir
                $stub = Join-Path $weekDir ("WeeklyChecklist_{0}.md" -f $range)
                if (-not (Test-Path -LiteralPath $stub)) {
                    @(
                        "---", "title: Weekly Checklist (stub)", "range: $range", "---",
                        "", "# Weekly Checklist (stub)", "- Auto-staged"
                    ) | Set-Content -LiteralPath $stub -Encoding UTF8
                }
            }
        }

        $VerifyRoot = $stage
        Write-Log "[INFO] Staged WEEKLY at $VerifyRoot"
    }
    else {
        $VerifyRoot = $weeklyBase
        Write-Log "[INFO] Using WEEKLY at $VerifyRoot"
    }
}

# ---------- ensure ARCHIVE under VerifyRoot ----------
$archiveRoot = Join-Path $VerifyRoot "ARCHIVE"
if (-not (Test-Path -LiteralPath $archiveRoot)) {
    New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
}
$yearDir = Join-Path $archiveRoot (Get-Date -Format 'yyyy')
if (-not (Test-Path -LiteralPath $yearDir)) {
    New-Item -ItemType Directory -Path $yearDir -Force | Out-Null
}

# ---------- 1) VERIFY ----------
$verifyCompat = "D:\CHECHA_CORE\TOOLS\Verify-ArchiveChecksums_Compat.ps1"
$verifyLegacy = "D:\CHECHA_CORE\TOOLS\Verify-ArchiveChecksums.ps1"
$verify = if (Test-Path $verifyCompat) { $verifyCompat } else { $verifyLegacy }

if (Test-Path $verify) {
    Write-Log ("Step1: {0} …" -f (Split-Path -Leaf $verify))
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass `
            -File $verify `
            -ReportsRoot $VerifyRoot `
            -RebuildIfMissing -ShowExtras -SummaryOnly -CsvReport
        if ($LASTEXITCODE -ne 0) { Write-Log "[WARN] Verify finished with rc=$LASTEXITCODE"; $verifyRc = 1 } else { $verifyRc = 0 }
    }
    catch {
        Write-Log ("[ERR] Verify failed: {0}" -f $_.Exception.Message); $verifyRc = 1
    }
}
else {
    Write-Log ("[WARN] Script not found: {0}" -f $verify); $verifyRc = 1
}

# ---------- 2) SCORE ----------
$score = "D:\CHECHA_CORE\TOOLS\Update-IntegrityScore.ps1"
if (Test-Path $score) {
    Write-Log "Step2: Update-IntegrityScore.ps1 …"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass `
            -File $score `
            -ChecksumsGlob $C12ChecksumsGlob `
            -OutCsv (Join-Path $C07 "C12_IntegrityScore.csv") `
            -LogPath (Join-Path $C07 "logs\Update-IntegrityScore.log")
        if ($LASTEXITCODE -ne 0) { Write-Log "[WARN] IntegrityScore rc=$LASTEXITCODE"; $scoreRc = 1 } else { $scoreRc = 0 }
    }
    catch {
        Write-Log "[ERR] IntegrityScore failed: $($_.Exception.Message)"; $scoreRc = 1
    }
}
else {
    Write-Log "[WARN] Script not found: $score"; $scoreRc = 1
}

# ---------- 3) SUMMARY ----------
$summary = "D:\CHECHA_CORE\TOOLS\Build-ControlSummary.ps1"
if (Test-Path $summary) {
    Write-Log "Step3: Build-ControlSummary.ps1 …"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass `
            -File $summary `
            -OutDir (Join-Path $C03 "control") `
            -LogPath (Join-Path $C03 "control\Run-Build-ControlSummary.log")
        if ($LASTEXITCODE -ne 0) { Write-Log "[WARN] Summary rc=$LASTEXITCODE"; $sumRc = 1 } else { $sumRc = 0 }
    }
    catch {
        Write-Log "[ERR] Summary failed: $($_.Exception.Message)"; $sumRc = 1
    }
}
else {
    Write-Log "[WARN] Script not found: $summary"; $sumRc = 1
}

# ---------- 3.5) C13 Learning Feedback ----------
$c13 = "D:\CHECHA_CORE\TOOLS\New-C13LearningFeedback.ps1"
if (Test-Path $c13) {
    Write-Log "Step3.5: New-C13LearningFeedback.ps1 …"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass `
            -File $c13 `
            -WeeklyRoot $VerifyRoot `
            -OutDir "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK" `
            -WindowWeeks 4 `
            -LogPath "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\logs\New-C13LearningFeedback.log"
        if ($LASTEXITCODE -ne 0) { Write-Log "[WARN] C13 rc=$LASTEXITCODE" }
    }
    catch {
        Write-Log "[ERR] C13 failed: $($_.Exception.Message)"
    }
}

# ---------- 3.8) Update MANIFEST Metrics ----------
$updMetrics = "D:\CHECHA_CORE\TOOLS\Update-MANIFEST-Metrics.ps1"
if (Test-Path $updMetrics) {
    Write-Log "Step3.8: Update-MANIFEST-Metrics.ps1 …"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass `
            -File $updMetrics `
            -ManifestPath "D:\CHECHA_CORE\MANIFEST.md" `
            -ScoreCsv     "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv" `
            -C13LatestMd  "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md" `
            -ScoreHistory 3 -C13Lines 6 `
            -LogPath      (Join-Path $C03 "control\Update-MANIFEST-Metrics.log")
    }
    catch { Write-Log "[WARN] MANIFEST metrics failed: $($_.Exception.Message)" }
}

# ---------- 4) ARCHIVE (optional) ----------
$arcRc = 0
if ($DoArchive) {
    $archive = "D:\CHECHA_CORE\TOOLS\Archive-Reports.ps1"
    if (Test-Path $archive) {
        Write-Log "Step4: Archive-Reports.ps1 …"
        try {
            # Якщо є WEEKLY — архів покладемо в WEEKLY\ARCHIVE\YYYY; інакше — в REPORTS\ARCHIVE\YYYY
            $weeklyBase = (Split-Path -Leaf $VerifyRoot) -ieq 'WEEKLY' ? $VerifyRoot : (Join-Path $ReportsRoot 'WEEKLY')
            $outDir = (Test-Path $weeklyBase) ? (Join-Path $weeklyBase ("ARCHIVE\{0}" -f (Get-Date -Format 'yyyy'))) : (Join-Path $ReportsRoot ("ARCHIVE\{0}" -f (Get-Date -Format 'yyyy')))

            pwsh -NoProfile -ExecutionPolicy Bypass `
                -File $archive `
                -ReportsRoot $VerifyRoot `
                -SinceHours $ArchiveSinceHours `
                -OutDir $outDir `
                -NamePrefix "CheCha_Weekly"
            if ($LASTEXITCODE -ne 0) { Write-Log "[WARN] Archive rc=$LASTEXITCODE"; $arcRc = 1 }
        }
        catch {
            Write-Log "[ERR] Archive failed: $($_.Exception.Message)"; $arcRc = 1
        }
    }
    else {
        Write-Log "[WARN] Script not found: $archive"; $arcRc = 1
    }
}

# ---------- 4.5) Build Dashboard ----------
$buildDash = "D:\CHECHA_CORE\TOOLS\Build-Dashboard.ps1"
if (Test-Path $buildDash) {
    Write-Log "Step4.5: Build-Dashboard.ps1 …"
    try {
        pwsh -NoProfile -ExecutionPolicy Bypass `
            -File $buildDash `
            -OutPath "D:\CHECHA_CORE\Dashboard.md" `
            -ManifestPath "D:\CHECHA_CORE\MANIFEST.md" `
            -WeeklyRoot   $VerifyRoot `
            -ScoreCsv     "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv" `
            -C13LatestMd  "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md" `
            -ControlLogDir (Join-Path $C03 'control') `
            -ArchiveShow 5
    }
    catch { Write-Log "[WARN] Build-Dashboard failed: $($_.Exception.Message)" }
}

# ---------- Exit code ----------
$rc = 0
if ($verifyRc -ne 0) { $rc = 1 }
if ($scoreRc -ne 0) { $rc = 2 }
if ($sumRc -ne 0) { $rc = 3 }
if ($arcRc -ne 0) { if ($rc -eq 0) { $rc = 3 } }

Write-Log ("END Run-ControlCycle (rc={0})" -f $rc)
exit $rc

