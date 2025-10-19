<#
.SYNOPSIS
  Оновлює REPORTS індекси: переліки останніх N дайджестів і чеклістів.

.PARAMETER RepoRoot
  Корінь репозиторію (де є папка REPORTS). Default: D:\CHECHA_CORE

.PARAMETER Count
  Скільки останніх файлів показувати у кожному індексі. Default: 5

.PARAMETER DigestPattern
  Маска для пошуку дайджестів. Default: BTD_Manifest_Digest_*.md

.PARAMETER ChecklistPattern
  Маска для пошуку чеклістів. Default: CHECHA_CHECKLIST_*.md
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = 'D:\CHECHA_CORE',
    [int]$Count = 5,
    [string]$DigestPattern = 'BTD_Manifest_Digest_*.md',
    [string]$ChecklistPattern = 'CHECHA_CHECKLIST_*.md'
)

$reportsDir = Join-Path $RepoRoot 'REPORTS'
if (-not (Test-Path $reportsDir)) {
    throw "Не знайдено папку REPORTS: $reportsDir"
}

function Get-LatestFiles {
    param([string]$dir, [string]$pattern, [int]$take)
    if (-not (Test-Path $dir)) { return @() }
    Get-ChildItem -LiteralPath $dir -Filter $pattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $take
}

function New-IndexContent {
    param([string]$title, [string]$desc, [System.IO.FileInfo[]]$files, [string]$relPrefix)
    $md = @()
    $md += "# $title"
    if ($desc) { $md += "`n$desc`n" }
    if (-not $files -or $files.Count -eq 0) {
        $md += "> Поки що немає файлів."
    }
    else {
        $md += "> Останні:"
        foreach ($f in $files) {
            $name = $f.Name
            $rel = (Join-Path $relPrefix $name).Replace('\', '/')
            $date = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            $md += "- [$name]($rel) — _оновлено $date_"
        }
    }
    return ($md -join "`r`n")
}

# ── Останні дайджести
$dFiles = Get-LatestFiles -dir $reportsDir -pattern $DigestPattern -take $Count
$dIndexPath = Join-Path $reportsDir 'BTD_Manifest_Digest_index.md'
$dContent = New-IndexContent `
    -title '📆 Щотижневі дайджести BTD' `
    -desc 'Автоматично оновлюваний список останніх дайджестів.' `
    -files $dFiles `
    -relPrefix '.'

$dContent | Set-Content -LiteralPath $dIndexPath -Encoding UTF8

# ── Останні чеклісти
$cFiles = Get-LatestFiles -dir $reportsDir -pattern $ChecklistPattern -take $Count
$cIndexPath = Join-Path $reportsDir 'CHECHA_CHECKLIST_index.md'
$cContent = New-IndexContent `
    -title '✅ Щотижневі чеклісти' `
    -desc 'Автоматично оновлюваний список останніх чеклістів.' `
    -files $cFiles `
    -relPrefix '.'

$cContent | Set-Content -LiteralPath $cIndexPath -Encoding UTF8

Write-Host "[OK] Оновлено:"
Write-Host " - $dIndexPath"
Write-Host " - $cIndexPath"

