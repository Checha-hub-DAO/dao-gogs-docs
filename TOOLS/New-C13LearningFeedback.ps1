[CmdletBinding()]
param(
    [string]$WeeklyRoot = "D:\CHECHA_CORE\REPORTS\WEEKLY",
    [string]$OutDir = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK",
    [int]$WindowWeeks = 4,
    [string]$LogPath = "D:\CHECHA_CORE\C13_LEARNING_FEEDBACK\logs\New-C13LearningFeedback.log"
)

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line; try { $null = $line | Tee-Object -FilePath $LogPath -Append } catch {}
}

Ensure-Dir $OutDir; Ensure-Dir (Split-Path -Parent $LogPath)
Write-Log "START New-C13LearningFeedback"
Write-Log "WeeklyRoot=$WeeklyRoot; OutDir=$OutDir; WindowWeeks=$WindowWeeks"

# 1) знайти теки тижнів (плоскі і річні)
$rangeRx = '^\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$'
$weekDirs = @()
if (Test-Path $WeeklyRoot) {
    # A) WEEKLY\<range>
    $weekDirs += Get-ChildItem -LiteralPath $WeeklyRoot -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -match $rangeRx }
    # B) WEEKLY\<YYYY>\<range>
    $weekDirs += Get-ChildItem -LiteralPath $WeeklyRoot -Recurse -Directory -EA SilentlyContinue |
        Where-Object { $_.FullName -match '\\\d{4}\\\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$' }
}

if (-not $weekDirs) { Write-Log "[WARN] No weekly dirs found"; exit 0 }

# 2) взяти останні N за ім’ям (дати у назві)
function Parse-Range([string]$name) {
    if ($name -match '^(?<s>\d{4}-\d{2}-\d{2})_to_(?<e>\d{4}-\d{2}-\d{2})$') {
        return [pscustomobject]@{ Start = [datetime]$matches['s']; End = [datetime]$matches['e'] }
    }
    else { return $null }
}
$weeks = $weekDirs | ForEach-Object {
    $rangeName = Split-Path -Leaf $_.FullName
    $r = Parse-Range $rangeName
    if ($r) { [pscustomobject]@{ Dir = $_.FullName; Name = $rangeName; Start = $r.Start; End = $r.End } }
} | Sort-Object Start -Descending | Select-Object -First $WindowWeeks

if (-not $weeks) { Write-Log "[WARN] Unable to parse week ranges"; exit 0 }

# 3) простий аналіз по файліку WeeklyChecklist_<range>.md (якщо нема — інші WeeklyChecklist_*.*)
function Analyze-Week($w) {
    $pathMd = Join-Path $w.Dir ("WeeklyChecklist_{0}.md" -f $w.Name)
    $content = @()
    if (Test-Path $pathMd) {
        $content = Get-Content -LiteralPath $pathMd -ErrorAction SilentlyContinue
    }
    else {
        $fallback = Get-ChildItem -LiteralPath $w.Dir -File -Filter "WeeklyChecklist_*" -EA SilentlyContinue | Select-Object -First 1
        if ($fallback) { $content = Get-Content -LiteralPath $fallback.FullName -EA SilentlyContinue }
    }
    if (-not $content) { return [pscustomobject]@{ Name = $w.Name; Start = $w.Start; End = $w.End; Done = 0; Open = 0; Issues = 0; Notes = 0 } }

    # евристики: 
    $done = ($content | Where-Object { $_ -match '^\s*-\s*\[x\]' }).Count
    $open = ($content | Where-Object { $_ -match '^\s*-\s*\[\s\]' }).Count
    $iss = ($content | Where-Object { $_ -match '(?i)\b(issue|risk|blocker)\b' }).Count
    $notes = ($content | Where-Object { $_ -match '^\s*-\s' }).Count

    [pscustomobject]@{
        Name   = $w.Name; Start=$w.Start; End=$w.End
        Done   = $done
        Open   = $open
        Issues = $iss
        Notes  = $notes
    }
}

$rows = $weeks | ForEach-Object { Analyze-Week $_ }

# 4) тренди / метрики
$sumDone = ($rows | Measure-Object -Property Done  -Sum).Sum
$sumOpen = ($rows | Measure-Object -Property Open  -Sum).Sum
$sumIss = ($rows | Measure-Object -Property Issues -Sum).Sum
$avgDone = [math]::Round((($rows.Done | Measure-Object -Average).Average), 2)
$avgOpen = [math]::Round((($rows.Open | Measure-Object -Average).Average), 2)
$deltaDone = if ($rows.Count -ge 2) { $rows[0].Done - $rows[1].Done } else { 0 }
$deltaOpen = if ($rows.Count -ge 2) { $rows[0].Open - $rows[1].Open } else { 0 }

# 5) збереження
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$csv = Join-Path $OutDir ("C13_LearningFeedback_{0}.csv" -f $ts)
$md = Join-Path $OutDir ("C13_LearningFeedback_{0}.md" -f $ts)
$last = Join-Path $OutDir ("LATEST.md")
$csvL = Join-Path $OutDir ("LATEST.csv")

$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Copy-Item $csv $csvL -Force

$mdBody = @()
$mdBody += "# C13 — Learning Feedback (last $($rows.Count) weeks)"
$mdBody += ""
$mdBody += "*Generated:* $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$mdBody += ""
$mdBody += "## Summary"
$mdBody += "- Total Done: $sumDone (avg=$avgDone; Δweek=$deltaDone)"
$mdBody += "- Total Open: $sumOpen (avg=$avgOpen; Δweek=$deltaOpen)"
$mdBody += "- Issues mentions: $sumIss"
$mdBody += ""
$mdBody += "## Weeks"
foreach ($r in $rows) {
    $mdBody += "- **$($r.Name)**: Done=$($r.Done), Open=$($r.Open), Issues=$($r.Issues)"
}
$mdBody | Set-Content -LiteralPath $md -Encoding UTF8
Copy-Item $md $last -Force

Write-Log "WROTE: $csv"
Write-Log "WROTE: $md"
Write-Log "END New-C13LearningFeedback"

