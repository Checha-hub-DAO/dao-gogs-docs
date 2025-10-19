<#
.SYNOPSIS
  Формує контрольний підсумок (Control Summary) для CHECHA_CORE.

.DESCRIPTION
  Збирає ключові артефакти звітності (WeeklyChecklist, VerifyChecksums тощо),
  формує Markdown-підсумок з YAML front-matter і веде лог.
  Підтримує DryRun, а також опційну інтеграцію IntegrityScore.

.PARAMETER ReportsRoot
  Корінь директорії зі звітами.

.PARAMETER OutDir
  Куди писати ControlSummary_*.md.

.PARAMETER LogPath
  Шлях до лог-файла.

.PARAMETER DryRun
  Якщо задано — нічого не записує, лише моделює.

.PARAMETER IntegrateIntegrityScore
  Якщо задано — після формування підсумку викликає Update-IntegrityScore.ps1.

.PARAMETER ChecksumsGlob
  Маска пошуку останнього CSV VerifyChecksums.

.PARAMETER IntegrityScoreCsv
  Куди писати C12_IntegrityScore.csv (для Update-IntegrityScore.ps1).

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File "D:\CHECHA_CORE\TOOLS\Build-ControlSummary.ps1" `
    -DryRun `
    -OutDir "D:\CHECHA_CORE\C03_LOG\control" `
    -LogPath "D:\CHECHA_CORE\C03_LOG\control\Run-Build-ControlSummary.log"
#>

[CmdletBinding()]
param(
    [string]$ReportsRoot = "D:\CHECHA_CORE\REPORTS",
    [string]$OutDir = "D:\CHECHA_CORE\C03_LOG\control",
    [string]$LogPath = "D:\CHECHA_CORE\C03_LOG\control\Run-Build-ControlSummary.log",
    [switch]$DryRun,
    [switch]$IntegrateIntegrityScore,

    # джерело VerifyChecksums (логів перевірки)
    [string]$ChecksumsGlob = "D:\CHECHA_CORE\C03_LOG\VerifyChecksums_*.csv",
    # ціль C12_IntegrityScore
    [string]$IntegrityScoreCsv = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv"
)

#region helpers
function Ensure-Dir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line
    try { $null = $line | Tee-Object -FilePath $LogPath -Append } catch { }
}

function Upsert-YamlFrontmatter {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][hashtable]$Pairs
    )
    # шукаємо перший front-matter: --- ... ---
    $rx = '^(?<pre>---\s*[\r\n]+)(?<yaml>.*?)(?<post>[\r\n]+---\s*)'
    $m = [regex]::Match($Text, $rx, 'Singleline, Multiline')
    if (!$m.Success) {
        # немає front-matter — створюємо
        $yamlLines = @()
        foreach ($k in $Pairs.Keys) { $yamlLines += ("{0}: {1}" -f $k, $Pairs[$k]) }
        return ("---`n{0}`n---`n{1}" -f ($yamlLines -join "`n"), $Text)
    }

    $pre = $m.Groups['pre'].Value
    $yaml = $m.Groups['yaml'].Value
    $post = $m.Groups['post'].Value
    $body = $Text.Substring($m.Index + $m.Length)

    # простий парс YAML (k: v) построчно
    $map = @{}
    foreach ($line in $yaml -split "\r?\n") {
        if ($line -match '^\s*([^:#]+)\s*:\s*(.*)\s*$') {
            $map[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    foreach ($k in $Pairs.Keys) { $map[$k] = [string]$Pairs[$k] }

    $newYaml = ($map.GetEnumerator() | Sort-Object Name | ForEach-Object {
            "{0}: {1}" -f $_.Key, $_.Value
        }) -join "`n"

    return ("{0}{1}{2}{3}" -f $pre, $newYaml, $post, $body)
}
#endregion helpers

# підготовка
Ensure-Dir (Split-Path -Parent $LogPath)
Ensure-Dir $OutDir

# === Inject: show IntegrityScore & C13 note ===
try {
    $scoreCsv = "D:\CHECHA_CORE\C07_ANALYTICS\C12_IntegrityScore.csv"
    if (Test-Path $scoreCsv) {
        $scoreRows = Import-Csv -LiteralPath $scoreCsv | Sort-Object Date -Descending
        $latestScore = $scoreRows | Select-Object -First 1
        if ($latestScore) {
            $scoreLine = "*IntegrityScore:* **$($latestScore.IntegrityScore)** (at $($latestScore.Date))"
            Add-Content -LiteralPath $OutputMdPath -Value ""
            Add-Content -LiteralPath $OutputMdPath -Value "## Integrity"
            Add-Content -LiteralPath $OutputMdPath -Value $scoreLine
        }
    }

    $c13latest = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md"
    if (Test-Path $c13latest) {
        Add-Content -LiteralPath $OutputMdPath -Value ""
        Add-Content -LiteralPath $OutputMdPath -Value "## Learning Feedback"
        Add-Content -LiteralPath $OutputMdPath -Value "[See latest C13 summary](D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\LATEST.md)"
    }
}
catch { }
# === /Inject ===

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
Write-Log "START Build-ControlSummary (DryRun=$($DryRun.IsPresent))"
Write-Log "ReportsRoot=$ReportsRoot"
Write-Log "OutDir=$OutDir"

# 1) Збір артефактів
$weekly = @()
try {
    if (Test-Path -LiteralPath $ReportsRoot) {
        $weekly = Get-ChildItem -LiteralPath $ReportsRoot -Filter "WeeklyChecklist_*.md" -Recurse -ErrorAction SilentlyContinue
    }
    else {
        Write-Log "[WARN] ReportsRoot not found: $ReportsRoot"
    }
}
catch {
    Write-Log "[ERR] Weekly scan failed: $($_.Exception.Message)"
}

$latestChecksCsv = $null
try {
    $latestChecksCsv = Get-ChildItem -Path $ChecksumsGlob -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1
    if ($latestChecksCsv) {
        Write-Log ("Found VerifyChecksums CSV: {0}" -f $latestChecksCsv.FullName)
    }
    else {
        Write-Log "[WARN] No VerifyChecksums CSV by glob: $ChecksumsGlob"
    }
}
catch {
    Write-Log "[ERR] Checksums glob failed: $($_.Exception.Message)"
}

# 2) Побудова Markdown
$lines = @()
$lines += "# Control Summary ($stamp)"
$lines += ""
$lines += "## Weekly"
$lines += ("- Found: {0} file(s)" -f ($weekly.Count))

if ($weekly.Count -gt 0) {
    $last3 = $weekly | Sort-Object LastWriteTime -Desc | Select-Object -First 3
    $lines += ""
    $lines += "| File | LastWriteTime |"
    $lines += "|---|---|"
    foreach ($f in $last3) {
        $lines += ("| `{0}` | {1} |" -f $f.Name, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    }
}

$lines += ""
$lines += "## VerifyChecksums"
if ($latestChecksCsv) {
    $lines += ("- Latest: `{0}` (time: {1})" -f $latestChecksCsv.Name, $latestChecksCsv.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))

    try {
        $csv = Import-Csv -LiteralPath $latestChecksCsv.FullName
        $row = $csv | Select-Object -First 1
        if ($row) {
            # гнучко читаємо можливі колонки
            $ok = $row.Ok
            $anyMismatch = $row.AnyMismatch
            $anyMissing = $row.AnyMissing
            $anyExtras = $row.AnyExtras
            $weeks = $row.WeeksChecked

            $lines += ""
            $lines += "| Metric | Value |"
            $lines += "|---|---|"
            $lines += ("| WeeksChecked | {0} |" -f $weeks)
            $lines += ("| Ok           | {0} |" -f $ok)
            $lines += ("| AnyMismatch  | {0} |" -f $anyMismatch)
            $lines += ("| AnyMissing   | {0} |" -f $anyMissing)
            $lines += ("| AnyExtras    | {0} |" -f $anyExtras)
        }
    }
    catch {
        Write-Log "[WARN] Import-Csv failed: $($_.Exception.Message)"
    }
}
else {
    $lines += "- Latest: <none>"
}

$lines += ""
$lines += "## Notes"
$lines += "- Cycle: Measure → Control → Summary → Archive → LearningFeedback"
$lines += "- Mode: {0}" -f ($(if ($DryRun) { "DryRun" }else { "Write" }))

$md = ($lines -join "`n")

# 3) YAML front-matter (службові поля)
$pairs = @{
    "ControlCycle" = "Build-ControlSummary"
    "DryRun"       = "$DryRun"
    "OutDir"       = "$OutDir"
    "GeneratedAt"  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}
$md = Upsert-YamlFrontmatter -Text $md -Pairs $pairs

# 4) Запис/моделювання
$summaryMd = Join-Path $OutDir ("ControlSummary_{0}.md" -f $stamp)
if ($DryRun) {
    Write-Log ("DRYRUN: would write {0}" -f $summaryMd)
}
else {
    try {
        $md | Set-Content -LiteralPath $summaryMd -Encoding UTF8
        Write-Log ("WROTE: {0}" -f $summaryMd)
    }
    catch {
        Write-Log ("[ERR] Failed to write summary: {0}" -f $_.Exception.Message)
    }
}

# 5) (Опціонально) Інтеграція IntegrityScore
if ($IntegrateIntegrityScore -and -not $DryRun) {
    $updScript = "D:\CHECHA_CORE\TOOLS\Update-IntegrityScore.ps1"
    if (Test-Path -LiteralPath $updScript) {
        Write-Log "Calling Update-IntegrityScore.ps1 …"
        $args = @(
            "-File", $updScript,
            "-ChecksumsCsv", $ChecksumsGlob,
            "-OutCsv", $IntegrityScoreCsv
        )
        try {
            pwsh -NoProfile -ExecutionPolicy Bypass @args
            Write-Log "Update-IntegrityScore.ps1 finished."
        }
        catch {
            Write-Log "[WARN] Update-IntegrityScore failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "[WARN] Update-IntegrityScore.ps1 not found at $updScript"
    }
}

Write-Log "END Build-ControlSummary"
exit 0


