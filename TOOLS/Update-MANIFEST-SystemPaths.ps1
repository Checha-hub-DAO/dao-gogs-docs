[CmdletBinding()]
param(
    [string]$ManifestPath = "D:\CHECHA_CORE\MANIFEST.md",
    [string]$WeeklyRoot = "D:\CHECHA_CORE\REPORTS\WEEKLY",
    [int]$ShowLatestArchives = 5,
    [string]$LogPath = "D:\CHECHA_CORE\C03_LOG\control\Update-MANIFEST-SystemPaths.log"
)

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    $line; try { $null = $line | Tee-Object -FilePath $LogPath -Append } catch {}
}

Ensure-Dir (Split-Path -Parent $ManifestPath)
Ensure-Dir (Split-Path -Parent $LogPath)

Write-Log "START Update-MANIFEST-SystemPaths"
Write-Log "Manifest=$ManifestPath; WeeklyRoot=$WeeklyRoot"

# 1) Зібрати останні архіви
$year = Get-Date -Format 'yyyy'
$archiveDir = Join-Path $WeeklyRoot ("ARCHIVE\{0}" -f $year)

$latestLines = @()
if (Test-Path -LiteralPath $archiveDir) {
    $latest = Get-ChildItem -LiteralPath $archiveDir -File -Filter *.zip -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First $ShowLatestArchives
    if ($latest) {
        foreach ($z in $latest) {
            $sha = "$($z.FullName).sha256"
            $shaTag = (Test-Path -LiteralPath $sha) ? (" | sha256: " + (Split-Path $sha -Leaf)) : " | sha256: —"
            $latestLines += ("- {0} ({1:yyyy-MM-dd HH:mm}){2}" -f (Split-Path $z.FullName -Leaf), $z.LastWriteTime, $shaTag)
        }
    }
    else {
        $latestLines += "- (нема *.zip у $archiveDir)"
    }
}
else {
    $latestLines += "- (нема файлів за $year)"
}

# 2) Побудувати розділ (рядки, що починаються з '-', беремо в лапки)
$section = @()
$section += "<!-- BEGIN SYSTEM PATHS -->"
$section += "## System Paths"
$section += '- Reports: `REPORTS\WEEKLY\<YYYY>\*`'
$section += '- Archives: `REPORTS\WEEKLY\ARCHIVE\<YYYY>\*.zip` + `*.zip.sha256` (post-archive hashing via `Write-ZipSha256`)'
$section += ""
$section += ("### Archive (latest {0})" -f $ShowLatestArchives)
$section += $latestLines
$section += "<!-- END SYSTEM PATHS -->"
$sectionText = ($section -join "`r`n")

# 3) Запис у MANIFEST.md (створити або оновити між маркерами)
$pattern = '<!-- BEGIN SYSTEM PATHS -->.*?<!-- END SYSTEM PATHS -->'
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    $body = @("# MANIFEST", "", $sectionText) -join "`r`n"
    $body | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    Write-Log "[NEW] Created MANIFEST.md with System Paths section."
}
else {
    $content = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $regex = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($regex.IsMatch($content)) {
        $m = $regex.Match($content)
        $updated = $content.Substring(0, $m.Index) + $sectionText + $content.Substring($m.Index + $m.Length)
        Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding UTF8
        Write-Log "[OK] Updated System Paths section."
    }
    else {
        $updated = $content.TrimEnd() + "`r`n`r`n" + $sectionText + "`r`n"
        Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding UTF8
        Write-Log "[OK] Appended System Paths section."
    }
}

Write-Log "END Update-MANIFEST-SystemPaths"

